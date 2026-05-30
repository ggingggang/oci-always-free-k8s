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
| Outbound Data Transfer | Egress traffic to the internet via Internet Gateway, NAT Gateway, and Load Balancer responses. Excludes intra-VCN traffic and OCI-internal traffic routed through Service Gateway | Up to 10 TB per month |
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
| Bastions | Restricted SSH access to private targets | Up to 20 OCI Bastions |
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

## Effectively Free — Not in the Official Always Free List

Resources not listed in the official Always Free catalog, but usable at no cost by leveraging existing Always Free resources or because the service itself carries no charge.

| Resource | Description | Why It's Free | Notes |
| :--- | :--- | :--- | :--- |
| OKE Basic Cluster (Container Engine for Kubernetes) | Oracle-managed Kubernetes control plane | Control plane itself is free. Running worker nodes on Always Free A1 instances makes the entire cluster free to operate | Requires a PAYG account. Virtual Nodes, OKE Add-ons, and control plane SLA are not supported |
| Container Instances (CI.Standard.A1.Flex) | Serverless containers — run containers directly without managing VMs | Uses the shared A1 Flex Always Free quota (3,000 OCPU-hours / 18,000 GB-hours per month). No additional service charge | A1 quota is shared across VMs, Container Instances, and Bare Metal |
| Internet Gateway | Direct connectivity between a VCN and the internet | Gateway itself is free. Outbound traffic is free up to 10 TB/month | Data transfer charges apply beyond the 10 TB threshold |
| NAT Gateway | Outbound internet access for resources without a public IP | Gateway itself is free. Outbound traffic is free up to 10 TB/month | Data transfer charges apply beyond the 10 TB threshold |
| Service Gateway | Private access to OCI services (e.g. Object Storage) from within a VCN | **No additional cost** (explicitly stated on Oracle's product page). Enables secure access to OCI-internal services without traversing the internet | Not listed in the official Always Free catalog, but Oracle explicitly states "no additional cost" |

> **Note**: When combining OKE and Container Instances, ensure total A1 quota usage does not exceed the Always Free limit.

