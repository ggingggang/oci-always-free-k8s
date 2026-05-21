# Namespaces

클러스터 전체 Namespace 구조 및 PSA(Pod Security Admission) 라벨 설정.

## 1. 전제 조건

- OKE 클러스터에 kubectl 접근 가능 상태

## 2. 매니페스트 (`namespaces.yaml`)

| Namespace | 용도 |
|-----------|------|
| `istio-system` | Istio 컨트롤 플레인 (istiod, ztunnel, gateway) |
| `cert-manager` | cert-manager 전용 |
| `external-dns` | external-dns 전용 |
| `cicd` | ArgoCD, Jenkins |
| `monitoring` | Prometheus, Grafana, Loki, Thanos, Tempo, Kiali |
| `vault` | OpenBao (Vault) |
| `app` | 앱 단일 환경 (PSA enforce=restricted 선반영) |

`app` namespace는 Always Free 24GB RAM 제약상 dev/staging/prod 멀티환경 분리가 비현실적이므로 단일 환경으로 운영한다.

## 3. 적용

`$ kubectl apply -f .\namespaces.yaml`

```bash
namespace/istio-system created
namespace/cert-manager created
namespace/external-dns created
namespace/cicd created
namespace/monitoring created
namespace/vault created
namespace/app created
```

## 4. 검증

`$ kubectl get ns`

```bash
NAME              STATUS   AGE
app               Active   16s
cert-manager      Active   16s
cicd              Active   16s
default           Active   25h  # 기본
external-dns      Active   16s
istio-system      Active   17s
kube-node-lease   Active   25h  # 기본
kube-public       Active   25h  # 기본 
kube-system       Active   25h  # 기본
monitoring        Active   16s
vault             Active   16s
```

`$ kubectl get ns app -o jsonpath='{.metadata.labels}'`

```bash
{"app.kubernetes.io/managed-by":"kubectl","kubernetes.io/metadata.name":"app","pod-security.kubernetes.io/enforce":"restricted","pod-security.kubernetes.io/enforce-version":"latest","pod-security.kubernetes.io/warn":"restricted","pod-security.kubernetes.io/warn-version":"latest"}
```
