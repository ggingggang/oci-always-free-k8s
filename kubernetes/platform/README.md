# platform

infra 부트스트랩(Gateway / TLS / DNS) 위에서 동작하는 플랫폼 계층. 현재 CI/CD(ArgoCD, Jenkins) + 시크릿(OpenBao) 도입. 관측 컴포넌트는 후속.

각 폴더는 독립 컴포넌트 단위. helm 릴리즈 단위로 의존이 닫혀있어 개별 turn으로 진행 가능.

## 1. 구성

| 폴더 | 역할 | helm 릴리즈 | NS | 외부 노출 |
|------|------|------------|-----|----------|
| `argocd/` | GitOps 컨트롤 플레인 | argo/argo-cd `~7.7.0` | `cicd` (PSA baseline) | `argocd.ggang.cloud` |
| `jenkins/` | JCasC Jenkins + Kaniko 동적 빌드 | jenkins/jenkins `~5.8.0` | `cicd` controller / `build` 빌드 Pod (PSA privileged) | admin: tailnet (parked) / webhook: `ci-hook.ggang.cloud` `/github-webhook/` |
| `openbao/` | 시크릿 저장소 (Raft 1 + OCI KMS auto-unseal) | openbao/openbao `~0.28.0` | `vault` (PSA baseline) | 없음 (port-forward) |
| `monitoring/` | 관측 (메트릭/알림/대시보드) | prometheus-community/kube-prometheus-stack `~75.0.0` | `monitoring` (PSA baseline) | `grafana.ggang.cloud` |
| `redis/` | MSA 캐시 (cache-aside, ephemeral) | — (raw manifest, `redis:*-alpine`) | `data` (PSA baseline, ambient) | 없음 (ClusterIP, in-mesh) |
| `kafka/` | MSA 이벤트 백본 (Strimzi, KRaft, ephemeral) | strimzi/strimzi-kafka-operator `1.0.1` + Kafka CR | `data` (PSA baseline, ambient) | 없음 (ClusterIP, in-mesh) |

## 2. 전제 조건 (infra 의존)

platform 컴포넌트는 모두 infra 계층(`../infra/`) 위에서 동작. 부트스트랩 미완료 상태로 설치하면 HTTPRoute가 `ResolvedRefs: False`로 멈춤.

- `cicd` + `build` 네임스페이스 + PSA 라벨 (`../infra/namespaces/`)
- Gateway API CRD + `public-gateway` (`*.ggang.cloud` listener) 동작 (`../infra/istio/`)
- wildcard TLS Secret `public-wildcard-tls` Ready=True (`../infra/cert-manager/`)
- external-dns 동작 (`../infra/external-dns/`) — HTTPRoute hostname → Cloudflare DNS 자동 sync
- Helm 3.6+

## 3. 설치 순서

infra 부트스트랩 완료 후:

```
1. argocd       helm + httproute
2. jenkins      rbac + ghcr-push Secret (build NS) + helm + httproute
3. openbao      terraform (kms + iam) 선행 → helm + operator init
```

세 컴포넌트는 상호 독립 — 순서 무관. 단 openbao 만 terraform 선행 의존 (KMS 키 + Dynamic Group/Policy). 각 단계 상세는 해당 폴더 README 참조.

## 4. 외부 노출 / TLS

둘 다 `public-gateway`의 `https-wildcard` listener에 HTTPRoute attach. `*.ggang.cloud` 와일드카드 인증서로 Gateway 단일 TLS 종료, mesh 내부 hop은 Istio Ambient(ztunnel) L4 mTLS. HTTP→HTTPS redirect는 `../infra/istio/http-redirect.yaml` catch-all 처리.

external-dns가 HTTPRoute의 `hostnames`를 source로 Cloudflare A 레코드 자동 등록.

## 5. GitOps 모델

본 레포(인프라)는 self-managed Application + 기존 helm release adopt 구조로 전환. app-of-apps(`argocd/project.yaml` + `argocd/root.yaml` + `argocd/apps/`)가 컴포넌트별 Application 으로 기존 release 를 흡수 — 부트스트랩·adopt 절차·sync-wave·제외(gateway-api CRD / openbao)는 `argocd/README.md` 6장. adopt 단계는 수동 sync + prune off(ArgoCD = 구경꾼), selfHeal/prune 활성은 하드닝 turn. 앱 sync는 별도 deploy repo 대상 — config vs source code 분리 원칙 유지.

빌드/배포 흐름의 권한 경계가 git 레벨에서 강제됨:

```
Jenkins (Kaniko) ──build──► GHCR
       │
       └──commit image tag──► 앱 레포 deploy/values.yaml
                                      │
                              ArgoCD ─sync─► app NS
```

Jenkins는 `app` NS 권한 0건 — k8s API 직접 호출 ❌, git commit만. ArgoCD가 git diff를 감지해 적용. 상세 RBAC narrative는 `jenkins/README.md` 참조.

## 6. Secret

- argo/argo-cd chart 자동 생성 `argocd-initial-admin-secret` (변경 후 삭제)
- jenkins chart 자동 생성 `jenkins` admin Secret
- `ghcr-push` — Kaniko GHCR push 자격, `build` NS (`kubernetes.io/dockerconfigjson`)

3종 모두 `kubectl create secret` 직접 생성. OpenBao 설치 완료 — Cloudflare / GHCR / DB 시크릿의 OpenBao 이관(Agent Injector / ESO 비교 포함)은 후속 turn.

placeholder · helm 버전 핀 · 5섹션 README 구조 등 공통 컨벤션은 `../infra/README.md` 참조.

## 7. 다음 후보

- monitoring 후속 — Loki / Alloy / Tempo / Kiali (kube-prometheus-stack 완료)
- 시크릿 이관 — Cloudflare / DB / GHCR Secret → OpenBao (Agent Injector / ESO 비교)
- ArgoCD SSO — `dex.enabled: true` + GitHub OAuth, `admin` 사용자 비활성
