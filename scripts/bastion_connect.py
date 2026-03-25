"""SSH to master node via OCI Bastion Port Forwarding.

Usage:
  python bastion_connect.py                    # ssh (default)
  python bastion_connect.py --putty            # PuTTY
  python bastion_connect.py --putty --ppk C:\\key.ppk
"""

import argparse
import json
import os
import socket
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

STEP = 0
SESSION_CACHE_FILE = os.path.join(os.path.dirname(__file__), ".bastion_session.json")
SESSION_MIN_REMAINING_SEC = 3600  # Create new session if less than 1 hour remaining


def step(msg: str):
    global STEP
    STEP += 1
    print(f"\n[{STEP}] {msg}")


def progress(msg: str):
    print(f"    ..{msg}")


def find_exe(name: str) -> str:
    """Find executable path. Also searches Windows Store Python Scripts directory."""
    found = shutil.which(name)
    if found:
        return found
    for base in sys.path:
        candidate = os.path.join(base, "Scripts", f"{name}.exe")
        if os.path.exists(candidate):
            return candidate
    local_packages = os.path.expandvars(r"%LOCALAPPDATA%\Packages")
    if os.path.isdir(local_packages):
        for d in os.listdir(local_packages):
            if "Python" in d:
                candidate = os.path.join(
                    local_packages, d,
                    "LocalCache", "local-packages",
                    f"Python{sys.version_info.major}{sys.version_info.minor}",
                    "Scripts", f"{name}.exe",
                )
                if os.path.exists(candidate):
                    return candidate
    return name


OCI_EXE = find_exe("oci")


def resolve_key_path(key_arg: str) -> str:
    """Resolve key path: retry with .pem extension if file not found."""
    path = os.path.expanduser(key_arg)
    if os.path.exists(path):
        return path
    pem_path = path + ".pem"
    if os.path.exists(pem_path):
        return pem_path
    return path  # Return original path even if missing (error handled later)


