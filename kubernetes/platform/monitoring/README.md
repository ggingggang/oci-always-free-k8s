# Monitoring (kube-prometheus-stack)

메트릭/알림/대시보드. Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics + prometheus-operator 일괄.

참조:
- https://github.com/prometheus-community/helm-charts (chart `prometheus-community/kube-prometheus-stack`)
- https://kubernetes.io/docs/concepts/security/pod-security-standards/ (PSA baseline)

## 1. 전제 조건

- `monitoring` 네임스페이스 + PSA `enforce=baseline` (`../../infra/namespaces/`)
- Grafana 외부 노출용: `public-gateway` `https-wildcard` listener + wildcard TLS Secret `public-wildcard-tls` Ready (`../../infra/istio/`, `../../infra/cert-manager/`)
- external-dns 동작 — HTTPRoute hostname → Cloudflare DNS (`../../infra/external-dns/`)
- Helm 3.6+
- 권장 버전: 작성 시점 추론 `~75.0.0` — chart가 app 버전을 추종해 major를 자주 올림. 설치 전 확인:
  ```bash
  helm search repo prometheus-community/kube-prometheus-stack --versions | head
  ```

> `kubectl top` / CPU 기반 HPA 는 이 스택이 아니라 별도 **metrics-server**(`metrics.k8s.io`)가 필요. node-exporter ≠ metrics-server.

## 2. 설치

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --version "~75.0.0" -f values.yaml --wait

kubectl apply -f httproute.yaml
```

Grafana admin 비밀번호 (chart 자동 생성):

```bash
kubectl -n monitoring get secret grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d ; echo
# https://grafana.ggang.cloud → admin / <위 출력>
```

## 3. 검증

```bash
kubectl get pods -n monitoring

kubectl -n monitoring get httproute grafana \
  -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' ; echo
# 기대: True

dig +short grafana.ggang.cloud
```

Prometheus 타겟 (전부 up, control-plane `down` 타겟 없어야 함):

```bash
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090/targets
```

## 4. 결정

### kube-prometheus-stack 채택
operator + Prometheus + Alertmanager + Grafana + node-exporter + kube-state-metrics + 기본 룰/대시보드 일괄. 컴포넌트 개별 설치 대비 ServiceMonitor/CRD 정합 유지가 쉬움.

### OKE managed control plane — control-plane 스크랩 비활성
`kubeControllerManager` / `kubeScheduler` / `kubeEtcd` / `kubeProxy` `enabled: false`. OKE는 컨트롤 플레인이 관리형이라 해당 메트릭 엔드포인트 접근 불가 → 켜두면 영구 `down` 타겟 + 오탐 알림. 노드/워크로드 메트릭만 수집.

### node-exporter hostNetwork 비활성
PSA `baseline`은 호스트 네임스페이스(hostNetwork)를 금지. `hostNetwork: false`로 baseline 충족. host `/proc`·`/sys` hostPath 마운트는 baseline 허용이라 노드 메트릭 수집 정상 — ServiceMonitor가 pod IP:9100으로 스크랩.

### Grafana 외부 노출 — Gateway 단일 TLS 종료
argocd 패턴 동일. Grafana는 ClusterIP HTTP, `public-gateway`가 `*.ggang.cloud` 와일드카드로 TLS 종료. mesh 내부는 Istio Ambient L4 mTLS.

### 스토리지 — Prometheus 영속 안 함 (로컬 emptyDir)
OCI Block Volume 최소 단위 50GB — `10Gi` 요청해도 50GB로 올림 + Always Free 한도(총 200GB, jenkins 50 + openbao 50 + 노드 부트볼륨)에서 50GB 차감. 메트릭 history에 블록볼륨 한 칸을 태우지 않기로 하고 **노드 로컬 emptyDir**(`sizeLimit 5Gi`) + 짧은 retention(`3d`/`4GB`). 재시작 시 history 소실 수용 — Loki(오브젝트 스토리지) / Tempo(emptyDir) 후속과 정합. Grafana/Alertmanager도 ephemeral.

### 리소스 핀 — Always Free tight
24GB 분배에서 Vault/기존 컴포넌트와 공존하도록 tight. mem limit만 설정(cpu limit 미설정 — throttling 회피).

## 5. 주의 사항

### chart 버전 / CRD
major를 자주 올림 — upgrade 전 CHANGELOG breaking change 확인. CRD는 chart가 설치하지만 `helm uninstall` 시 잔존. major upgrade 시 CRD 수동 apply가 필요할 수 있음.

### Prometheus 로컬 디스크 / OOM
`retentionSize 4GB` < emptyDir `sizeLimit 5Gi` — 한도 전에 prune되게. emptyDir는 노드 부트볼륨을 공유하므로 sizeLimit 초과 시 pod evict. 타겟 급증으로 mem 압박 시 `resources.limits.memory` 상향. 영속이 필요해지면 50Gi PVC(oci-bv)로 전환하되 블록볼륨 한도 확인.

### Grafana admin Secret 회전
`grafana` Secret 평문 base64. 최초 로그인 후 변경. OpenBao 이관 후보.

### metrics-server 별도
HPA(CPU/메모리)·`kubectl top` 필요 시 metrics-server를 따로 설치. 보유 여부: `kubectl get deploy -n kube-system metrics-server`.
