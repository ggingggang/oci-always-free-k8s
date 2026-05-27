# Jenkins (JCasC + emptyDir)

선언적 Jenkins. 모든 설정은 JCasC(Configuration as Code)로 git 추적, controller는 emptyDir 운영.

참조:
- https://github.com/jenkinsci/configuration-as-code-plugin
- https://artifacthub.io/packages/helm/jenkinsci/jenkins
- https://github.com/jenkinsci/kubernetes-plugin

## 1. 전제 조건

- `cicd` 네임스페이스 존재 (`../../infra/namespaces/namespaces.yaml`)
- Gateway API CRD + Istio Gateway `public-gateway` 동작 (`../../infra/istio/`)
- cert-manager + wildcard Certificate Ready=True (`../../infra/cert-manager/`)
- external-dns 동작 (`../../infra/external-dns/`)
- Helm 3.6+
- 권장 버전: jenkins/jenkins chart `~5.8.0`

## 2. 설치

```bash
export DOMAIN=<your-domain>
export EMAIL=<your-email>

kubectl apply -f rbac.yaml

helm repo add jenkins https://charts.jenkins.io
helm repo update

sed -e "s|<your-domain>|${DOMAIN}|g" -e "s|<your-email>|${EMAIL}|g" values.yaml \
  | helm install jenkins jenkins/jenkins -n cicd --version "~5.8.0" -f - --wait

sed -e "s|<your-domain>|${DOMAIN}|g" httproute.yaml | kubectl apply -f -
```

초기 admin 계정 (chart가 자동 생성한 `jenkins` Secret 사용):

```bash
kubectl get secret jenkins -n cicd -o jsonpath='{.data.jenkins-admin-user}'     | base64 -d ; echo
kubectl get secret jenkins -n cicd -o jsonpath='{.data.jenkins-admin-password}' | base64 -d ; echo
```

## 3. 검증

```bash
kubectl get pods -n cicd
kubectl get svc,httproute -n cicd
kubectl logs -n cicd jenkins-0 -c jenkins --tail=50 | grep -i "casc\|configuration-as-code"
```

JCasC 적용 확인:

```bash
kubectl exec -n cicd jenkins-0 -c jenkins -- ls /var/jenkins_home/casc_configs/
```

브라우저:
- `https://jenkins.<your-domain>` 접근 → 로그인 → JCasC seed에 박힌 system message 확인
- Manage Jenkins → Configuration as Code → "Reload existing configuration" 동작 확인

**선언성 검증 — pod 재시작 후 동일 상태**:

```bash
kubectl delete pod jenkins-0 -n cicd
kubectl wait --for=condition=ready pod/jenkins-0 -n cicd --timeout=180s
# 브라우저 재접속 → 동일 system message + admin 사용자 유지 확인 (emptyDir이라도 JCasC가 재구성)
```

DNS 자동 등록 (external-dns + Cloudflare):

```bash
nslookup "jenkins.${DOMAIN}" 1.1.1.1
curl -vIk "https://jenkins.${DOMAIN}"
```

## 4. 결정

### emptyDir + JCasC

PV(`oci-bv` 50Gi) 대신 emptyDir. 사유:

- **분배 정합** — Always Free Block Volume 4볼륨 한도 (boot 2 + PV 2). PV 슬롯은 Vault + Prometheus 우선
- **GitOps 단일 진실** — 모든 설정이 `values.yaml` JCasC seed에 박힘. UI 클릭으로 영구 변경 ❌ (UI 변경은 next reload에서 git값으로 덮임)
- **DR narrative** — pod 날아가도 git이 source of truth. PV 복원 불필요
- **trade-off**: 빌드 history 손실 (재시작마다). 다만 빌드 메타데이터는 git + GHCR + Loki(observability 도입 시)에 영구 보존

### 단일 인스턴스 controller

HA controller는 Jenkins 라이선스/플러그인 호환성 폭증. 본 환경은 Always Free 24GB RAM에서 *동작/재현성*이 *고가용성*보다 우위. RTO는 "JCasC 재로드 + agent pod 재생성"으로 분단위.

### Plugins 명시 + `installLatestPlugins: false`

chart default + 추가 9개 명시:
- `kubernetes` — Kubernetes plugin (동적 agent)
- `workflow-aggregator` — Pipeline core
- `configuration-as-code` — JCasC
- `job-dsl` — Job DSL syntax
- `git`, `github`, `github-branch-source`, `credentials-binding` — GitHub/GHCR 연동 (다음 turn Secret 4종 시점에 활용)
- `pipeline-stage-view` — UI 가시성

`installLatestPlugins: false` — chart에 박힌 plugin 버전 핀 사용. 재현성 우선. plugin upgrade는 chart 버전 bump와 함께.

### Agent — Kubernetes plugin + `containerCap: 2`

빌드 agent는 동적 Pod (`agent.enabled: true`). 동시 빌드 2개로 제한 (24GB RAM 환경 보호). 빌드 종료 시 Pod 자동 삭제 — stateless.

