# OCI Kubernetes (Always Free)

A production-shaped Kubernetes platform on **Always Free** resources in an OCI paid account (Pay As You Go / Universal Credits).

**[📖 한국어 문서](./docs/README-KR.md)**

> **Not Free Tier.**
> Free Tier is a 30-day credit trial. This project uses Always Free resources that remain free indefinitely on a PAYG account — normal usage incurs **no charges**.

## Stack

| Layer | Components | Status |
|-------|-----------|--------|
| IaC | Terraform | done |
| Container | OKE Basic, Flannel Overlay, containerd | done |
| Mesh / Gateway | Gateway API, Istio Ambient, NLB | done |
| DNS | external-dns + Cloudflare | done |
| TLS | cert-manager + Let's Encrypt (DNS-01) | done |
| GitOps | ArgoCD, Jenkins, GHCR | planned |
| Observability | kube-prometheus-stack, Thanos, Loki, Alloy, Tempo, Kiali | planned |
| Security | OpenBao (Vault), Trivy, Kyverno, cosign, PSA, NetworkPolicy | planned |
| App infra | Strimzi/Kafka (KRaft), Redis, HPA + Prometheus Adapter | planned |
| DR / Backup | Velero, OCI Block Volume Backup, Vault Raft Snapshot | planned |
| Test | k6 | planned |

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
            │  │  OCI NLB       │  │  ← provisioned by Gateway API (Istio reconcile)
            │  │  (TCP L4)      │  │
            │  └──────┬─────────┘  │
            └─────────┼────────────┘
                      │ NodePort (30000-32767)
         ┌────────────┼─────────────────────────┐
         │            │                         │
  ┌──────┴──────────┐ │  ┌──────────────────────┴───┐
  │ subnet-oke-api  │ │  │  subnet-workers           │
  │ 10.0.0.0/28     │ │  │  10.0.102.0/24            │
  │                 │ │  │                           │
  │  ┌───────────┐  │ │  │  ┌─────────────────────┐  │
  │  │ OKE       │◄─┼─┘  │  │  Node Pool          │  │
  │  │ Control   │◄─┼────┼──│  2× VM.Standard     │  │
  │  │ Plane API │  │    │  │     .A1.Flex        │  │
  │  │ (managed) │  │    │  │  2 OCPU / 12GB each │  │
  │  └───────────┘  │    │  └──────────┬──────────┘  │
  └─────────────────┘    └─────────────┼─────────────┘
                                       │
                               [ NAT Gateway ]
                               [ Service GW  ]
                                       │
                           ┌───────────┴────────┐
                           │  subnet-db         │
                           │  10.0.201.0/28     │
                           │                    │
                           │  ┌──────────────┐  │
                           │  │  HeatWave    │  │
                           │  │  MySQL Free  │  │
                           │  └──────────────┘  │
                           └────────────────────┘
```

## Always Free Usage

| Resource | Current Usage | Always Free Limit | Remaining |
|----------|---------------|-------------------|-----------|
| VM.Standard.A1.Flex | 4 OCPU / 24 GB (2 nodes) | 4 OCPU / 24 GB | At limit |
| OKE Basic Cluster | 1× (free control plane) | — | — |
| MySQL HeatWave | 1×, 50 GB | 1×, 50 GB | — |
| Network Load Balancer | 1× (Istio Gateway, L4) | 1× | — |
| Flexible Load Balancer | 0× | 1×, 10 Mbps | 1× |
| VCN | 1× | 2× | 1× |

> OKE Basic Cluster control plane is free. Workers use the Always Free A1.Flex quota.
> A PAYG account is required — OKE is not available in Free Tier.

Full catalog: [`docs/summary.md`](./docs/summary.md).

## Directory

```
.
├── terraform/                  # OCI infra (VCN, OKE, MySQL, IAM/NSG)
│   ├── modules/{networking,oke,database,iam}/
│   └── README.md
├── kubernetes/                 # K8s manifests
│   ├── infra/                  # Bootstrap infra
│   │   ├── namespaces/
│   │   ├── gateway-api/
│   │   ├── istio/
│   │   ├── external-dns/
│   │   ├── cert-manager/
│   │   └── README.md
│   ├── test/                   # One-shot validation
│   └── README.md
└── docs/
    ├── README-KR.md            # Korean mirror
    ├── summary.md              # Always Free catalog (EN)
    └── summary-kr.md           # Always Free catalog (KR)