def verify_tunnel(local_port: int, tunnel: subprocess.Popen, timeout: int = 15) -> None:
    """Verify tunnel is open. Success when SSH banner (SSH-2.0-...) is received."""
    progress("Verifying tunnel...")
    for i in range(timeout):
        time.sleep(1)
        if tunnel.poll() is not None:
            stderr = tunnel.stderr.read().decode() if tunnel.stderr else ""
            print(f"    ERROR: Tunnel process exited (exit={tunnel.returncode})", file=sys.stderr)
            if stderr:
                print(f"    {stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(2)
            sock.connect(("127.0.0.1", local_port))
            banner = sock.recv(256).decode(errors="replace").strip()
            sock.close()
            if banner.startswith("SSH-"):
                progress(f"Tunnel verified! ({i+1}s)")
                progress(f"Banner: {banner}")
                return
            else:
                progress(f"Response received, not SSH: {banner[:50]}")
        except (ConnectionRefusedError, socket.timeout, OSError):
            progress(f"Waiting... ({i+1}/{timeout}s)")
            continue

    print(f"    ERROR: Tunnel did not open within {timeout}s.", file=sys.stderr)
    tunnel.terminate()
    sys.exit(1)


def run(cmd: list[str]) -> str:
    if cmd[0] == "oci":
        cmd = [OCI_EXE] + cmd[1:]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"    ERROR: {' '.join(cmd)}", file=sys.stderr)
        print(f"    {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def terraform_output(name: str) -> str:
    return run(["terraform", "output", "-raw", name])


def save_session(data: dict) -> None:
    with open(SESSION_CACHE_FILE, "w") as f:
        json.dump(data, f, indent=2)


def load_session(bastion_id: str, master_id: str) -> dict | None:
    """Load session from cache. Returns None if infra mismatch, <1h remaining, or not ACTIVE."""
    if not os.path.exists(SESSION_CACHE_FILE):
        return None
    try:
        with open(SESSION_CACHE_FILE) as f:
            data = json.load(f)

        session_id = data.get("id")
        if not session_id:
            return None

        # Verify cached session matches current infrastructure
        cached_bastion = data.get("bastion-id", "")
        cached_target = data.get("target-resource-details", {}).get("target-resource-id", "")
        if cached_bastion != bastion_id:
            progress("Bastion ID mismatch -> creating new session")
            return None
        if cached_target != master_id:
            progress("Master ID mismatch -> creating new session")
            return None

        # Query current state via OCI API
        result = run(["oci", "bastion", "session", "get", "--session-id", session_id])
        fresh = json.loads(result)["data"]
        state = fresh.get("lifecycle-state")

        if state != "ACTIVE":
            progress(f"Cached session state: {state} -> creating new session")
            return None

        # Check expiration
        expire_str = fresh.get("time-ttl-expires") or fresh.get("lifecycle-details", "")
        if expire_str:
            try:
                expire_dt = datetime.fromisoformat(expire_str.replace("Z", "+00:00"))
                now = datetime.now(timezone.utc)
                remaining = (expire_dt - now).total_seconds()
                progress(f"Cached session remaining: {int(remaining // 60)}min")
                if remaining < SESSION_MIN_REMAINING_SEC:
                    progress("Less than 1 hour remaining -> creating new session")
                    return None
            except Exception:
                pass

        progress(f"Reusing cached session: {session_id[:40]}...")
        return fresh

    except Exception as e:
        progress(f"Cache load failed: {e} -> creating new session")
        return None


def create_bastion_session(bastion_id: str, master_id: str, pub_key_path: str, ttl: int) -> dict:
    step("Bastion session check")

    cached = load_session(bastion_id, master_id)
    if cached:
        return cached

    progress("Calling OCI API...")
    session_json = run([
        "oci", "bastion", "session", "create-port-forwarding",
        "--bastion-id", bastion_id,
        "--target-resource-id", master_id,
        "--target-port", "22",
        "--key-type", "PUB",
        "--ssh-public-key-file", pub_key_path,
        "--session-ttl", str(ttl),
    ])
    data = json.loads(session_json)["data"]
    session_id = data["id"]
    progress(f"Session created: {session_id[:40]}...")

    step("Waiting for session activation")
    for i in range(60):
        result = run(["oci", "bastion", "session", "get", "--session-id", session_id])
        data = json.loads(result)["data"]
        state = data["lifecycle-state"]

        if state == "ACTIVE":
            progress("Activation complete!")
            save_session(data)
            progress(f"Session cached: {SESSION_CACHE_FILE}")
            return data
        elif state in ("FAILED", "DELETED"):
            print(f"    ERROR: Session {state}", file=sys.stderr)
            sys.exit(1)
        else:
            elapsed = (i + 1) * 5
            progress(f"{state} ({elapsed}s elapsed...)")
            time.sleep(5)

    print("    ERROR: Session activation timeout (5min)", file=sys.stderr)
    sys.exit(1)


def connect_ssh(data: dict, key_path: str, local_port: int):
    session_id = data["id"]
    target_ip = data["target-resource-details"]["target-resource-private-ip-address"]
    bastion_id = data["bastion-id"]
    region = bastion_id.split(".")[3]
    bastion_host = f"host.bastion.{region}.oci.oraclecloud.com"

    step(f"SSH tunnel (localhost:{local_port} -> {target_ip}:22)")
    tunnel_cmd = [
        "ssh",
        "-i", key_path,
        "-N",
        "-L", f"{local_port}:{target_ip}:22",
        "-p", "22",
        "-o", "StrictHostKeyChecking=no",
        f"{session_id}@{bastion_host}",
    ]
    progress(f"{' '.join(tunnel_cmd)}")
    tunnel = subprocess.Popen(tunnel_cmd, stderr=subprocess.PIPE)
    verify_tunnel(local_port, tunnel)

    step(f"SSH connect (localhost:{local_port})")
    ssh_cmd = [
        "ssh",
        "-i", key_path,
        "-p", str(local_port),
        "-o", "StrictHostKeyChecking=no",
        "rocky@localhost",
    ]
    progress(f"{' '.join(ssh_cmd)}")
    print()
    subprocess.run(ssh_cmd)
    tunnel.terminate()
    progress("Tunnel closed.")


def connect_putty(data: dict, ppk_path: str, local_port: int):
    step("PuTTY environment check")
    plink = shutil.which("plink")
    putty = shutil.which("putty")

    if not plink and not putty:
        print("    ERROR: Neither PuTTY (putty.exe) nor Plink (plink.exe) found in PATH.", file=sys.stderr)
        sys.exit(1)

    progress(f"plink: {plink or 'not found'}")
    progress(f"putty: {putty or 'not found'}")

    session_id = data["id"]
    target_ip = data["target-resource-details"]["target-resource-private-ip-address"]
    bastion_id = data["bastion-id"]
    region = bastion_id.split(".")[3]
    bastion_host = f"host.bastion.{region}.oci.oraclecloud.com"

    step("Register Bastion host key")
    progress(f"Host: {bastion_host}")
    hostkey_cmd = [
        plink or "plink",
        "-i", ppk_path,
        "-P", "22",
        "-batch",
        f"{session_id}@{bastion_host}",
        "exit",
    ]
    result = subprocess.run(hostkey_cmd, capture_output=True, text=True, timeout=10)
    if result.returncode != 0 and "host key" in result.stderr.lower():
        progress("Auto-accepting host key...")
        accept_cmd = [
            plink or "plink",
            "-i", ppk_path,
            "-P", "22",
            f"{session_id}@{bastion_host}",
        ]
        subprocess.run(accept_cmd, input="y\n", capture_output=True, text=True, timeout=15)
        progress("Host key registered.")
    else:
        progress("Host key already registered.")

    step(f"Plink tunnel (localhost:{local_port} -> {target_ip}:22)")
    tunnel_cmd = [
        plink or "plink",
        "-i", ppk_path,
        "-N",
        "-batch",
        "-L", f"{local_port}:{target_ip}:22",
        "-P", "22",
        f"{session_id}@{bastion_host}",
    ]
    progress(f"{' '.join(tunnel_cmd)}")
    tunnel = subprocess.Popen(tunnel_cmd, stderr=subprocess.PIPE)

    progress("Checking tunnel connection...")
    for i in range(15):
        time.sleep(1)
        if tunnel.poll() is not None:
            stderr = tunnel.stderr.read().decode() if tunnel.stderr else ""
            print(f"    ERROR: Plink tunnel failed (exit={tunnel.returncode})", file=sys.stderr)
            if stderr:
                print(f"    {stderr.strip()}", file=sys.stderr)
            sys.exit(1)
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            sock.connect(("127.0.0.1", local_port))
            sock.close()
            progress(f"Tunnel open! ({i+1}s)")
            break
        except (ConnectionRefusedError, socket.timeout, OSError):
            if i < 14:
                progress(f"Waiting... ({i+1}s)")
            continue
    else:
        print("    ERROR: Tunnel did not open within 15s.", file=sys.stderr)
        tunnel.terminate()
        sys.exit(1)

    step(f"PuTTY connect (localhost:{local_port})")
    if putty:
        connect_cmd = [putty, "-i", ppk_path, "-P", str(local_port), "rocky@localhost"]
    else:
        connect_cmd = [plink, "-i", ppk_path, "-P", str(local_port), "rocky@localhost"]

    progress(f"{' '.join(connect_cmd)}")
    print()
    subprocess.run(connect_cmd)
    tunnel.terminate()
    progress("Tunnel closed.")


def main():
    parser = argparse.ArgumentParser(description="OCI Bastion SSH connection")
    parser.add_argument("--key", default=r"~\.ssh\id_rsa", help="SSH private key path (OpenSSH, .pem optional)")
    parser.add_argument("--putty", action="store_true", help="Connect via PuTTY/Plink")
    parser.add_argument("--ppk", help="PuTTY private key (.ppk) path")
    parser.add_argument("--ttl", type=int, default=10800, help="Session TTL in seconds (default: 3h)")
    parser.add_argument("--port", type=int, default=2222, help="Local port forwarding port (default: 2222)")
    parser.add_argument("--clear", action="store_true", help="Delete cached session")
    args = parser.parse_args()

    if args.clear:
        if os.path.exists(SESSION_CACHE_FILE):
            os.remove(SESSION_CACHE_FILE)
            print("Session cache deleted.")
        else:
            print("No cache file found.")
        return

    if args.putty and args.ppk:
        ppk_path = os.path.expanduser(args.ppk)
        base = os.path.splitext(ppk_path)[0]
        key_path = resolve_key_path(args.key) if args.key != r"~\.ssh\id_rsa" else base
        pub_key_path = base + ".pub"
    else:
        key_path = resolve_key_path(args.key)
        base = key_path if not key_path.endswith(".pem") else key_path[:-4]
        pub_key_path = base + ".pub"

    step("Key file check")
    if not os.path.exists(pub_key_path):
        print(f"    ERROR: SSH public key not found: {pub_key_path}", file=sys.stderr)
        sys.exit(1)
    progress(f"Public key: {pub_key_path}")

    if not os.path.exists(key_path):
        print(f"    ERROR: SSH private key not found: {key_path}", file=sys.stderr)
        sys.exit(1)
    progress(f"Private key: {key_path}")

    if args.putty:
        ppk_path = ppk_path if args.ppk else base + ".ppk"
        if not os.path.exists(ppk_path):
            print(f"    ERROR: PPK file not found: {ppk_path}", file=sys.stderr)
            print("    Convert with PuTTYgen: puttygen id_rsa -o id_rsa.ppk", file=sys.stderr)
            sys.exit(1)
        progress(f"PPK: {ppk_path}")

    step("Terraform output lookup")
    bastion_id = terraform_output("bastion_id")
    progress(f"Bastion: {bastion_id[:40]}...")
    master_id = terraform_output("master_instance_id")
    progress(f"Master ID: {master_id[:40]}...")
    master_ip = terraform_output("master_private_ip")
    progress(f"Master IP: {master_ip}")

    data = create_bastion_session(bastion_id, master_id, pub_key_path, args.ttl)

    if args.putty:
        connect_putty(data, ppk_path, args.port)
    else:
        connect_ssh(data, key_path, args.port)

    print(f"\nDone. ({STEP} steps)")


if __name__ == "__main__":
    main()