다음 turn에 podTemplate 추가 (Go/Java 빌드 환경, `imagePullSecrets: [ghcr-pull]` 등).

### `numExecutors: 0` on controller

controller는 빌드 안 함. agent Pod만 빌드 → controller는 *오케스트레이션 전용* 격리. controller resource 보호 + 빌드 격리.

### RBAC — agent Pod 관리 권한만

`rbac.yaml`은 `cicd` namespace 안의 Pod/ConfigMap/Secret read + agent Pod CRUD만. `app` namespace 권한 ❌.

사유: **manifest commit 패턴 채택**. Jenkins는 *k8s API 직접 호출 ❌*, *git push (앱 레포 deploy/values.yaml에 image tag commit)* 만. ArgoCD가 git diff 감지해서 app NS에 적용. *권한 경계가 git 레벨에서 강제됨*.

### HTTPRoute — https-wildcard listener attach

`jenkins.<your-domain>` 으로 노출. `public-gateway` 의 `https-wildcard` listener (cert SAN의 `*.<your-domain>` 매칭). HTTP→HTTPS redirect는 `../../infra/istio/http-redirect.yaml` 이 catch-all 처리.

external-dns가 HTTPRoute의 `hostnames` 를 source로 sync → Cloudflare A 레코드 자동 생성.

### Secret 4종 — 다음 turn

`ghcr-push`, `ghcr-pull`, `github-manifest-pat`, `gh-webhook-secret` 은 본 setup에 불필요. 빌드 파이프라인 turn에 함께 생성.

## 5. 주의 사항

### JCasC 적용 실패 시

```bash
kubectl logs -n cicd jenkins-0 -c jenkins | grep -iE "casc|configuration-as-code|error"
```

흔한 원인:
- `configScripts` YAML 들여쓰기 깨짐 → multi-line literal block (`|`) 사용 강제
- plugin 누락 — `configuration-as-code` plugin 명시 + chart 버전과 호환 확인
- 변수 치환 누락 — `<your-domain>`, `<your-email>` 가 sed로 치환됐는지 확인
- `JCasC.defaultConfig: true` + 동일 key 중복 → `ConfiguratorConflictException`. chart 기본 JCasC가 채우는 키(`jenkins.numExecutors`, `unclassified.location.url/adminAddress` 등)는 `configScripts`에서 재정의 ❌. 대신 chart value(`controller.numExecutors`, `controller.jenkinsUrl`, `controller.jenkinsAdminEmail`)로 설정

### Plugin 업그레이드 정책

`installLatestPlugins: false` 라 chart pin 사용. 보안 패치 필요 시:

1. chart 버전 bump (`helm search repo jenkins/jenkins` 로 patch version 확인)
2. 또는 `installPlugins` 에 명시 버전 박기 (예: `git:5.2.0`)

CVE 발생 시 plugin 단독 upgrade는 비권장 — JCasC + chart + plugin 조합 호환성 검증된 묶음 유지.

### emptyDir 빌드 history 손실

빌드 메타데이터는 controller pod 재시작 시 모두 손실. *수용 가능*:
- 빌드 결과물(image): GHCR에 영구 보존
- 빌드 로그: observability stack의 Loki에 수집 (Alloy)
- 빌드 트리거 이력: GitHub commit + webhook 로그
- 파이프라인 정의: git (Jenkinsfile)

→ source of truth가 *git + GHCR + Loki* 분산. controller PV ❌도 무손실.

### 초기 admin 비밀번호 회전

chart가 자동 생성한 `jenkins-admin-password` Secret은 *plain text*. 운영 진입 시:

1. JCasC `securityRealm` 을 GitHub OAuth (또는 Dex) 로 전환 — 보안 강화 단계
2. `jenkins-admin` 사용자 비활성화 또는 강력한 비밀번호로 변경
3. 초기 admin Secret 삭제

### Gateway listener attach 실패 시

```bash
kubectl describe httproute jenkins -n cicd | grep -A5 "Conditions\|Parents"
```

`ResolvedRefs: False` 또는 `Accepted: False` 시 원인:
- Gateway `public-gateway` 의 `allowedRoutes.namespaces.from: All` 확인
- `sectionName: https-wildcard` 가 Gateway listener 이름과 정확히 일치하는지 확인
- backend service `jenkins` 가 같은 `cicd` namespace에 존재하는지 확인

### prometheus integration

현재 `prometheus.enabled: false`. kube-prometheus-stack 도입 후 활성화 — `prometheus.serviceMonitor.enabled: true` + ServiceMonitor 자동 등록. 빌드 큐 길이, agent 생성 시간, 빌드 실패율 메트릭 수집.

### 단일 인스턴스 RTO

controller pod 단일. node 장애 시:
- 정상: ~3분 (k8s scheduler가 다른 노드로 재배치 + JCasC reload + plugin 로드)
- 노드 둘 다 장애: terraform apply 후 재설치 (~30분)

ArgoCD가 Jenkins Application으로 관리하면 cluster 재구축 시 ArgoCD sync 한 번에 복구.
