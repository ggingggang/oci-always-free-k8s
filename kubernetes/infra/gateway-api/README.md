# Gateway API CRD

Gateway API v1.5.0 standard channel CRD 설치.
Istio `base` chart, cert-manager, external-dns 모두의 선행 조건.

참조 : https://gateway-api.sigs.k8s.io/guides/getting-started/introduction/#installing-gateway-api

## 1. 전제 조건

- kubectl 접근 가능 상태

## 2. 설치

`kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml`

```bash
customresourcedefinition.apiextensions.k8s.io/backendtlspolicies.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gatewayclasses.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/gateways.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/grpcroutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/httproutes.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/listenersets.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/referencegrants.gateway.networking.k8s.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/tlsroutes.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicy.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
validatingadmissionpolicybinding.admissionregistration.k8s.io/safe-upgrades.gateway.networking.k8s.io serverside-applied
```

## 3. 검증

```bash
kubectl get crd
```

```bash
NAME                                           CREATED AT
backendtlspolicies.gateway.networking.k8s.io   2026-05-21T11:49:51Z
gatewayclasses.gateway.networking.k8s.io       2026-05-21T11:49:51Z
gateways.gateway.networking.k8s.io             2026-05-21T11:49:52Z
grpcroutes.gateway.networking.k8s.io           2026-05-21T11:49:52Z
httproutes.gateway.networking.k8s.io           2026-05-21T11:49:52Z
listenersets.gateway.networking.k8s.io         2026-05-21T11:49:52Z
nodeoperationrules.oci.oraclecloud.com         2026-05-20T09:49:36Z # 기본값
referencegrants.gateway.networking.k8s.io      2026-05-21T11:49:52Z
tlsroutes.gateway.networking.k8s.io            2026-05-21T11:49:52Z
```

## 4. 결정

Istio Helm chart는 Gateway API CRD를 자동으로 함께 설치하는 옵션을 제공한다.
해당 옵션을 비활성화하고 여기서 별도 관리한다.

사유: Istio 업그레이드 시 CRD 버전도 Istio chart가 임의로 변경할 수 있어 버전 관리 책임이 불명확해짐. 
Gateway API CRD는 이 매니페스트에서 단독으로 버전 핀을 관리한다.
