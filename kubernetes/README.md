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
│   ├── metrics-server/   # metrics.k8s.io (kubectl top / HPA)
│   └── README.md         # 전체 그림 + 설치 순서
├── platform/             # CI/CD · 관측 · 보안 등 플랫폼 컴포넌트
│   ├── argocd/           # GitOps 컨트롤 플레인 (helm + HTTPRoute)
│   ├── jenkins/          # JCasC + emptyDir, 동적 agent (+ Kaniko podTemplate in build NS)
│   ├── openbao/          # 시크릿 저장소 (Raft 1 + OCI KMS auto-unseal + Injector)
│   ├── monitoring/       # kube-prometheus-stack (Prometheus/Alertmanager/Grafana)
│   ├── redis/            # MSA 캐시 (ephemeral, cache-aside, data NS)
│   └── kafka/            # MSA 이벤트 백본 (Strimzi, KRaft, ephemeral, data NS)
└── test/                 # 일회성 검증 자산
    ├── networking/       # NLB smoke test
    ├── storage/          # Block Volume CSI smoke test
    └── database/         # HeatWave MySQL 연결 smoke test
```

상세 설치 순서 + 컴포넌트 의존 관계: [`infra/README.md`](./infra/README.md) (부트스트랩), [`platform/README.md`](./platform/README.md) (CI/CD).

## 적용 모델

helm install + `kubectl apply` 수동 (멱등). 도메인은 git 박힘, secret 성격 값만 sed/Vault 경유. ArgoCD 는 현재 helm release 로 유지하되, 본 레포(인프라)는 self-managed Application + 기존 helm release adopt 로 ArgoCD sync 전환 예정. 앱 sync 는 별도 deploy repo 대상 — config vs source code 분리 원칙 유지.

수동 적용 흐름은 cold-start / DR 복구 자산으로 유지.

## 앱 매니페스트 위치

앱 매니페스트는 본 레포에 두지 않음. 서비스별 별도 레포(코드 + `deploy/` 매니페스트 동거).

사유: ArgoCD 공식 권장 *config vs source code 분리* + 인프라/앱 권한 경계 + commit log 오염 방지.

## 예정 추가

- `platform/` — argocd, jenkins, openbao, monitoring, 데이터 계층(redis/kafka, `data` NS) 도입 완료. 관측 후속(Loki / Alloy / Tempo / Kiali) 예정
- `apps/` 또는 별도 레포 — 실제 워크로드 (redis/kafka 소비하는 producer/consumer)
