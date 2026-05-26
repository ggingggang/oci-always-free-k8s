# infra

OKE 클러스터의 기반 인프라 계층. 네임스페이스/PSA, Gateway API, Ambient mesh, DNS 자동화, 인증서.

각 폴더는 독립 컴포넌트 단위. helm 릴리즈/CR 단위로 의존이 닫혀있어 개별 turn으로 진행 가능.

## 1. 구성

| 폴더 | 역할 | helm 릴리즈 | 외부 의존 |
|------|------|------------|----------|
| `namespaces/` | 네임스페이스 + PSA(`app`에 enforce=restricted) | — | — |
| `gateway-api/` | Gateway API v1.5.0 standard CRD | — | — |
| `istio/` | Ambient mesh(`base`/`istiod`/`cni`/`ztunnel`) + Gateway/HTTPRoute | 4 | — |
| `external-dns/` | HTTPRoute hostnames → Cloudflare DNS sync | 1 | Cloudflare zone + API token |
| `cert-manager/` | LE DNS-01 + 와일드카드 Certificate | 1 | Cloudflare zone + API token |
| `rbac/` | RBAC 설계 문서 (권한 매트릭스 + 컨벤션). 실 YAML은 각 컴포넌트 폴더 동거 | — | — |

## 2. 설치 순서

의존 그래프 기준. 각 단계의 상세는 해당 폴더 README 참조.

```
1. namespaces            네임스페이스 + PSA
2. gateway-api           Gateway/HTTPRoute/GRPCRoute CRD
3. istio (코어)          base → istiod → istio-cni → ztunnel
4. external-dns          Cloudflare Secret + helm
5. cert-manager          helm + ClusterIssuer + Certificate (Ready=True 대기)
6. istio (Gateway)       gateway.yaml + http-redirect.yaml — Certificate Secret 의존
```

3번 helm 4개는 명시한 순서로. `base`가 GatewayClass CRD 등록, `istiod`가 컨트롤 플레인, `istio-cni`가 노드 데이터 플레인 redirect, `ztunnel`이 ambient L4 mTLS.

5번과 6번 사이에 Certificate `Ready=True` 검증 필요. Secret 미존재 상태로 Gateway HTTPS listener를 apply하면 `ResolvedRefs: False` — Certificate 발급되면 자동 회복되지만 status 노이즈 발생.

## 3. 외부 의존

- **OCI** — OKE 클러스터, Network Load Balancer (Gateway API → istio가 자동 프로비전)
- **Cloudflare** — 도메인 zone (DNS 관리 + ACME DNS-01 challenge)
- **helm registries** — `jetstack`, `kubernetes-sigs/external-dns`, `istio-release`

Cloudflare API Token은 컴포넌트별 분리 발급 권장 (cert-manager/external-dns 각각). 사고 시 폭발 반경 최소화.

## 4. 컨벤션

### Placeholder + sed 패턴

매니페스트의 사적 값은 `<your-*>` placeholder로 박고 apply 시 sed로 치환.

```bash
export DOMAIN=<your-domain>
sed -e "s|<your-domain>|${DOMAIN}|g" some.yaml | kubectl apply -f -
```

사용하는 placeholder:

| 토큰 | 의미 |
|------|------|
| `<your-domain>` | apex 도메인 (예: `example.com`) |
| `<your-email>` | ACME 등록 이메일 |
| `<your-cf-token>` | Cloudflare API Token (Secret 생성 시) |
| `<your-zone>` | Cloudflare zone (대부분 apex 도메인과 동일) |

### 비밀값

`*.env`, `*.local.*` 는 `.gitignore`로 git 추적 제외. 본인 값은 각 컴포넌트 폴더의 `.env` 또는 루트 `values.local.env`(예정)에 보관.

### README 구조 (5섹션 표준)

각 폴더 README는 동일 구조:

1. 전제 조건
2. 설치
3. 검증
4. 결정 — 채택 사유 / 비채택 대안
5. 주의 사항 — 운영 시 함정, 회전·갱신·업그레이드 가이드

### helm 버전 핀

`--version "~X.Y.0"` SemVer tilde 범위. patch만 자동 따라가고 minor 변경은 명시적 갱신.

## 5. 다음 후보

- echo/whoami HTTPRoute — external-dns sync + end-to-end TLS 검증
- observability (kube-prometheus-stack, Loki, Grafana, Tempo) — 메트릭/로그/트레이스
- ArgoCD — 기존 helm 릴리즈 adopt + Application 매니페스트화. RBAC 컨벤션 함께
- OpenBao (Vault) — Cloudflare/DB 시크릿 Vault 이관 + ESO 도입
