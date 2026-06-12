# platform

infra 부트스트랩(Gateway / TLS / DNS) 위에서 동작하는 플랫폼 계층. 현재 CI/CD(ArgoCD, Jenkins) 도입. 관측·보안 컴포넌트는 후속.

각 폴더는 독립 컴포넌트 단위. helm 릴리즈 단위로 의존이 닫혀있어 개별 turn으로 진행 가능.

## 1. 구성

| 폴더 | 역할 | helm 릴리즈 | NS | 외부 노출 |
|------|------|------------|-----|----------|
| `argocd/` | GitOps 컨트롤 플레인 | argo/argo-cd `~7.7.0` | `cicd` (PSA baseline) | `argocd.ggang.cloud` |
| `jenkins/` | JCasC Jenkins + Kaniko 동적 빌드 | jenkins/jenkins `~5.8.0` | `cicd` controller / `build` 빌드 Pod (PSA privileged) | `jenkins.ggang.cloud` |

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
```

두 컴포넌트는 상호 독립 — 순서 무관, 병렬 가능. 각 단계 상세는 해당 폴더 README 참조.

## 4. 외부 노출 / TLS

둘 다 `public-gateway`의 `https-wildcard` listener에 HTTPRoute attach. `*.ggang.cloud` 와일드카드 인증서로 Gateway 단일 TLS 종료, mesh 내부 hop은 Istio Ambient(ztunnel) L4 mTLS. HTTP→HTTPS redirect는 `../infra/istio/http-redirect.yaml` catch-all 처리.

external-dns가 HTTPRoute의 `hostnames`를 source로 Cloudflare A 레코드 자동 등록.

## 5. GitOps 모델

ArgoCD는 현재 helm release로 유지. 본 레포(인프라)는 self-managed Application + 기존 helm release adopt로 ArgoCD sync 전환 예정 (Application 매니페스트 도입 시점에). 앱 sync는 별도 deploy repo 대상 — config vs source code 분리 원칙 유지.

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

3종 모두 `kubectl create secret` 직접 생성. 향후 OpenBao(Vault) Agent Injector + ESO 이관 예정.

placeholder · helm 버전 핀 · 5섹션 README 구조 등 공통 컨벤션은 `../infra/README.md` 참조.

## 7. 다음 후보

- monitoring — kube-prometheus-stack / Loki / Alloy / Tempo / Grafana / Kiali (`monitoring` NS)
- openbao — Cloudflare / DB / GHCR Secret Vault 이관 + ESO (`vault` NS)
- ArgoCD SSO — `dex.enabled: true` + GitHub OAuth, `admin` 사용자 비활성
