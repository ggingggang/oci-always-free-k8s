# OCI Kubernetes 클러스터 (Always Free)

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
            │  │  OCI LB        │  │  ← OKE가 자동 프로비저닝 (Service type: LoadBalancer)
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
  │  │ Plane API │  │    │  │    .A1.Flex         │  │
  │  │ (managed) │  │    │  │  2 OCPU / 12GB each │  │
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

## Always Free 리소스 사용량

| 리소스 | 사용량 | Always Free 한도 | 여유 |
|--------|--------|-------------------|------|
| VM.Standard.A1.Flex | 4 OCPU / 24GB (노드 2개 × 2C/12GB) | 4 OCPU / 24GB | 한도 도달 |
| OKE Basic Cluster | 1개 (컨트롤 플레인 무료) | — | — |
| MySQL HeatWave | 1개, 50GB | 1개, 50GB | — |
| Load Balancer | 1개, 10Mbps (OKE Service 경유) | 1개, 10Mbps | — |
| VCN | 1개 | 2개 | 1개 |

> OKE Basic Cluster의 컨트롤 플레인은 무료입니다. 워커 노드는 Always Free A1.Flex 쿼터를 사용합니다.
> OKE는 Free Tier 계정에서 사용할 수 없으므로 PAYG(종량제) 계정이 필요합니다.

## 디렉토리 구조

```
.
├── README.md
├── docs/
│   ├── README-KR.md          # 한국어 문서
│   ├── architecture.html     # 인프라 아키텍처 다이어그램
│   └── summary.md            # Always Free 리소스 요약
└── terraform/
    ├── main.tf                   # 모듈 호출 및 의존성 구성
    ├── provider.tf               # OCI Provider 설정
    ├── variables.tf              # 루트 변수
    ├── outputs.tf                # 루트 출력
    ├── terraform.tfvars.example  # 설정 파일 예시
    ├── modules/
    │   ├── networking/           # VCN, 서브넷, 라우트 테이블, 보안 리스트, Bastion
    │   ├── oke/                  # OKE Basic Cluster + ARM Node Pool + 이미지 동적 조회
    │   │   └── scripts/
    │   │       └── node_pool_init.sh  # Cloud-init 부트스트랩 스크립트
    │   ├── database/             # HeatWave MySQL Free
    │   └── iam/                  # (예약) Dynamic Group, Policy
```

## 의존성 그래프

```
networking ──┬──► oke
             │
             └──► database
```

## 서브넷 구성

| 서브넷 | CIDR | 유형 | 용도 |
|--------|------|------|------|
| subnet-oke-api | 10.0.0.0/28 | Public | OKE API 엔드포인트 |
| subnet-public | 10.0.1.0/28 | Public | OCI Load Balancer (Service LB) |
| subnet-workers | 10.0.102.0/24 | Private | OKE 워커 노드 |
| subnet-db | 10.0.201.0/28 | Private | HeatWave MySQL |

## 네트워크 정책

| Source | Destination | Protocol | Port |
|--------|-------------|----------|------|
| Internet | subnet-oke-api | TCP | 6443 (kubectl) |
| Internet | subnet-public | TCP | 80, 443 |
| subnet-oke-api | subnet-workers | ALL | 컨트롤 플레인 → 워커 |
| subnet-oke-api | OCI Services (SGW) | TCP | 443 |
| subnet-public (LB) | subnet-workers | TCP | 30000–32767 (NodePort) |
| subnet-public (LB) | subnet-workers | TCP | 10256 (헬스체크) |
| subnet-workers | subnet-oke-api | TCP | 6443, 12250 |
| subnet-workers ↔ subnet-workers | — | ALL | Pod 간 통신 (Flannel VXLAN) |
| subnet-workers | subnet-db | TCP | 3306 (MySQL) |
| subnet-workers | Internet (NAT) | ALL | 이미지 pull, 업데이트 |
| subnet-workers | OCI Services (SGW) | ALL | OCI 내부 서비스 |

