# Gateway API CRD

Gateway API v1.5.0 standard channel CRD. Istio (`base`/Gateway 컨트롤러), cert-manager (Gateway integration), external-dns (`gateway-httproute` source) 모두의 선행 조건.

참조: https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/#installing-gateway-api

## 1. 전제 조건

- kubectl 접근 가능

## 2. 설치

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml
```

CRD 9개 + ValidatingAdmissionPolicy 1개 설치:

- `gatewayclasses`, `gateways`, `httproutes`, `grpcroutes`, `tlsroutes`
- `backendtlspolicies`, `referencegrants`, `listenersets`
- `safe-upgrades.gateway.networking.k8s.io` (ValidatingAdmissionPolicy + Binding)

`--server-side` 필수 — CRD가 client-side apply의 annotation size 제한(262144 bytes)을 초과.

## 3. 검증

```bash
kubectl get crd -l gateway.networking.k8s.io/bundle-version
kubectl get crd -o jsonpath='{range .items[?(@.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version)]}{.metadata.name}{"\t"}{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}{end}'
```

모든 CRD가 `v1.5.0` 으로 표기되어야 함.

## 4. 결정

### CRD를 Istio chart에서 분리

Istio Helm chart는 `pilot.env.PILOT_ENABLE_GATEWAY_API_DEPLOYMENT_CONTROLLER` + `installPackagedCustomResourceDefinitions` 옵션으로 Gateway API CRD를 함께 깔 수 있음. **비채택.**

사유: Istio 업그레이드 시 CRD 버전을 Istio chart가 임의로 변경 → 버전 관리 책임이 Istio측으로 흡수되어 불명확해짐. Gateway API CRD는 본 매니페스트에서 단독 핀 관리.

`istio/base` chart의 values에 명시적으로 옵션 끔 (`base.values.yaml` 참조).

### Standard channel

Standard channel — GA + Beta 리소스만. Experimental channel(`experimental-install.yaml`)은 BackendLBPolicy, ServiceImport 등 알파 리소스 포함. 현 단계 미사용 → standard로 충분.

향후 멀티 클러스터 traffic split, BackendLBPolicy 같은 알파 기능 도입 시 experimental 채널로 교체 검토.

### Server-side apply

`--server-side`로 적용. CRD가 client-side annotation 제한 초과 + 추후 cert-manager/Istio가 동일 CRD를 server-side 소유권으로 reconcile할 때 충돌 회피.

## 5. 주의 사항

### CRD 업그레이드

```bash
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/vX.Y.Z/standard-install.yaml
```

major 변경(v1.x → v2.x) 시 호환성 표 확인 (`https://gateway-api.sigs.k8s.io/concepts/versioning/`). Istio가 지원하는 Gateway API 버전 범위와 교집합 안에서 갈아끼움.

### CRD 삭제 금지

`kubectl delete crd ...` 는 해당 CRD의 모든 CR을 cascade 삭제 → Gateway/HTTPRoute 다 사라지고 트래픽 절단. CRD 제거는 클러스터 폐기 시점 한정.

### Istio chart의 자동 설치 옵션 확인

본 결정과 충돌하지 않도록 `istio/base` chart values에서 Gateway API CRD 자동 설치 옵션이 꺼져있어야 함. Istio 업그레이드 시 chart default 변경 가능성 → release notes 확인 필수.
