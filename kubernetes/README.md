# kubernetes

OKE 클러스터 위에서 동작하는 Kubernetes 매니페스트.

각 컴포넌트 폴더에 매니페스트(`.yaml`) + helm values + README. 모든 README는 5섹션 표준 (전제 조건 / 설치 / 검증 / 결정 / 주의 사항).

## 디렉토리

```
kubernetes/
├── infra/                # 클러스터 부트스트랩 인프라
│   ├── namespaces/       # 네임스페이스 + PSA 라벨
│   ├── gateway-api/      # Gateway API CRD
│   ├── istio/            # Ambient mesh + Gateway/HTTPRoute
│   ├── external-dns/     # HTTPRoute hostnames → Cloudflare DNS
│   ├── cert-manager/     # LE DNS-01 + 와일드카드 Certificate
│   └── README.md         # 전체 그림 + 설치 순서
└── test/                 # 일회성 검증 자산
    ├── networking/       # NLB smoke test
    └── storage/          # Block Volume CSI smoke test
```

상세 설치 순서 + 컴포넌트 의존 관계: [`infra/README.md`](./infra/README.md).

## 적용 모델

현재는 helm install + `sed | kubectl apply -f -` 수동 (멱등). ArgoCD 도입 시점에 helm 릴리즈 adopt + Application 매니페스트로 전환. 그 시점에 RBAC 컨벤션 + ApplicationSet도 함께.

수동 적용 흐름은 cold-start / DR 복구 자산으로 유지.

## 앱 매니페스트 위치

앱 매니페스트는 본 레포에 두지 않음. 서비스별 별도 레포(코드 + `deploy/` 매니페스트 동거).

사유: ArgoCD 공식 권장 *config vs source code 분리* + 인프라/앱 권한 경계 + commit log 오염 방지.

## 예정 추가

- `platform/` — argocd, jenkins, monitoring (kube-prometheus / Loki / Tempo / Grafana), openbao
- `apps/` 또는 별도 레포 — 실제 워크로드
