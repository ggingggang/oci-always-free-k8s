# Namespaces

클러스터 전체 Namespace 구조 + PSA(Pod Security Admission) 라벨.

## 1. 전제 조건

- OKE 클러스터에 kubectl 접근 가능

## 2. 설치

```bash
kubectl apply -f namespaces.yaml
```

생성되는 네임스페이스:

| Namespace | 용도 |
|-----------|------|
| `istio-system` | Istio 컨트롤 플레인 (istiod, ztunnel, istio-cni, Gateway) |
| `cert-manager` | cert-manager 전용 |
| `external-dns` | external-dns 전용 |
| `cicd` | ArgoCD, Jenkins |
| `monitoring` | kube-prometheus-stack, Thanos, Loki, Grafana, Tempo, Kiali |
| `vault` | OpenBao |
| `app` | 워크로드 (PSA `enforce=restricted`) |

## 3. 검증

```bash
kubectl get ns
kubectl get ns app -o jsonpath='{.metadata.labels}' | jq .
kubectl get ns -L pod-security.kubernetes.io/enforce
```

`app` 네임스페이스에만 `pod-security.kubernetes.io/enforce=restricted` 라벨이 박혀 있어야 정상.

## 4. 결정

### app 단일 환경

dev/staging/prod 멀티 네임스페이스 분리는 OCI Always Free 24GB RAM 제약에서 비현실적 (각 환경 stack을 N배). 단일 `app` 네임스페이스 + LE staging/prod ClusterIssuer로 환경 분리 역할 흡수.

### PSA enforce는 app에만 적용

`istio-system`, `vault`, `cert-manager`, `external-dns` 등 인프라 네임스페이스는 host network / privileged container / hostPath 등 권한 요구 컴포넌트가 들어옴. enforce 라벨 박으면 ambient ztunnel + istio-cni가 거부됨.

워크로드는 `app` 한정 → 거기에만 enforce 부여. 인프라 네임스페이스는 명시적으로 enforce 미적용.

### 명시적 네임스페이스 선언

helm chart의 `--create-namespace` 옵션 비채택. 네임스페이스 라이프사이클 + 라벨/annotation을 단일 매니페스트로 통제. helm uninstall 시 네임스페이스가 사라지지 않음 (의도된 격리).

## 5. 주의 사항

### PSA 위반 시 동작

`pod-security.kubernetes.io/enforce` 위반 시 Pod 생성이 거부됨 (admission level). Deployment는 만들어지지만 ReplicaSet 단계에서 실패. 디버깅 시 `kubectl get events -n app | grep -i security` 또는 Deployment status의 `FailedCreate` 확인.

### warn / audit 라벨 추가 가능

워크로드 마이그레이션 단계에서 `enforce` 대신 `warn` / `audit`만 부여하면 위반 시 거부 없이 경고/감사 로그만 남김:

```yaml
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/audit: restricted
```

현재 매니페스트는 `enforce` + `warn` 모두 박힘.

### 신규 네임스페이스 추가

워크로드를 `app` 외부로 확장할 때 (예: dedicated namespace per tenant) 매니페스트에 추가하고 동일 PSA 라벨 부여. 인프라 네임스페이스는 PSA 미적용 원칙 유지.
