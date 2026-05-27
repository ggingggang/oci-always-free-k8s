# Jenkins (JCasC + emptyDir)

선언적 Jenkins. 모든 설정은 JCasC(Configuration as Code)로 git 추적, controller는 emptyDir 운영.

참조:
- https://github.com/jenkinsci/configuration-as-code-plugin
- https://artifacthub.io/packages/helm/jenkinsci/jenkins
- https://github.com/jenkinsci/kubernetes-plugin

## 1. 전제 조건

- `cicd` + `build` 네임스페이스 존재 (`../../infra/namespaces/namespaces.yaml`)
  - `cicd` — Jenkins controller (PSA `baseline`)
  - `build` — Kaniko 빌드 Pod 격리 (PSA `privileged`)
- Gateway API CRD + Istio Gateway `public-gateway` 동작 (`../../infra/istio/`)
- cert-manager + wildcard Certificate Ready=True (`../../infra/cert-manager/`)
- external-dns 동작 (`../../infra/external-dns/`)
- Helm 3.6+
- 권장 버전: jenkins/jenkins chart `~5.8.0`

## 2. 설치

```bash
export DOMAIN=<your-domain>
export EMAIL=<your-email>
export GHCR_USER=<your-github-user>
export GHCR_TOKEN=<your-ghcr-write-token>

kubectl apply -f rbac.yaml

kubectl create secret docker-registry ghcr-push \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_TOKEN}" \
  -n build

helm repo add jenkins https://charts.jenkins.io
helm repo update

sed -e "s|<your-domain>|${DOMAIN}|g" -e "s|<your-email>|${EMAIL}|g" values.yaml \
  | helm install jenkins jenkins/jenkins -n cicd --version "~5.8.0" -f - --wait

sed -e "s|<your-domain>|${DOMAIN}|g" httproute.yaml | kubectl apply -f -
```

`ghcr-push` Secret 은 `build` NS 에 존재해야 함 (Kaniko podTemplate 이 마운트). GHCR token scope: `write:packages` + `read:packages`. 향후 Vault Agent Injector 또는 GitHub App Installation Token 으로 이관 예정.

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

Kaniko podTemplate 적용 확인:

```bash
kubectl exec -n cicd jenkins-0 -c jenkins -- \
  cat /var/jenkins_home/casc_configs/*.yaml | grep -A2 "label: kaniko"

kubectl get secret ghcr-push -n build -o jsonpath='{.type}'
# kubernetes.io/dockerconfigjson 출력되어야 함

kubectl get sa kaniko-builder -n build
```

Jenkins UI → Manage Jenkins → Clouds → kubernetes → Pod Templates → `kaniko` 항목 존재 확인.

## 4. 결정

### emptyDir + JCasC

PV(`oci-bv` 50Gi) 대신 emptyDir. 사유:

- **분배 정합** — Always Free Block Volume 4볼륨 한도 (boot 2 + PV 2). PV 슬롯은 Vault + Prometheus 우선
- **GitOps 단일 진실** — 모든 설정이 `values.yaml` JCasC seed에 박힘. UI 클릭으로 영구 변경 ❌ (UI 변경은 next reload에서 git값으로 덮임)
- **DR narrative** — pod 날아가도 git이 source of truth. PV 복원 불필요
- **trade-off**: 빌드 history 손실 (재시작마다). 다만 빌드 메타데이터는 git + GHCR + Loki(observability 도입 시)에 영구 보존

### 단일 인스턴스 controller

HA controller는 Jenkins 라이선스/플러그인 호환성 폭증. 본 환경은 Always Free 24GB RAM에서 *동작/재현성*이 *고가용성*보다 우위. RTO는 "JCasC 재로드 + agent pod 재생성"으로 분단위.

### Plugins 전체 pin + `installLatestPlugins: false`

73개 plugin 모두 `<name>:<version>` 형식 명시 pin. *재현성 우선* — 같은 values.yaml 로 어디서 install 해도 같은 plugin set.

핵심 plugin 그룹:

- **Pipeline 코어**: `workflow-*` 12종 + `pipeline-*` 9종 + `pipeline-model-*` 4종 (Declarative Pipeline 포함)
- **Kubernetes plugin**: `kubernetes` + `kubernetes-client-api` + `kubernetes-credentials` (동적 agent)
- **JCasC**: `configuration-as-code` + `snakeyaml-api`
- **GitHub/Git 연동**: `git`, `git-client`, `github`, `github-api`, `github-branch-source`, `credentials-binding`
- **UI**: `pipeline-stage-view`, `pipeline-rest-api`, `dashboard-view` 류
- **Transitive deps**: API plugin 다수 (`commons-*`, `jackson2-api`, `okhttp-api` 등) — *명시 pin 안 하면 UC-latest 로 떠서 mismatch 발생 위험*

명시 일부 pin 만으로는 transitive 통제 불가. `pipeline-model-api/extensions/definition` trio 처럼 release wave 가 어긋나면 Declarative Pipeline 로드 실패. *전체 plugin set 을 한 번에 pin* 하는 것이 유일한 재현성 보장.

#### Plugin upgrade 절차

CVE 발생 또는 chart bump 시:

1. 안전 환경에서 `installLatestPlugins: true` + 임시 install → 동작 검증
2. plugin manager 또는 script console 로 실 설치 version 캡처:
   ```bash
   kubectl exec -n cicd jenkins-0 -c jenkins -- \
     ls /var/jenkins_home/plugins | awk -F'.jpi' '{print $1}' | sort -u
   ```
   또는 `https://jenkins.<domain>/script` 에서:
   ```groovy
   Jenkins.instance.pluginManager.plugins.each { println "${it.shortName}:${it.version}" }
   ```
3. 출력을 values.yaml `installPlugins` 로 박음 (정렬 권장)
4. `installLatestPlugins: false` 유지
5. helm upgrade + rollout restart → 재현성 회복

plugin 단독 upgrade ❌ — JCasC + chart + plugin 조합 호환성 검증된 묶음 유지.

### Agent — Kubernetes plugin + `containerCap: 2`

빌드 agent는 동적 Pod (`agent.enabled: true`). 동시 빌드 2개로 제한 (24GB RAM 환경 보호). 빌드 종료 시 Pod 자동 삭제 — stateless.

agent image 태그 핀 (`3327.v868139a_d00e0-3-alpine`) — `latest-alpine` floating 회피. 빌드 환경 재현성을 chart pin 정신과 정합.

### Kaniko podTemplate — `agent.podTemplates.kaniko`

JCasC 로 선언적 정의. Jenkinsfile 에서 `agent { label 'kaniko' }` 만 쓰면 됨.

핵심 결정:

- **`build` NS 격리** — Kaniko 가 root + capabilities 요구. `cicd` 의 PSA `baseline` 을 우회하지 않고 `build` NS (`enforce: privileged`) 로 분리. controller 침해 시 빌드 SA 직접 도달 ❌
- **`kaniko-builder` SA + `automountServiceAccountToken: false`** — Kaniko 는 GHCR push 외 k8s API 호출 불필요. SA 토큰 마운트 차단으로 *빌드 컨테이너가 k8s API 통한 측면 이동 ❌*
- **`:v1.23.2-debug` 이미지** — Jenkins Kubernetes plugin 이 컨테이너에 `sleep` 주입해서 agent 가 살아 있어야 `exec` 가능. `:debug` 는 busybox 포함, default `:latest` 는 executor binary 만 있어 sleep ❌
- **`ghcr-push` Secret projected 마운트** — `/kaniko/.docker/config.json` 으로 kaniko 가 자동 인식. Secret type `kubernetes.io/dockerconfigjson` 필수
- **ARM64 빌드** — A1.Flex 워커. Kaniko 는 호스트 아키텍처 따라감 → ARM 자동. Jenkinsfile 에서 `--customPlatform=linux/arm64` 명시 권장 (base image multi-arch 검증 의무)

cache + memory 폭주 회피 args (Jenkinsfile 에서 주입):

```bash
--cache=true
--cache-repo=ghcr.io/${GHCR_USER}/cache
--cache-ttl=168h
--snapshot-mode=redo
--use-new-run
```

Jenkinsfile 예시:

```groovy
pipeline {
  agent { label 'kaniko' }
  environment {
    GIT_SHA = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
  }
  stages {
    stage('build & push') {
      steps {
        container('kaniko') {
          sh '''
            /kaniko/executor \
              --dockerfile=Dockerfile \
              --context=`pwd` \
              --destination=ghcr.io/${GHCR_USER}/myapp:${GIT_SHA} \
              --cache=true \
              --cache-repo=ghcr.io/${GHCR_USER}/cache \
              --customPlatform=linux/arm64 \
              --snapshot-mode=redo \
              --use-new-run
          '''
        }
      }
    }
  }
}
```

