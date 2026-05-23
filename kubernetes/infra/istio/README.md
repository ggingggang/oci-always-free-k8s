# Istio Ambient

서비스 메시 + Gateway API 데이터플레인. Ambient 모드 (sidecar 비채택).

참조: https://istio.io/latest/docs/ambient/install/helm/

## 1. 전제 조건

- Gateway API CRD 설치 완료 (`../gateway-api/`)
- `istio-system` 네임스페이스 존재 (`../namespaces/namespaces.yaml`)
- Helm 3.6+ (또는 4)
- 권장 버전: **Istio 1.29.x** (`~1.29.0` SemVer 범위)

## 2. 설치

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

helm install istio-base istio/base    -n istio-system --version "~1.29.0" -f base.values.yaml    --wait
helm install istiod     istio/istiod  -n istio-system --version "~1.29.0" -f istiod.values.yaml  --wait
helm install istio-cni  istio/cni     -n istio-system --version "~1.29.0" -f cni.values.yaml     --wait
helm install ztunnel    istio/ztunnel -n istio-system --version "~1.29.0" -f ztunnel.values.yaml --wait

kubectl apply -f gateway.yaml
```

```bash
```

## 3. 검증

```bash
kubectl get pods -n istio-system
kubectl get gatewayclass
kubectl get gateway -n istio-system
kubectl get deployment,svc -n istio-system -l gateway.networking.k8s.io/gateway-name=public-gateway
curl -v http://<GATEWAY_IP>/   # HTTPRoute 미연결 상태에서 404 + server: istio-envoy 가 정상
```

```bash
```

## 4. 결정

### Ambient 채택

| 항목 | sidecar | ambient |
|------|---------|---------|
| Pod당 추가 RAM | ~40-50MB (envoy sidecar) | 0 |
| 노드당 추가 RAM | 0 | ~80MB (ztunnel) |
| L7 정책 | 즉시 가능 | waypoint 별도 배포 시 가능 |
| Pod restart | 주입 시 강제 | 불필요 |
| GA | 오래됨 | 2024-11 (1.24) |

OCI Always Free 24GB RAM, 앱 파드 10개 가정 시 sidecar는 400-500MB 추가. ambient는 노드 2개 × 80MB = 160MB. L7 필요 시점에만 waypoint 추가.

### Istio Gateway Helm chart 비채택

Helm으로 깔리는 4개: `base`, `istiod`, `cni`, `ztunnel`.

`istio/gateway` chart는 깔지 않는다. 외부 트래픽을 Gateway API 표준 리소스(`Gateway`, `HTTPRoute`)로 처리하기로 결정. `istio/gateway` chart는 구식 Istio Gateway CR용 envoy를 띄우는 chart라 본 결정과 모순.

Gateway API `Gateway` 리소스를 선언하면 Istio가 reconcile하면서 envoy Deployment + Service를 자동 프로비저닝한다. NLB annotation은 `spec.infrastructure.annotations` 필드로 전달.

### 트래픽 분리 원칙

- 남북(외부 ↔ 클러스터): Gateway API (`Gateway`, `HTTPRoute`, `GRPCRoute`)
- 동서(클러스터 내부 정책): Istio CR (`PeerAuthentication`, `AuthorizationPolicy`)
- `VirtualService` / 구 `Gateway`(Istio CR) 신규 작성 금지

### OCI Network LB (L4 TCP passthrough)

Flexible LB(L7) 대신 NLB 선택.

사유: Istio Gateway envoy가 TLS 종료 + L7 라우팅을 단독 책임. L7 LB를 앞단에 두면 (1) 라우팅 책임 중복, (2) 인증서 두 군데 관리, (3) 불필요한 TLS 재암호화. NLB로 TCP passthrough 시 책임 경계 명확 + cert-manager 단일 관리.

annotation은 `gateway.yaml` 참조. AWS NLB / GCP TCP LB와 동일한 권장 패턴.

### istioctl 비채택

Helm only. istioctl로 설치 시 GitOps drift 추적 불가.

### profile=ambient 사후 변경 불가

ambient → sidecar 전환은 사실상 재설치. 결정 본 단계에서 고정.

## 5. 주의 사항

### Cilium chaining 도입 시 CNI 순서 충돌 가능

본 클러스터는 추후 Cilium chaining (`generic-veth` 모드)을 Flannel 위에 올릴 예정. 그 시점에 CNI chain 순서:

```
Flannel  →  Cilium (NetworkPolicy + Hubble)  →  Istio CNI (ambient redirect)
```

Istio CNI는 `cni.chained: true`로 설정되어 마지막 위치를 기대함. Cilium chaining 설치 매니페스트에서 `cni-conf-path` 우선순위를 확인하고 충돌 시 `cniBinDir` / `cniConfDir` 명시 override 필요.

### TLS 보류 상태

`gateway.yaml`의 listener는 현재 HTTP 80 단독. HTTPS 443 + redirect 추가는 cert-manager + ClusterIssuer 설치 후. 그 시점에 listener 추가 + `tls.certificateRefs` 박음.

### istio-system PSA

ambient의 ztunnel + istio-cni는 host network + privileged container 필요. `istio-system` 네임스페이스에 PSA label 적용 금지 (`namespaces.yaml`에서 의도적으로 미적용).

### Values override 범위

`*.values.yaml`은 chart default 위에 *덮어쓰는 override만* 명시. 전체 schema 확인:

```bash
helm show values istio/base    --version "~1.29.0"
helm show values istio/istiod  --version "~1.29.0"
helm show values istio/cni     --version "~1.29.0"
helm show values istio/ztunnel --version "~1.29.0"
```
