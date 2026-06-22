# Kafka (Strimzi, KRaft + ephemeral)

MSA 이벤트 백본. Strimzi operator 가 Kafka CR 을 reconcile. KRaft(Zookeeper 제거) + ephemeral(PV 0) + single broker — Always Free 최소 풋프린트.

참조:
- https://strimzi.io/docs/operators/latest/deploying (2026-06 확인)
- https://strimzi.io/docs/operators/latest/configuring (KRaft / node pools)

## 1. 전제 조건

- `data` 네임스페이스 + PSA `enforce=baseline` + Istio ambient (`../../infra/namespaces/`)
- ArgoCD `platform` AppProject `sourceRepos` 에 `https://strimzi.io/charts/` 등록 (`../argocd/project.yaml`)
- operator 버전 확인 (작성 시점 `1.0.1`). 설치 전:
  ```bash
  helm repo add strimzi https://strimzi.io/charts/
  helm search repo strimzi/strimzi-kafka-operator --versions | head
  ```
  `kafka.yaml` 은 `spec.kafka.version` **미지정** — operator 가 지원하는 기본 Kafka 버전 사용(버전 불일치 회피). 특정 버전을 핀하려면 operator 문서의 지원 목록 확인 후 `spec.kafka.version` 명시.

## 2. 설치

GitOps — 두 Application 이 sync-wave 로 순서 보장:

- `strimzi-operator` (wave 6) — helm chart, operator + CRD. `watchNamespaces: [data]`.
- `kafka` (wave 8) — `kafka.yaml`(KafkaNodePool + Kafka CR). **CRD 가 먼저 등록돼야** 하므로 operator 다음.

부트스트랩/수동:

```bash
helm install strimzi-operator strimzi/strimzi-kafka-operator \
  -n data --version 1.0.1 -f operator.values.yaml --wait

kubectl apply -f kafka.yaml
```

> `kafka` Application 의 `directory.include` 는 **`kafka.yaml` 만** — 같은 폴더의 `operator.values.yaml`(helm values, k8s 매니페스트 아님)을 ArgoCD 가 적용하려다 깨지는 것 방지.

## 3. 검증

```bash
kubectl get pods -n data -l strimzi.io/cluster=kafka
kubectl get kafka,kafkanodepool -n data                       # READY=True
kubectl get svc -n data | grep kafka                          # kafka-kafka-bootstrap

# 토픽 produce/consume 왕복
kubectl -n data run kcat --rm -it --image=edenhill/kcat:1.7.1 --restart=Never -- \
  -b kafka-kafka-bootstrap:9092 -L                            # 메타데이터 = 브로커 1
```

ambient 캡처 (app↔kafka ztunnel mTLS):

```bash
istioctl ztunnel-config workloads -n data | grep kafka        # HBONE
```

앱에서 접근 — bootstrap: `kafka-kafka-bootstrap.data.svc.cluster.local:9092`.

## 4. 결정

### Strimzi operator (수동 StatefulSet 비채택)

Kafka 운영(롤링, 설정 reconcile, KRaft 메타데이터)을 operator 가 흡수. helm chart 로 설치 — `platform` AppProject `sourceRepos` 에 strimzi repo 1개 추가(jenkins/argocd 등과 동일 패턴). 멀티아치라 ARM64(A1.Flex) 자동.

### KRaft + node pools (Zookeeper 비채택)

Strimzi 1.0 은 KRaft + node pool 이 *유일 모드*(Zookeeper 제거) — 0.x 의 전환용 `strimzi.io/kraft`/`strimzi.io/node-pools` 어노테이션은 obsolete 라 미사용(공식 v1 예제도 생략). 단일 `KafkaNodePool`(`combined`)이 `controller`+`broker` 겸용 1노드. v1 스키마는 *파드 단위*(replicas/storage/resources)를 node pool 로, *클러스터 단위*(version/listeners/config/jvmOptions)를 `spec.kafka` 로 가른다.

### ephemeral (PV 0)

PV 2칸(Vault/Prometheus) 선점 상태 → Kafka 에 줄 PV 없음. `storage.type: ephemeral`(emptyDir, `sizeLimit: 5Gi`). 재시작/리스케줄 = 토픽·오프셋·클러스터ID 리셋 = "새 클러스터". 이벤트 흐름 *시연* 용도라 내구성 불요. 내구 필요 시 PV 예산 재조정 후 `type: persistent-claim`.

### single broker + replication factor 1

브로커 1개라 내부 토픽 기본 RF=3 이면 생성 실패 → 전부 1로:
`offsets.topic.replication.factor` / `transaction.state.log.replication.factor` / `transaction.state.log.min.isr` / `default.replication.factor` / `min.insync.replicas` = 1. HA 없음(데모 전제).

### plain listener + JVM heap 핀

internal `plain`(9092, TLS off) — mesh 내부 caller 전용. 엣지 노출 0, app↔kafka hop 은 ambient ztunnel L4 mTLS(redis/openbao 패턴 동일). `-Xms/-Xmx 512m` 로 heap 고정(24GB 공유 환경 보호), container limit `1536Mi` 로 non-heap/page cache 헤드룸.

### entityOperator 생략 (초기)

topic/user operator 미배포(RAM 절약). 토픽은 auto-create 또는 CLI. 선언적 토픽(`KafkaTopic` CR) 필요 시 `spec.entityOperator.topicOperator` 추가 — Pod +1.

## 5. 주의 사항

### CRD 선행 — operator 먼저

`kafka.yaml` 의 `Kafka`/`KafkaNodePool` 은 Strimzi CRD 가 있어야 적용됨. sync-wave(operator 6 < kafka 8)로 순서 보장. 수동 적용 시 operator/CRD 먼저. CRD 없이 apply 시 `no matches for kind "Kafka"`.

### ephemeral 재시작 손실

pod 재시작 = 전체 데이터+메타데이터 소실. 컨슈머 오프셋도 리셋되어 컨슈머가 `earliest`/`latest` 정책대로 재시작. 내구성 기대 ❌.

### 인증/인가 미설정 — in-mesh 한정

`plain` listener 무인증. ClusterIP 라 외부 노출 0, ambient mesh 내부만. 멀티테넌트 확장 시 `tls`/`scram-sha-512` listener + `KafkaUser`(userOperator) + NetworkPolicy. OpenBao 이관 후보.

### 리소스 압박

브로커 `1536Mi` + operator `512Mi` ≈ 2Gi. 24GB 공유라 Vault/Prometheus/Jenkins/ArgoCD 와 동시 기동 시 스케줄 확인. OOMKill(exit 137) 시 `jvmOptions` heap 또는 container limit 조정(동시).