### `numExecutors: 0` on controller

controller는 빌드 안 함. agent Pod만 빌드 → controller는 *오케스트레이션 전용* 격리. controller resource 보호 + 빌드 격리.

### RBAC — controller `cicd`, 빌드 `build`

`rbac.yaml` 구조:

- `cicd/jenkins` SA — controller 신원. agent Pod 관리 권한 두 곳에 분배:
  - `cicd` NS — 일반 빌드 agent Pod CRUD
  - `build` NS — Kaniko 빌드 Pod CRUD (cross-NS RoleBinding)
- `build/kaniko-builder` SA — 빌드 Pod 신원. `automountServiceAccountToken: false`. k8s API 권한 0건

권한 경계 narrative:

- controller (`jenkins` SA) 는 *Pod 만들 권한* 만 가짐 — image 자체에 대한 권한 ❌
- 빌드 Pod (`kaniko-builder` SA) 는 *GHCR push token* 만 가짐 — Pod 만들 권한 ❌
- 둘 다 `app` NS 권한 0건 — 배포는 git commit (manifest 패턴) 으로만

manifest commit 패턴: Jenkins 는 *k8s API 직접 호출 ❌*, *git push (앱 레포 deploy/values.yaml 에 image tag commit)* 만. ArgoCD 가 git diff 감지해서 `app` NS 에 적용 → *권한 경계가 git 레벨에서 강제됨*.

### HTTPRoute — https-wildcard listener attach

`jenkins.<your-domain>` 으로 노출. `public-gateway` 의 `https-wildcard` listener (cert SAN의 `*.<your-domain>` 매칭). HTTP→HTTPS redirect는 `../../infra/istio/http-redirect.yaml` 이 catch-all 처리.

external-dns가 HTTPRoute의 `hostnames` 를 source로 sync → Cloudflare A 레코드 자동 생성.

### Secret 운영 — `ghcr-push` 만 선행, 나머지는 앱 레포 시점

본 setup 에 필수: `ghcr-push` 1종 (Kaniko 빌드용, `build` NS).

앱 레포 등장 시점에 추가 도입:

- `ghcr-pull` — 앱 Pod (`app` NS) `imagePullSecrets`
- `github-manifest-pat` — Jenkins 가 앱 레포 `deploy/values.yaml` 에 image tag commit (또는 GitHub App Installation Token 으로 직행)
- `gh-webhook-secret` — GitHub Webhook HMAC SHA-256 검증

4종 모두 Vault Agent Injector 또는 GitHub App 으로 이관 예정.

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

### Kaniko 빌드 실패 디버깅

```bash
kubectl get pods -n build
kubectl logs -n build <kaniko-pod> -c kaniko
kubectl describe pod -n build <kaniko-pod>
```

흔한 원인:

- `ghcr-push` Secret 누락 또는 type 불일치 → `unauthorized: authentication required`
  - `kubectl get secret ghcr-push -n build -o jsonpath='{.type}'` 가 `kubernetes.io/dockerconfigjson` 인지 확인
- PSA 거부 → Pod 생성 실패. `build` NS 가 `privileged` enforce 인지 확인
- base image multi-arch 미보장 → `manifest unknown` 또는 `no matching manifest for linux/arm64`. base image 의 `docker manifest inspect <image>` 로 ARM64 포함 확인
- OOMKilled (exit 137) → cache 미사용 시 흔함. `--cache=true` + `--snapshot-mode=redo` 적용. limit `2Gi` 부족하면 chart values 의 podTemplate memory limit 상향
- Jenkins controller 가 `build` NS 에 Pod 못 만듦 → `rbac.yaml` 의 `jenkins-builder` RoleBinding 적용 확인

### 단일 인스턴스 RTO

controller pod 단일. node 장애 시:
- 정상: ~3분 (k8s scheduler가 다른 노드로 재배치 + JCasC reload + plugin 로드)
- 노드 둘 다 장애: terraform apply 후 재설치 (~30분)

ArgoCD가 Jenkins Application으로 관리하면 cluster 재구축 시 ArgoCD sync 한 번에 복구.
