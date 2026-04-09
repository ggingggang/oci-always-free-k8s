# Oracle Cloud Infrastructure Always Free Resources Summary

## Compute
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| AMD Compute Instance | AMD based Compute VMs (1/8 OCPU, 1 GB RAM) | 2 VMs |
| ARM Compute Instance | Arm-based Ampere A1 cores and 24 GB RAM | 3,000 OCPU hours & 18,000 GB hours/month (up to 4 VMs) |

## Developer Services
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| APEX | Low-code application development platform | Up to 744 hours per instance |
| Oracle Functions | Serverless function execution (FaaS) | 2,000,000 invocations & 400,000 GB-seconds per month |

## Networking
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| Flexible Network Load Balancer | Layer 3/Layer 4 traffic distribution | 1 instance |
| Load Balancer | Highly available load balancers with provisioned bandwidth | 1 instance, 10 Mbps |
| Outbound Data Transfer | Data transfer out of OCI | Up to 10 TB per month |
| Service Connector Hub | Message bus for data movement between OCI services | 2 service connectors |
| Site-to-Site VPN | IPSec connection between on-premises and VCN | 50 IPSec connections |
| VCN Flow Logs | Traffic details for auditing and troubleshooting | Up to 10 GB per month (shared) |
| Virtual Cloud Networks (VCN) | Software-defined network with IPv4/IPv6 support | 2 VCNs (includes subnets) |

## Observability and Management
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| Application Performance Monitoring | Application monitoring and diagnostics | 1,000 tracing events & 10 Synthetic runs/hour |
| Email Delivery | Managed solution for high-volume emails | Up to 100 emails sent per day |
| Logging | Scalable single pane of glass for all logs | Up to 10 GB per month |
| Monitoring | Query metrics and manage alarms | 500M ingestion & 1B retrieval datapoints |
| Notification | Alerting via email, text (SMS), and HTTPS | 1M HTTPS & 1,000 email messages/month |

## Oracle Databases
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| Autonomous Database | ATP, ADW, AJD, or APEX Development | 2 databases total |
| HeatWave | Integrated AI/ML for transactions and analytics | 1 standalone instance (50GB storage/backup) |
| NoSQL Database | Fully managed NoSQL database service | 133M reads/writes per month, 25GB/table (up to 3 tables) |

## Security
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| Bastions | Restricted SSH access to private targets | Up to 5 OCI Bastions |
| Certificates | Certificate issuance and management | 5 Private CA & 150 private TLS certificates |
| Vault | Master encryption keys and secrets management | 20 key versions (HSM) & 150 Vault secrets |

## Storage
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| Archive Storage | Unstructured archive storage | 20GB total (shared with Standard/Infrequent) |
| Block Volume Storage | Boot and block volume storage | 2 volumes, 200 GB total; 5 volume backups |
| Object Storage | API requests for object storage | Up to 50,000 API requests per month |
| Object Storage - Infrequent Access | Unstructured infrequent access storage | 20GB total (shared with Standard/Archive) |
| Object Storage - Standard | Unstructured standard storage | 20GB total (shared with Archive/Infrequent) |

## Others
| Resource | Description | Always Free Limit |
| :--- | :--- | :--- |
| Console Dashboards | Custom dashboards for monitoring OCI resources | Up to 100 dashboards |

---

## 공식 무료 리소스 (Effectively Free — 공식 Always Free 목록 외)

공식 Always Free 목록에는 없지만, 기존 Always Free 리소스를 활용하거나 서비스 자체가 무료라서 **실질적으로 무료로 사용 가능한** 리소스입니다.

| Resource | Description | 무료 조건 | 주의사항 |
| :--- | :--- | :--- | :--- |
| OKE Basic Cluster (Container Engine for Kubernetes) | Oracle 관리형 Kubernetes 컨트롤 플레인 | 컨트롤 플레인 자체는 무료. 워커 노드에 Always Free A1 인스턴스 사용 시 전체 무료 운영 가능 | PAYG 계정 필요. Virtual Node, Add-on, 컨트롤 플레인 SLA 미지원 |
| Container Instances (CI.Standard.A1.Flex) | VM 없이 컨테이너를 직접 실행하는 서버리스 컨테이너 | A1 Flex Always Free 쿼터(월 3,000 OCPU시간 / 18,000 GB시간)를 VM·베어메탈과 공유하여 무료 사용 가능. 서비스 자체 추가 요금 없음 | A1 쿼터는 VM·Container Instances·Bare Metal 합산 적용 |

> **참고**: OKE + Container Instances 조합 시 A1 쿼터를 초과하지 않도록 주의가 필요합니다.

