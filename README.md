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
            │  │  OCI LB        │  │  ← provisioned by OKE (Service type: LoadBalancer)
            │  │  (10Mbps)      │  │
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
  │  │ Control   │◄─┼────┼──│  2x VM.Standard     │  │
  │  │ Plane API │  │    │  │    .A1.Flex          │  │
  │  │ (managed) │  │    │  │  2 OCPU / 12GB each  │  │
  │  └───────────┘  │    │  └──────────┬──────────┘  │
  └─────────────────┘    └─────────────┼─────────────┘
                                       │
                               [ NAT Gateway ]
                               [ Svc Gateway ]
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

## Always Free Resource Usage

| Resource | Current Usage | Always Free Limit | Remaining |
|----------|---------------|-------------------|-----------|
| VM.Standard.A1.Flex | 4 OCPU / 24GB (2 nodes × 2C/12GB) | 4 OCPU / 24GB | At limit |
| OKE Basic Cluster | 1x (free control plane) | — | — |
| MySQL HeatWave | 1x, 50GB | 1x, 50GB | — |
| Load Balancer | 1x, 10Mbps (via OKE Service) | 1x, 10Mbps | — |
| VCN | 1x | 2x | 1x |

> OKE Basic Cluster control plane is free. Worker nodes use the Always Free A1.Flex quota.
> A PAYG (Pay As You Go) account is required — OKE is not available in Free Tier accounts.

## Directory Structure

```
.
├── README.md
├── docs/
│   ├── README-KR.md          # 한국어 문서
│   ├── architecture.html     # Infrastructure architecture diagram
│   └── summary.md            # Always Free resource summary
└── terraform/
    ├── main.tf                   # Module calls and dependencies
    ├── provider.tf               # OCI Provider configuration
    ├── variables.tf              # Root variables
    ├── outputs.tf                # Root outputs
    ├── terraform.tfvars.example  # Example configuration
    ├── modules/
    │   ├── networking/           # VCN, Subnets, Route Tables, Security Lists, Bastion
    │   ├── oke/                  # OKE Basic Cluster + ARM Node Pool + dynamic image lookup
    │   │   └── scripts/
    │   │       └── node_pool_init.sh  # Cloud-init bootstrap script
    │   ├── database/             # HeatWave MySQL Free
    │   └── iam/                  # (Reserved) Dynamic Group, Policy
```

## Dependency Graph

```
networking ──┬──► oke
             │
             └──► database
```

## Subnet Layout

| Subnet | CIDR | Type | Purpose |
|--------|------|------|---------|
| subnet-oke-api | 10.0.0.0/28 | Public | OKE API endpoint |
| subnet-public | 10.0.1.0/28 | Public | OCI Load Balancer (Service LB) |
| subnet-workers | 10.0.102.0/24 | Private | OKE worker nodes |
| subnet-db | 10.0.201.0/28 | Private | HeatWave MySQL |

## Network Policy

| Source | Destination | Protocol | Port |
|--------|-------------|----------|------|
| Internet | subnet-oke-api | TCP | 6443 (kubectl) |
| Internet | subnet-public | TCP | 80, 443 |
| subnet-oke-api | subnet-workers | ALL | Control plane → workers |
| subnet-oke-api | OCI Services (SGW) | TCP | 443 |
| subnet-public (LB) | subnet-workers | TCP | 30000–32767 (NodePort) |
| subnet-public (LB) | subnet-workers | TCP | 10256 (health check) |
| subnet-workers | subnet-oke-api | TCP | 6443, 12250 |
| subnet-workers ↔ subnet-workers | — | ALL | Pod-to-Pod (Flannel VXLAN) |
| subnet-workers | subnet-db | TCP | 3306 (MySQL) |
| subnet-workers | Internet (NAT) | ALL | Image pull, updates |
| subnet-workers | OCI Services (SGW) | ALL | OCI internal services |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (for kubeconfig setup)
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
private_key_path      = "./secrets/oci-api-key.pem"
region                = "ap-tokyo-1"
compartment_ocid      = "ocid1.compartment.oc1..aaaa..."
ssh_authorized_keys   = "ssh-rsa AAAA... user@host"
db_admin_password     = "MyStr0ng#Pass!"
kubernetes_version    = "v1.34.2"
```

> The Oracle Linux ARM node image is automatically resolved for your region.
> Override `kubernetes_version` if the default is not available in your OKE region.

### 2. Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. Access the Cluster

```bash
# Configure kubectl (run after apply)
oci ce cluster create-kubeconfig \
  --cluster-id <oke_cluster_id> \
  --file ~/.kube/config \
  --region ap-tokyo-1 \
  --token-version 2.0.0

kubectl get nodes
```

### 4. Destroy

```bash
cd terraform
terraform destroy
```

## Variables

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `tenancy_ocid` | string | Yes | — | OCI tenancy OCID |
| `user_ocid` | string | Yes | — | OCI user OCID |
| `fingerprint` | string | Yes | — | API Key fingerprint |
| `private_key_path` | string | Yes | — | API Key PEM file path |
| `region` | string | Yes | — | OCI region |
| `compartment_ocid` | string | Yes | — | Target compartment OCID |
| `ssh_authorized_keys` | string | Yes | — | Worker node SSH public key |
| `db_admin_password` | string | Yes | — | MySQL admin password (sensitive) |
| `kubernetes_version` | string | No | `"v1.34.2"` | Kubernetes version |

## Outputs

| Output | Description |
|--------|-------------|
| `vcn_id` | VCN OCID |
| `subnet_oke_api_id` | OKE API subnet OCID |
| `subnet_pub_id` | Public (LB) subnet OCID |
| `subnet_workers_id` | Worker subnet OCID |
| `subnet_db_id` | DB subnet OCID |
| `oke_cluster_id` | OKE cluster OCID |
| `oke_cluster_endpoint` | OKE API public endpoint |
| `oke_node_pool_id` | Node pool OCID |
| `heatwave_ip` | MySQL connection IP |
| `heatwave_port` | MySQL connection port |

## Network Bandwidth

| Link | Bandwidth | Notes |
|------|-----------|-------|
| A1 Instance (per OCPU) | 1 Gbps / OCPU | 2 OCPU node = 2 Gbps |
| Load Balancer | 10 Mbps | Always Free Flexible LB fixed |
| Outbound Data Transfer | 10 TB/month free | Charged beyond limit; inbound is free |

- The LB is the bottleneck at 10 Mbps for external traffic.
- Internal cluster traffic (worker ↔ worker, worker ↔ DB) is intra-VCN and uses full instance bandwidth.

## OKE Basic Cluster Limitations

| Feature | Basic Cluster | Enhanced Cluster |
|---------|--------------|-----------------|
| Price | **Free** | $0.10/hr |
| Virtual Nodes | ✗ | ✓ |
| OKE Add-ons | ✗ | ✓ |
| Control Plane SLA | ✗ | ✓ |
| CNI | Flannel Overlay | Flannel / OCI VCN-Native |

> For personal projects and non-production workloads, Basic Cluster is sufficient.
