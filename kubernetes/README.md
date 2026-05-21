# kubernetes/

OKE 클러스터 위에서 동작하는 Kubernetes 매니페스트.

각 컴포넌트 폴더에 매니페스트(`.yaml`) + 설명(`README`) + 필요 시 부트스트랩 스크립트(`bootstrap.sh` 또는 `verify.sh`)가 함께 위치한다.

## 디렉토리 구조

- `infra/` — 클러스터 부트스트랩에 필요한 인프라
  - `namespaces/` — 네임스페이스 + PSA 라벨
  - `gateway-api/` — Gateway API CRD
  - `external-dns/` — Cloudflare DNS 자동화
  - `cert-manager/` — Let's Encrypt
  - `istio/` — Ambient 서비스 메시
  - `rbac/` — RBAC 설계 문서
- `platform/` — 플랫폼 서비스
  - `argocd/`, `jenkins/`, `monitoring/`
- `test/` — 일회성 검증 자산 (적용 후 삭제)
  - `storage/` — Block Volume CSI / oci-bv 스모크 테스트

## 적용 모델

ArgoCD 미설치 시 폴더별 `bootstrap.sh` / `verify.sh`를 수동 실행 (helm + kubectl 멱등).
ArgoCD 설치 후에는 폴더의 `application.yaml`을 ArgoCD가 자동 sync. 쉘 스크립트는 cold-start 진단 자산으로 유지.

## 앱 매니페스트 위치

앱 매니페스트는 본 레포에 두지 않는다. 서비스별 별도 레포(코드 + `deploy/` 매니페스트 동거).
사유: ArgoCD 공식 권장 *config vs source code 분리* + 인프라/앱 권한 경계 + commit log 오염 방지.
