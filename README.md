# OCI Kubernetes Cluster (Always Free)

Kubernetes cluster provisioned entirely with **Always Free resources** in an OCI **paid account** (Pay As You Go / Universal Credits).

**[📖 한국어 문서](./docs/README-KR.md)**

> **This is NOT Free Tier.**
> Free Tier provides limited trial credits (30 days).
> This project uses only Always Free resources permanently included in paid accounts, so **there are no charges** for normal usage.

## Architecture

```
                    Internet
                       |
              [ Internet Gateway ]
                       |
            ┌──────────────────────┐
            │  subnet-public       │
            │  10.0.1.0/28         │
            │                      │
            │  ┌────────────────┐  │
            │  │  Load Balancer │  │
            │  │  (10Mbps)      │  │
            │  └──────┬─────────┘  │
            └─────────┼────────────┘
                      │ :80 → :30080
         ┌────────────┼────────────────────┐
         │            │                    │
  ┌──────┴───────────┐   ┌──────────────────────────┐
  │ subnet-masters   │   │  subnet-workers          │
  │ 10.0.101.0/28    │   │  10.0.102.0/24           │
  │                  │   │                          │
  │  ┌────────────┐  │   │  ┌────────────────────┐  │
  │  │ master-01  │  │   │  │  Instance Pool     │  │
  │  │ 1C / 6GB   │◄─┼───┼──│  2~3 x 1C / 6GB    │  │
  │  └────────────┘  │   │  └────────────────────┘  │
  │        │         │   │           │              │
  │  [ Bastion ]     │   │           │              │
  └────────┼─────────┘   └───────────┼──────────────┘
           │                         │
    [ NAT Gateway ]                  │
           │                         │
           └─────────────┬───────────┘
                         │ :3306
              ┌──────────┴─────────┐
              │  subnet-db         │
              │  10.0.201.0/28     │
              │                    │
              │  ┌──────────────┐  │
              │  │  HeatWave    │  │
              │  │  MySQL Free  │  │
              │  └──────────────┘  │
              └────────────────────┘
```

## Always Free Resource Usage

| Resource | Current Usage | Always Free Limit | Remaining |
|----------|---------------|-------------------|-----------|
| VM.Standard.A1.Flex | 3 OCPU / 18GB (default) | 4 OCPU / 24GB | 1C / 6GB |
| (Autoscaling max) | 4 OCPU / 24GB | 4 OCPU / 24GB | At limit |
| Load Balancer (Flexible) | 1x, 10Mbps | 1x, 10Mbps | - |
| MySQL HeatWave | 1x, 50GB | 1x, 50GB | - |
| VCN | 1x | 2x | 1x |
| OCI Vault | 1 vault, 1 key | 20 keys | 19 keys |
| Bastion | 1x | 5x | 4x |

## Module Structure

```
.
├── main.tf                          # Module calls and dependencies
├── provider.tf                      # OCI Provider configuration
├── variables.tf                     # Root variables
├── outputs.tf                       # Root outputs
├── modules/
│   ├── networking/                  # VCN, Subnet, Security List, Bastion
│   ├── iam/                         # Dynamic Group, Policy, Vault, Key
│   ├── loadbalancer/                # Load Balancer, Backend Set, Listener
│   ├── database/                    # HeatWave MySQL
│   └── compute/                     # Master Instance, Worker Pool, Autoscaling
└── scripts/
    ├── cloud-init-master.sh         # Master initialization (kubeadm init, SSH join)
    ├── cloud-init-worker.sh         # Worker initialization (SSH accept, kubeadm join)
    └── bastion_connect.py           # Bastion SSH connection helper
```

## Dependency Graph

```
networking ──┬──► loadbalancer ──┐
             │                   │
             ├──► database       │
             │                   ▼
compute ──────────────────────────┘
(depends_on: master → worker pool)
```

Key module dependencies:

- Worker Instance Pool depends on Master Instance with `depends_on`
- Master node initializes first, then discovers and joins worker nodes via nmap + SSH

## Cluster Bootstrap Flow