## 필수 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.3
- [OCI CLI](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) (kubeconfig 설정 시)
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
private_key_path      = "./secrets/oci-api-key.pem"
region                = "ap-tokyo-1"
compartment_ocid      = "ocid1.compartment.oc1..aaaa..."
ssh_authorized_keys   = "ssh-rsa AAAA... user@host"
db_admin_password     = "MyStr0ng#Pass!"
kubernetes_version    = "v1.34.2"
```

> Oracle Linux ARM 노드 이미지는 리전에 맞게 자동 조회됩니다.
> 기본 `kubernetes_version`이 리전에서 지원되지 않는 경우 값을 변경하세요.

### 2. 배포

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 3. 클러스터 접속 (kubectl 설정)

```bash
# apply 완료 후 실행
oci ce cluster create-kubeconfig \
  --cluster-id <oke_cluster_id> \
  --file ~/.kube/config \
  --region ap-tokyo-1 \
  --token-version 2.0.0

kubectl get nodes
```

### 4. 삭제

```bash
cd terraform
terraform destroy
```

## 변수

| 변수 | 타입 | 필수 | 기본값 | 설명 |
|------|------|------|--------|------|
| `tenancy_ocid` | string | O | — | OCI 테넌시 OCID |
| `user_ocid` | string | O | — | OCI 사용자 OCID |
| `fingerprint` | string | O | — | API Key 지문 |
| `private_key_path` | string | O | — | API Key PEM 파일 경로 |
| `region` | string | O | — | OCI 리전 |
| `compartment_ocid` | string | O | — | 리소스 생성 대상 Compartment OCID |
| `ssh_authorized_keys` | string | O | — | 워커 노드 SSH 공개키 |
| `db_admin_password` | string | O | — | MySQL admin 비밀번호 (sensitive) |
| `kubernetes_version` | string | — | `"v1.34.2"` | Kubernetes 버전 |

## 출력

| 출력 | 설명 |
|------|------|
| `vcn_id` | VCN OCID |
| `subnet_oke_api_id` | OKE API 서브넷 OCID |
| `subnet_pub_id` | Public (LB) 서브넷 OCID |
| `subnet_workers_id` | Worker 서브넷 OCID |
| `subnet_db_id` | DB 서브넷 OCID |
| `oke_cluster_id` | OKE 클러스터 OCID |
| `oke_cluster_endpoint` | OKE API 공인 엔드포인트 |
| `oke_node_pool_id` | 노드 풀 OCID |
| `heatwave_ip` | MySQL 접속 IP |
| `heatwave_port` | MySQL 접속 포트 |

## 네트워크 대역폭

| 구간 | 대역폭 | 비고 |
|------|--------|------|
| A1 인스턴스 (OCPU당) | 1 Gbps / OCPU | 2 OCPU 노드 = 2 Gbps |
| Load Balancer | 10 Mbps | Always Free Flexible LB 고정 |
| Outbound 데이터 전송 | 월 10TB 무료 | 초과 시 과금, 인바운드는 무료 |

- LB가 10Mbps로 병목이 되어 외부 트래픽은 실질적으로 **최대 ~10Mbps**로 제한됩니다.
- 클러스터 내부 통신(워커 ↔ 워커, 워커 ↔ DB)은 VCN 내부 트래픽으로 인스턴스 전체 대역폭(2Gbps)까지 사용 가능합니다.

## OKE Basic Cluster 제한사항

| 기능 | Basic Cluster | Enhanced Cluster |
|------|--------------|-----------------|
| 요금 | **무료** | $0.10/시간 |
| Virtual Node | ✗ | ✓ |
| OKE Add-on | ✗ | ✓ |
| 컨트롤 플레인 SLA | ✗ | ✓ |
| CNI | Flannel Overlay | Flannel / OCI VCN-Native |

> 개인 프로젝트 및 비프로덕션 워크로드에는 Basic Cluster로 충분합니다.
