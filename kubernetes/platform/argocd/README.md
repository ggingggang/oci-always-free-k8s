# ArgoCD

GitOps 컨트롤 플레인. helm install + HTTPRoute 외부 노출까지. SSO / 앱 sync 는 별도 turn.

참조:
- https://github.com/argoproj/argo-helm (chart `argo/argo-cd`)
- https://argo-cd.readthedocs.io/en/stable/

## 1. 전제 조건

- `cicd` 네임스페이스 존재 (`../../infra/namespaces/namespaces.yaml`)
- `public-gateway` (istio-system, `*.ggang.cloud` listener) 준비 (`../../infra/istio/gateway.yaml`)
- wildcard TLS Secret `public-wildcard-tls` Ready (`../../infra/cert-manager/`)
- external-dns 동작 (`../../infra/external-dns/`) — HTTPRoute hostname → Cloudflare DNS 자동 sync
- Helm 3.6+
- 권장 버전: argo/argo-cd chart `~7.x` (작성 시점 추론, 설치 전 `helm search repo argo/argo-cd --versions` 로 stable 확인 — 2년 안쪽 변동 가능)

## 2. 설치

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd -n cicd --version "~7.7.0" -f values.yaml --wait

kubectl apply -f httproute.yaml
```

초기 admin 비밀번호 (chart가 자동 생성한 `argocd-initial-admin-secret` 사용 → 변경 후 삭제):

```bash
kubectl -n cicd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo

# https://argocd.ggang.cloud 접속 후
# admin / <위 출력> 로 로그인 → Settings에서 비밀번호 변경

kubectl -n cicd delete secret argocd-initial-admin-secret
```

## 3. 검증

```bash
kubectl get pods -n cicd -l app.kubernetes.io/part-of=argocd

kubectl -n cicd get httproute argocd \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' ; echo
# 기대: True
```

DNS sync 확인 (external-dns가 ~1-5분 내 Cloudflare에 A record 생성):

```bash
dig +short argocd.ggang.cloud
```

UI 접근: 브라우저에서 `https://argocd.ggang.cloud` → admin login.

## 4. 결정

### self-managed Application + helm release adopt — 채택 (도입 대기)

본 레포(인프라)의 `kubernetes/` 매니페스트를 ArgoCD 가 sync 하는 모델 채택. 초기엔 "helm release 만으로 충분" 으로 미채택했으나 결정 뒤집음. 사유:

- git 이 진실 = `selfHeal` 정합 — 수동 `kubectl apply`/helm 운영에서 발생하는 드리프트를 감지·자동 복구
- 기존 helm release (cert-manager / external-dns / istio / jenkins / argocd 자신) 는 컴포넌트별 Application 으로 adopt
- 앱 sync 는 별도 deploy repo 책임 — config vs source code 분리 + 인프라/앱 권한 경계는 git 레벨에서 유지

현재는 helm release 로 운영 중. `application.yaml`(self-managed) + adopt Application + AppProject 는 도입 시점에 추가. 그 전까지 업그레이드/롤백은 `helm upgrade` / `helm rollback`.

### 외부 노출 — Gateway TLS 단일 종료

`public-gateway` 의 `https-wildcard` listener 가 `*.ggang.cloud` 와일드카드 인증서로 TLS 종료. ArgoCD `argocd-server` 는 `--insecure` 유지하고 cluster 내부에서는 HTTP(:80) 로 listen. mesh 내부 트래픽은 Istio Ambient(ztunnel) 가 L4 mTLS 로 보호.

이중 TLS 종료(Gateway + ArgoCD self-TLS) 미채택 사유:
- ArgoCD gRPC + gRPC-Web 이 single port 에서 동작 — 중간단 재암호화 시 ALPN/HTTP2 협상 골치
- ambient mesh 가 이미 L4 mTLS 보장 → 평문 hop 없음
- argoproj 공식 ingress 가이드도 *TLS termination at ingress* 패턴이 default

SSO 도입 turn 에서 `dex.enabled: true` + GitHub OAuth 활성, `admin` user 비활성.

### dex / notifications / redis-ha 비활성

- `dex.enabled: false` — SSO turn 전까지 불필요
- `notifications.enabled: false` — Slack/email 연동 turn 에 활성
- `redis-ha.enabled: false` — single Redis. controller HA 불필요 (Always Free 24GB RAM 우선)

### 리소스 핀

총 ~544Mi (controller 256 + repo 128 + server 64 + appset 64 + redis 32). Always Free 분배 (Vault + Prometheus 우선) 에 맞춰 tight 설정.

## 5. 주의 사항

### chart 버전 확인

`~7.7.0` 은 작성 시점 추론. 설치 전:

```bash
helm search repo argo/argo-cd --versions | head -5
```

CHANGELOG 에서 breaking change 확인 (특히 6.x → 7.x, 7.x → 8.x).

### admin Secret 회전

`argocd-initial-admin-secret` 은 plain text. 변경 → 삭제까지 1회 절차. SSO 도입 turn 에 `admin` 사용자 비활성화 + role 기반 접근으로 전환.

### reconciliation 주기

`timeout.reconciliation: 180s` — 기본 180s 명시. webhook 적용 시 즉시 반영 — webhook 은 SSO turn 이후.

### gRPC CLI 접근

`argocd` CLI 는 gRPC. Gateway TLS 종료 + HTTPRoute 환경에선:

```bash
argocd login argocd.ggang.cloud --grpc-web
```

`--grpc-web` 없이 호출하면 HTTP/2 protocol error. UI 는 자동 처리되어 무관.