```
terraform apply
 │
 ├── networking (VCN, Subnet, Security List, Bastion)
 ├── loadbalancer (LB, Backend Set, Listener)
 ├── database (HeatWave MySQL)
 │
 └── compute
      │
      ├── master-01 created (1 OCPU / 6GB — control plane min recommended 2 OCPU)
      │   └── cloud-init:
      │       ├── containerd + kubeadm install
      │       ├── kubeadm init (CNI: Calico, --ignore-preflight-errors=NumCPU)
      │       ├── Install nmap
      │       └── Periodic SSH join to worker nodes (systemd timer: 1min interval)
      │
      └── worker pool created (after master)
          └── cloud-init:
              ├── containerd + kubeadm install
              └── Accept master SSH key, wait for join command
                  (systemd timer: polls for join, retries every 1min)

Join token auto-refreshed every 23 hours on master (systemd timer)
```

## Network Policy

| Source | Destination | Protocol | Port |
|--------|-------------|----------|------|
| Internet | subnet-public | TCP | 80, 443 |
| subnet-public (LB) | subnet-workers | TCP | 30080 (NodePort) |
| subnet-masters | subnet-workers | ALL | - |
| subnet-workers | subnet-masters | ALL | - |
| subnet-workers | subnet-workers | ALL | (inter-Pod) |
| subnet-masters | subnet-db | TCP | 3306 |
| subnet-workers | subnet-db | TCP | 3306 |
| subnet-masters, workers | Internet (NAT) | ALL | (image pull, etc.) |

## Autoscaling

Worker Instance Pool uses CPU-based autoscaling.

| Rule | Condition | Action |
|------|-----------|--------|
| Scale-out | CPU > 70% | +1 (max 3) |
| Scale-in | CPU < 30% | -1 (min 2) |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (for Bastion connection)
- OCI paid account (Pay As You Go or Universal Credits)
- OCI API Key (.pem)
- SSH key pair

## Usage

### 1. Create Configuration

```hcl
# terraform.tfvars
tenancy_ocid          = "ocid1.tenancy.oc1..aaaa..."
user_ocid             = "ocid1.user.oc1..aaaa..."
fingerprint           = "aa:bb:cc:dd:ee:ff:..."
private_key_path      = "~/.oci/oci_api_key.pem"
region                = "ap-tokyo-1"
compartment_ocid      = "ocid1.compartment.oc1..aaaa..."
ssh_authorized_keys   = "ssh-rsa AAAA... user@host"
db_admin_password     = "MyStr0ng#Pass!"
bastion_allowed_cidrs = ["YOUR_IP/32"]
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply
```

### 3. SSH to Master

```bash
# OpenSSH
python scripts/bastion_connect.py --key ~/.ssh/id_rsa

# PuTTY (Windows)
python scripts/bastion_connect.py --putty --ppk C:\path\to\key.ppk
```

### 4. Destroy

```bash
terraform destroy
```

## Network Bandwidth

OCI Always Free network bandwidth varies by resource type.

| Link | Bandwidth | Notes |
|------|-----------|-------|
| A1 Instance (per OCPU) | 1 Gbps / OCPU | master 1C = 1Gbps, worker 1C = 1Gbps |
| Load Balancer | 10 Mbps | Always Free Flexible LB fixed |
| NAT Gateway | Unlimited (instance bandwidth applies) | Outbound traffic charged separately |
| Outbound Data Transfer | **10TB/month free** | Charged beyond limit, inbound free |

- LB bottleneck is 10Mbps, so external traffic is effectively **~10Mbps max**.
- Internal cluster traffic (master ↔ worker, worker ↔ DB) is intra-VCN, can use full instance bandwidth (1Gbps).
- 10TB outbound rarely exceeded in typical K8s workloads, but monitor if serving large files.

## Variables

| Variable | Type | Required | Description |
|----------|------|----------|-------------|
| `tenancy_ocid` | string | Yes | OCI tenancy OCID |
| `user_ocid` | string | Yes | OCI user OCID |
| `fingerprint` | string | Yes | API Key fingerprint |
| `private_key_path` | string | Yes | API Key PEM file path |
| `region` | string | Yes | OCI region |
| `compartment_ocid` | string | Yes | Target compartment OCID |
| `ssh_authorized_keys` | string | Yes | Instance SSH public key |
| `db_admin_password` | string | Yes | MySQL admin password (sensitive) |
| `bastion_allowed_cidrs` | list(string) | Yes | Bastion access CIDR list |
| `image_id` | string | No | Compute image OCID (default: Rocky Linux 9 aarch64) |

## Outputs

| Output | Description |
|--------|-------------|
| `lb_ip` | Load Balancer public IP |
| `master_private_ip` | Master node private IP |
| `bastion_id` | Bastion service OCID |
| `heatwave_ip` | MySQL connection IP |
| `heatwave_port` | MySQL connection port |