```

## Quick Start

### 1. Provision OCI infrastructure

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in OCIDs, region, SSH key, etc.
terraform init
terraform apply
```

Details: [`terraform/README.md`](./terraform/README.md).

### 2. Configure kubectl

```bash
oci ce cluster create-kubeconfig \
  --cluster-id "$(terraform output -raw oke_cluster_id)" \
  --file ~/.kube/config \
  --region <your-region> \
  --token-version 2.0.0

kubectl get nodes
```

### 3. Bootstrap Kubernetes infra

Install in order: `namespaces` → `gateway-api` → `istio` (core) → `external-dns` → `cert-manager` → `istio` (Gateway HTTPS).

Details: [`kubernetes/infra/README.md`](./kubernetes/infra/README.md).

## Network Layout

| Subnet | CIDR | Type | Purpose |
|--------|------|------|---------|
| subnet-oke-api | 10.0.0.0/28 | Public | OKE API endpoint |
| subnet-public | 10.0.1.0/28 | Public | OCI Load Balancer / NLB |
| subnet-workers | 10.0.102.0/24 | Private | Worker nodes |
| subnet-db | 10.0.201.0/28 | Private | HeatWave MySQL |

Security list + NSG rules: see `terraform/modules/networking` and `terraform/modules/iam`.

## Network Bandwidth

| Link | Bandwidth | Notes |
|------|-----------|-------|
| A1 Instance (per OCPU) | 1 Gbps | 2 OCPU node = 2 Gbps |
| Network Load Balancer | A1 quota bound | L4 passthrough, no fixed cap |
| Flexible Load Balancer | 10 Mbps | (unused; if used, this is the bottleneck) |
| Outbound | 10 TB/month free | Charged beyond limit; inbound is free |

Intra-VCN traffic (worker↔worker, worker↔DB) uses full instance bandwidth.

## OKE Basic vs Enhanced

| Feature | Basic | Enhanced |
|---------|-------|----------|
| Price | **Free** | $0.10/hr |
| Virtual Nodes | ✗ | ✓ |
| OKE Add-ons | ✗ | ✓ |
| Control Plane SLA | ✗ | ✓ |
| CNI | Flannel Overlay | Flannel / VCN-Native |

Basic Cluster is sufficient for personal projects and non-production workloads.

## Fork Setup

For fork users — swap hard-coded values to your own.

### Change the apex domain

`init.sh` replaces every `ggang.cloud` occurrence across yaml/markdown/scripts. `admin@ggang.cloud` is rewritten as a side effect.

```bash
./init.sh your-domain.example
git diff --stat
```

GNU sed assumed (Linux / git-bash on Windows). macOS users: install `gnu-sed` via Homebrew or run the equivalent `sed -i ''` manually.

### Create `kubernetes/.env`

Holds tokens that never enter git (`*.env` is gitignored). Source it before running any Secret-creating command.

```bash
cat > kubernetes/.env <<EOF
export jenkins=<jenkins-admin-token-or-leave-empty-on-first-install>
export GHCR_TOKEN=<your-ghcr-write-token>
export GHCR_USER=<your-github-user>
EOF

source kubernetes/.env
```

Cloudflare API tokens are not in `.env` — generated per-component and passed inline to `kubectl create secret` (see `kubernetes/infra/cert-manager/`, `kubernetes/infra/external-dns/`).

## Conventions

- **Placeholders**: `<your-cf-token>`, `<your-region>`, `<your-github-user>`, `<your-ghcr-write-token>` — secret-grade values, injected at Secret creation time. Apex domain (`ggang.cloud`) and admin email (`admin@ggang.cloud`) are hard-coded in git. See each component README.
- **Secrets**: `*.env`, `*.local.*`, `*.tfvars`, `*.pem`, `*.ppk`, `*.pub` are gitignored. Personal values never enter git.
- **README structure**: every component folder follows 5 sections — Prerequisites / Setup / Verification / Decisions / Notes.
- **Helm versions**: pinned via SemVer tilde (`~X.Y.0`) — patch-level auto-follow, minor requires explicit bump.
