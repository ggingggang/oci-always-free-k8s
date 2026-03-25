# OCI Kubernetes Cluster (Always Free)

OCI **유료 계정**(Pay As You Go / Universal Credits)에서 **Always Free 리소스만** 사용하여 구성한 Kubernetes 클러스터.

**[📖 English Docs](../README.md)**

> **Free Tier(무료 체험)가 아닙니다.**
> Free Tier는 30일 한정 크레딧이 제공되는 체험 계정입니다.
> 본 프로젝트는 유료 계정에 영구적으로 포함되는 Always Free 리소스만 활용하므로, 정상적으로 사용하는 한 **과금이 발생하지 않습니다.**

## 아키텍처

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

## Always Free 리소스 사용량

| 리소스 | 사용량 | Always Free 한도 | 여유 |
|--------|--------|-------------------|------|
| VM.Standard.A1.Flex | 3 OCPU / 18GB (기본) | 4 OCPU / 24GB | 1C / 6GB |
| (Autoscaling 최대) | 4 OCPU / 24GB | 4 OCPU / 24GB | 한도 도달 |
| Load Balancer (Flexible) | 1개, 10Mbps | 1개, 10Mbps | - |
| MySQL HeatWave | 1개, 50GB | 1개, 50GB | - |
| VCN | 1개 | 2개 | 1개 |
| Bastion | 1개 | 5개 | 4개 |

## 모듈 구조

```
.
├── main.tf                          # 모듈 호출 및 의존성 구성
├── provider.tf                      # OCI Provider 설정
├── variables.tf                     # 루트 변수
├── outputs.tf                       # 루트 출력
├── modules/
│   ├── networking/                  # VCN, Subnet, Security List, Bastion
│   ├── loadbalancer/                # Load Balancer, Backend Set, Listener
│   ├── database/                    # HeatWave MySQL
│   └── compute/                     # Master Instance, Worker Pool, Autoscaling
└── scripts/
    ├── cloud-init-master.sh         # Master 초기화 (kubeadm init, SSH join)
    ├── cloud-init-worker.sh         # Worker 초기화 (SSH 허용, kubeadm join)
    └── bastion_connect.py           # Bastion SSH 접속 헬퍼
```

## 의존성 그래프

```
networking ──┬──► loadbalancer ──┐
             │                   │
             ├──► database       │
             │                   ▼
compute ──────────────────────────┘
(depends_on: master → worker pool)
```

주요 의존성:

- Worker Instance Pool은 Master Instance에 `depends_on`으로 의존
- Master 노드가 먼저 생성되고, nmap + SSH로 worker 노드를 자동 감지 후 join

## 클러스터 부트스트랩 흐름

```
terraform apply
 │
 ├── networking (VCN, Subnet, Security List, Bastion)
 ├── loadbalancer (LB, Backend Set, Listener)
 ├── database (HeatWave MySQL)
 │
 └── compute
      │
      ├── master-01 생성 (1 OCPU / 6GB — control plane 권장 최소 2 OCPU)
      │   └── cloud-init:
      │       ├── containerd + kubeadm 설치
      │       ├── kubeadm init (CNI: Calico, --ignore-preflight-errors=NumCPU)
      │       ├── nmap 설치
      │       └── 주기적 SSH join (systemd timer: 1분 간격)
      │
      └── worker pool 생성 (master 생성 후)
          └── cloud-init:
              ├── containerd + kubeadm 설치
              └── Master SSH 키 허용, join 명령 수신 대기
                  (systemd timer: 1분 간격 폴링)

Join token은 master에서 23시간마다 자동 갱신 (systemd timer)
```

## 네트워크 정책

| Source | Destination | Protocol | Port |
|--------|-------------|----------|------|
| Internet | subnet-public | TCP | 80, 443 |
| subnet-public (LB) | subnet-workers | TCP | 30080 (NodePort) |
| subnet-masters | subnet-workers | ALL | - |
| subnet-workers | subnet-masters | ALL | - |
| subnet-workers | subnet-workers | ALL | (Pod 간 통신) |
| subnet-masters | subnet-db | TCP | 3306 |
| subnet-workers | subnet-db | TCP | 3306 |
| subnet-masters, workers | Internet (NAT) | ALL | (이미지 pull 등) |

## 자동 스케일링

Worker Instance Pool은 CPU 사용률 기반 자동 스케일링.

| Rule | Condition | Action |
|------|-----------|--------|
| Scale-out | CPU > 70% | +1 (최대 3대) |
| Scale-in | CPU < 30% | -1 (최소 2대) |

## 필수 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (Bastion 접속 시)
- OCI 유료 계정 (Pay As You Go 또는 Universal Credits)
- OCI API Key (.pem)
- SSH 키 페어

## 사용 방법

### 1. 설정 파일 작성

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

### 2. 배포

```bash
terraform init
terraform plan
terraform apply
```

### 3. Master SSH 접속

```bash
# OpenSSH
python scripts/bastion_connect.py --key ~/.ssh/id_rsa

# PuTTY (Windows)
python scripts/bastion_connect.py --putty --ppk C:\path\to\key.ppk
```

### 4. 삭제

```bash
terraform destroy
```

## 네트워크 대역폭

OCI Always Free 계정의 네트워크 대역폭은 리소스별로 다르게 적용됩니다.

| 구간 | 대역폭 | 비고 |
|------|--------|------|
| A1 인스턴스 (OCPU당) | 1 Gbps / OCPU | master 1C = 1Gbps, worker 1C = 1Gbps |
| Load Balancer | 10 Mbps | Always Free Flexible LB 고정 |
| NAT Gateway | 제한 없음 (인스턴스 대역폭 따름) | Outbound 트래픽 요금 별도 |
| Outbound 데이터 전송 | **월 10TB 무료** | 초과 시 과금, 인바운드는 무료 |

- LB가 10Mbps로 병목이므로, 외부 트래픽은 실질적으로 **최대 ~10Mbps**로 제한됩니다.
- 클러스터 내부 통신(master ↔ worker, worker ↔ DB)은 VCN 내부 트래픽으로 인스턴스 대역폭(1Gbps)까지 사용 가능합니다.
- Outbound 10TB는 일반적인 K8s 워크로드에서 초과할 가능성이 낮지만, 대용량 파일 서빙 시 모니터링이 필요합니다.

## 변수

| 변수 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `tenancy_ocid` | string | O | OCI 테넌시 OCID |
| `user_ocid` | string | O | OCI 사용자 OCID |
| `fingerprint` | string | O | API Key 지문 |
| `private_key_path` | string | O | API Key PEM 파일 경로 |
| `region` | string | O | OCI 리전 |
| `compartment_ocid` | string | O | 리소스 생성 대상 Compartment OCID |
| `ssh_authorized_keys` | string | O | 인스턴스 SSH 공개키 |
| `db_admin_password` | string | O | MySQL admin 비밀번호 (sensitive) |
| `bastion_allowed_cidrs` | list(string) | O | Bastion 접근 허용 CIDR 목록 |
| `image_id` | string | - | Compute 이미지 OCID (기본: Rocky Linux 9 aarch64) |

## 출력

| 출력 | 설명 |
|------|------|
| `lb_ip` | Load Balancer 공인 IP |
| `master_private_ip` | Master 노드 사설 IP |
| `bastion_id` | Bastion 서비스 OCID |
| `heatwave_ip` | MySQL 접속 IP |
| `heatwave_port` | MySQL 접속 포트 |
