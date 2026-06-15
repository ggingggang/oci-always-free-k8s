# Tailscale

관리 플레인 접근 경로. subnet router pod 1개가 VCN + Service CIDR을 tailnet에 광고 — kubectl / DB / admin UI를 사설 경로로 전환하고 퍼블릭 admin 표면을 제거.

참조:
- https://tailscale.com/kb/1185/kubernetes (2026-06 확인)
- https://tailscale.com/docs/install/cloud/oracle-cloud (2026-06 확인 — VM 기준이나 DNS/포트 주의점 공유)

## 1. 전제 조건

- `tailscale` 네임스페이스 + PSA `enforce=baseline` (`../namespaces/`)
- Tailscale 계정 + admin console 접근
- 노트북 등 접속 기기에 tailscale 클라이언트 설치
- 이미지 핀: `tailscale/tailscale:v1.92.4` (2026-06 작성 시점 stable)

## 2. 설치

### 2-1. ACL — tag + 라우트 자동 승인

admin console → Access Controls 에 추가:

```json
"tagOwners": {
  "tag:k8s-router": ["autogroup:admin"]
},
"autoApprovers": {
  "routes": {
    "10.0.0.0/16":  ["tag:k8s-router"],
    "10.96.0.0/16": ["tag:k8s-router"]
  }
}
```

### 2-2. OAuth client 발급 (auth key 비채택 — 만료 없음)

admin console → Settings → **OAuth clients** → Generate:

- Scope: `Keys` → `Auth Keys` (write)
- Tag: `tag:k8s-router`

client secret(`tskey-client-...`)이 만료 없는 등록 자격이 됨. tagged 노드는 node key expiry 도 기본 비활성.

### 2-3. Secret + 적용

```bash
kubectl create secret generic tailscale-auth \
  -n tailscale \
  --from-literal=authkey='<your-ts-oauth-client-secret>?ephemeral=false&preauthorized=true'

kubectl apply -f rbac.yaml
kubectl apply -f deployment.yaml
```

`preauthorized=true` — 기기 승인 자동. 라우트 승인은 2-1 의 `autoApprovers` 가 처리 → **사람 손 가는 단계 0**.

### 2-4. kubeconfig private endpoint 전환

```bash
oci ce cluster create-kubeconfig \
  --cluster-id "$(terraform -chdir=../../../terraform output -raw oke_cluster_id)" \
  --file ~/.kube/config \
  --region <your-region> \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT
```

## 3. 검증

```bash
kubectl get pods -n tailscale
kubectl logs -n tailscale deploy/tailscale-router | grep -iE 'authenticate|routes|health' | tail -5

# 노트북에서 (tailscale up 상태)
tailscale status                  # oke-vcn-router 보이는지
kubectl get nodes                 # private endpoint 경유
mysql -h 10.0.201.7 -P 3306 -u admin -p --ssl-mode=REQUIRED   # DB 직행
```

직결/릴레이 확인:

```bash
tailscale ping oke-vcn-router
# "via DERP" = 릴레이 경유 — 설계된 동작 (주의 사항 참조)
```

### 검증 후 컷오버 — 퍼블릭 admin 표면 제거

tailnet 경유 kubectl/DB가 **확인된 후에만**:

```bash
# 1. admin UI 퍼블릭 제거 (external-dns가 DNS 레코드 자동 철거)
kubectl delete httproute argocd jenkins -n cicd

# 2. NSG 6443 룰 제거 — terraform/modules/iam/main.tf 의
#    kubectl_api rule 삭제 후 apply
```

이후 admin UI 접근: `http://<argocd-server ClusterIP>` / `http://<jenkins ClusterIP>:8080` (tailnet 경유).

## 4. 결정

### pod (VM 비채택)

Always Free AMD VM subnet router 대안 비채택 — 관리 대상 OS 1개 추가 + tailscale 버전 관리 별도. pod는 이미지 핀 + 매니페스트로 클러스터 운영 모델에 흡수. NAT Gateway 뒤 outbound-only라 인바운드 NSG/SL 룰 0건.

### userspace mode (kernel mode 비채택)

kernel mode는 `/dev/net/tun` + `NET_ADMIN` 필요 = PSA baseline 위반. userspace mode는 특수 권한 0개 — 인바운드(tailnet → 클러스터) 용도에 충분. 클러스터 → tailnet 방향 발신이 필요해지면 재검토.

### per-device (site-to-site 비채택)

OCI Site-to-Site VPN(IPSec): 집 고정 거점 모델 — 로밍 불가 + 집에 CPE 24/7 + 동적 IP 갱신 부담으로 기각. Tailscale site-to-site(양쪽 subnet router): 집 LAN 전체가 신뢰 범위에 들어와 기기 신원 모델보다 후퇴 — 기각. 키 가진 기기만 접근하는 per-device 채택.

### state를 k8s Secret에 영속

`TS_KUBE_SECRET=tailscale-state` — pod 재생성에도 노드 신원 유지 (재인증 불요). RBAC는 해당 Secret 1개로 `resourceNames` 한정.

### TS_ACCEPT_DNS=false

tailnet DNS가 pod resolv.conf를 덮으면 클러스터 DNS(CoreDNS) 깨짐. 비활성 고정.

## 5. 주의 사항

### DERP 릴레이 폴백은 설계된 동작

pod가 NAT Gateway 뒤라 인바운드 hole punching 수신 불가 — 직결 성립은 클라이언트 쪽 NAT에 달림. LTE/CGNAT 환경이면 DERP 릴레이 경유 확정. kubectl/SQL 대역폭에는 영향 없음. "왜 느리지" 디버깅 대상 아님.

### OAuth client secret 회전

만료는 없으나 *유출 시 수동 revoke + 재발급* (admin console). `tailscale-auth` Secret 갱신 후 pod 재시작. OpenBao 이관 후보. state Secret(`tailscale-state`)이 살아있는 한 등록 자격은 최초 1회만 쓰임 — 평시 의존 없음.

### break-glass — 클러스터 다운 = 접근 경로 동반 다운

tailscale pod가 클러스터 안에 살므로 클러스터 장애 시 사설 경로도 죽음. 복구 경로:

1. OKE API 공인 엔드포인트는 존속 (`is_public_ip_enabled = true` 유지)
2. `terraform/modules/iam/main.tf`에 6443 ingress 룰 재추가 + apply
3. kubeconfig public endpoint로 재생성 → 복구 작업
4. 복구 후 룰 제거 원복

### non-root 기동 실패 시

`runAsUser: 1000` + userspace 조합은 문서상 지원이나, 이미지 버전에 따라 socket 경로 권한 이슈 가능. CrashLoop 시 1차 조치: pod securityContext의 `runAsUser`/`runAsNonRoot` 제거 (root 기동 — baseline은 통과). 원인은 로그로 확인 후 결정.
