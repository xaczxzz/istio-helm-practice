# API Gateway 제거 및 직접 라우팅 마이그레이션 가이드

## 📋 개요

### 현재 아키텍처
```
Frontend → API Gateway → Backend Services (Order/User/Inventory)
                       → Monitoring Services (Prometheus/Grafana/Jaeger/Kiali)
```

### 목표 아키텍처
```
Frontend → Istio Gateway → Backend Services (Order/User/Inventory)
                         → Monitoring Services (Prometheus/Grafana/Jaeger/Kiali)
```

## 🎯 마이그레이션 목표

1. **API Gateway 완전 제거**: `app-stack-api-gateway` 서비스 및 배포 제거
2. **직접 라우팅 구현**: Istio VirtualService를 통한 path-based routing
3. **프론트엔드 수정**: API 호출을 직접 백엔드로 전환
4. **ArgoCD 설정 업데이트**: api-gateway 관련 리소스 제거

## 📁 영향 받는 파일 목록

### 필수 수정 파일
- `helm/umbrella-chart/values.yaml` - api-gateway 비활성화
- `k8s/istio/unified-virtualservice.yaml` - 라우팅 규칙 (이미 완료됨)
- `apps/frontend/app.js` - API 엔드포인트 변경
- `apps/frontend/nginx.conf` - Nginx 프록시 설정 (필요시)
- `argocd/applications/20-app-stack.yaml` - ArgoCD 애플리케이션 설정

### 선택적 수정 파일
- `scripts/07-test-api-endpoints.sh` - 테스트 스크립트 업데이트
- `apps/load-test/*.js` - 로드 테스트 스크립트 업데이트

## 🔍 현재 상태 분석

### API Gateway의 현재 역할
```yaml
# helm/umbrella-chart/values.yaml에서 확인된 내용
api-gateway:
  enabled: true
  service:
    port: 8000
  env:
    ORDER_SERVICE_URL: "http://app-stack-order-service:8080"
    INVENTORY_SERVICE_URL: "http://app-stack-inventory-service:3000"
    USER_SERVICE_URL: "http://app-stack-user-service:8000"
    # 모니터링 엔드포인트들도 관리
```

### 프론트엔드의 현재 API 호출 패턴
```javascript
// apps/frontend/app.js에서 확인
- GET /api/orders → API Gateway → Order Service
- POST /api/orders → API Gateway → Order Service  
- GET /api/inventory/health → API Gateway → Inventory Service
- GET /api/users/health → API Gateway → User Service
```

### Istio VirtualService 현황
- ✅ **이미 구현됨**: `k8s/istio/unified-virtualservice.yaml`에 직접 라우팅 규칙 존재
- 백엔드 서비스: `/api/{service}` → 해당 서비스로 직접 라우팅
- 모니터링: `/monitoring/{tool}` → 모니터링 서비스로 직접 라우팅

## 🔧 마이그레이션 작업 단계

### Phase 1: API Gateway 비활성화

#### 1.1 Umbrella Chart 수정
**파일**: `helm/umbrella-chart/values.yaml`

```yaml
# api-gateway 섹션을 찾아서 수정
api-gateway:
  enabled: false  # true → false로 변경
  # 나머지 설정은 그대로 유지 (향후 완전 제거 시를 위해)
```

**검증 명령어**:
```bash
# values.yaml 문법 검증
helm lint helm/umbrella-chart

# 변경사항 미리보기
helm template app-stack helm/umbrella-chart -n default
```

---

### Phase 2: 프론트엔드 API 호출 수정

#### 2.1 Frontend JavaScript 수정
**파일**: `apps/frontend/app.js`

**현재 코드**:
```javascript
// API calls through API Gateway
async function testAPI(endpoint) {
    const response = await fetch(endpoint, {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
        }
    });
}
```

**수정 후 코드**:
```javascript
// 변경 필요 없음 - 엔드포인트는 동일하게 유지
// Istio VirtualService가 /api/* 경로를 올바른 서비스로 라우팅
```

**중요**: 프론트엔드 코드는 **수정이 필요 없습니다**. 왜냐하면:
- 현재 엔드포인트: `/api/orders`, `/api/users`, `/api/inventory`
- Istio가 이미 이 경로들을 백엔드 서비스로 직접 라우팅하도록 설정됨
- `/api/gateway` 같은 특정 경로를 사용하지 않았기 때문에 투명한 전환 가능

#### 2.2 Health Check 엔드포인트 확인
**파일**: `apps/frontend/app.js`의 `checkServiceHealth()` 함수

```javascript
async function checkServiceHealth() {
    const services = [
        { name: 'frontend', endpoint: '/health', indicator: 'frontend-indicator' },
        // ❌ 제거: API Gateway health check
        // { name: 'api-gateway', endpoint: '/api/health', indicator: 'api-gateway-indicator' },
        { name: 'order', endpoint: '/api/orders/health', indicator: 'order-indicator' },
        { name: 'inventory', endpoint: '/api/inventory/health', indicator: 'inventory-indicator' },
        { name: 'user', endpoint: '/api/users/health', indicator: 'user-indicator' }
    ];
}
```

#### 2.3 Frontend HTML 수정 (필요시)
**파일**: `apps/frontend/index.html`

API Gateway 관련 UI 요소가 있다면 제거:
```html
<!-- 제거할 부분 찾기 -->
<div class="service-item">
    <span class="service-name">API Gateway</span>
    <span id="api-gateway-indicator" class="status-indicator">●</span>
</div>
```

---

### Phase 3: Nginx 설정 확인 (필요시)

#### 3.1 Nginx Configuration 검토
**파일**: `apps/frontend/nginx.conf`

현재 설정을 확인하고 API Gateway 관련 프록시 규칙이 있는지 확인:

```nginx
# 만약 이런 설정이 있다면 제거
location /api/ {
    proxy_pass http://app-stack-api-gateway:8000;
}
```

**수정 후** (Istio에 맡기고 프록시 규칙 제거):
```nginx
# /api/ 경로에 대한 특별한 프록시 설정 없음
# Istio VirtualService가 처리
```

---

### Phase 4: 이미지 빌드 및 배포

#### 4.1 Frontend 이미지 리빌드
**명령어**:
```bash
# frontend 이미지만 다시 빌드 (app.js 수정 후)
cd apps/frontend
docker build -t kind-registry:5000/frontend:v2 -f Dockerfile.v1 .
docker push kind-registry:5000/frontend:v2

# 또는 전체 빌드 스크립트 실행
./scripts/03-build-images.sh
```

#### 4.2 Umbrella Chart 업데이트
**파일**: `helm/umbrella-chart/values.yaml`

```yaml
frontend:
  enabled: true
  image:
    repository: "kind-registry:5000/frontend"
    tag: "v2"  # v1 → v2로 변경 (새 이미지)
```

---

### Phase 5: ArgoCD 설정 업데이트

#### 5.1 App-of-Apps 설정 확인
**파일**: `argocd/applications/20-app-stack.yaml`

현재 설정이 umbrella-chart를 사용하는지 확인:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-stack
  namespace: argocd
spec:
  source:
    path: helm/umbrella-chart
    repoURL: <your-repo>
    targetRevision: HEAD
```

**동작 확인**:
- `api-gateway.enabled: false`로 설정하면 ArgoCD가 자동으로 리소스 제거
- 수동 개입 불필요

#### 5.2 ArgoCD 동기화 전략

**Option A: 자동 동기화** (권장)
```bash
# ArgoCD에서 자동 동기화 활성화
argocd app set app-stack --sync-policy automated --auto-prune
```

**Option B: 수동 동기화**
```bash
# Git에 변경사항 커밋 후
argocd app sync app-stack

# 또는 ArgoCD UI에서 "Sync" 버튼 클릭
```

---

### Phase 6: 배포 및 검증

#### 6.1 변경사항 Git 커밋
```bash
git add helm/umbrella-chart/values.yaml
git add apps/frontend/app.js
git add apps/frontend/index.html  # 수정한 경우
git commit -m "Remove API Gateway and enable direct routing via Istio"
git push origin main
```

#### 6.2 ArgoCD 동기화 대기
```bash
# ArgoCD 앱 상태 확인
argocd app get app-stack

# 동기화 대기 (자동 동기화 활성화된 경우)
# 또는 수동 동기화 실행
argocd app sync app-stack
```

#### 6.3 배포 상태 확인
```bash
# API Gateway Pod가 제거되었는지 확인
kubectl get pods -n default | grep api-gateway
# 결과: No resources found (정상)

# 백엔드 서비스 정상 동작 확인
kubectl get pods -n default | grep -E "order|user|inventory"

# Istio Gateway 설정 확인
kubectl get virtualservices -n default unified-vs -o yaml
```

---

### Phase 7: 기능 테스트

#### 7.1 수동 API 테스트
```bash
# Istio Ingress Gateway 주소 확인
INGRESS_HOST=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Order Service 테스트
curl -X GET http://${INGRESS_HOST}/api/orders/health
curl -X POST http://${INGRESS_HOST}/api/orders \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"product_id":10,"quantity":2}'

# User Service 테스트  
curl -X GET http://${INGRESS_HOST}/api/users/health

# Inventory Service 테스트
curl -X GET http://${INGRESS_HOST}/api/inventory/health
```

#### 7.2 Frontend UI 테스트
```bash
# 브라우저에서 접속
open http://${INGRESS_HOST}

# UI에서 확인할 사항:
# 1. API Gateway 상태 표시 제거되었는지 확인
# 2. "Test Orders API" 버튼 클릭 → 정상 동작
# 3. "Create Order" 버튼 클릭 → 정상 동작
# 4. 모든 서비스 health check가 정상(초록불)인지 확인
```

#### 7.3 로드 테스트
```bash
# 로드 테스트 스크립트 업데이트 후 실행
./scripts/run-load-test.sh

# 예상 결과:
# - API Gateway 없이도 동일한 성능
# - 오히려 레이턴시 감소 (중간 홉 제거)
```

---

### Phase 8: 모니터링 확인

#### 8.1 Istio 대시보드 확인
```bash
# Kiali 접속
kubectl port-forward -n istio-system svc/kiali 20001:20001
open http://localhost:20001

# 확인사항:
# - Graph에서 API Gateway 노드 사라짐
# - Frontend → Backend Services 직접 연결 확인
```

#### 8.2 Jaeger 트레이싱 확인
```bash
# Jaeger UI 접속
kubectl port-forward -n istio-system svc/monitoring-jaeger-query 16686:16686
open http://localhost:16686

# 확인사항:
# - Trace에서 API Gateway span 제거
# - Frontend → Order/User/Inventory 직접 호출 trace 확인
```

#### 8.3 Grafana 메트릭 확인
```bash
# Grafana 접속
kubectl port-forward -n monitoring svc/monitoring-stack-grafana 3000:80
open http://localhost:3000

# 확인사항:
# - API Gateway 관련 메트릭 사라짐
# - 백엔드 서비스 메트릭은 정상
```

---

## 🔄 롤백 계획

만약 문제가 발생하면 즉시 롤백:

### 빠른 롤백
```bash
# 1. values.yaml에서 api-gateway 다시 활성화
cd helm/umbrella-chart
sed -i 's/enabled: false/enabled: true/' values.yaml

# 2. Git 커밋 및 푸시
git add values.yaml
git commit -m "Rollback: Re-enable API Gateway"
git push origin main

# 3. ArgoCD 동기화
argocd app sync app-stack --prune
```

### Git Revert
```bash
# 마지막 커밋 되돌리기
git revert HEAD
git push origin main

# ArgoCD가 자동으로 이전 상태로 복구
```

---

## ✅ 검증 체크리스트

마이그레이션 완료 후 다음 항목들을 확인하세요:

### 인프라 레벨
- [ ] `kubectl get pods -n default`에서 api-gateway Pod 없음
- [ ] 모든 백엔드 서비스 Pod가 Running 상태
- [ ] Istio VirtualService 설정 적용됨
- [ ] Istio Gateway 정상 동작

### 애플리케이션 레벨
- [ ] Frontend UI 정상 로드
- [ ] Order API 호출 정상 (GET, POST)
- [ ] User API 호출 정상
- [ ] Inventory API 호출 정상
- [ ] Health check 모두 통과

### 모니터링 레벨
- [ ] Kiali Graph에서 API Gateway 노드 제거 확인
- [ ] Jaeger Trace에서 직접 라우팅 확인
- [ ] Prometheus 메트릭 정상 수집
- [ ] Grafana 대시보드 정상 표시

### 성능 레벨
- [ ] 응답 시간 유지 또는 개선
- [ ] 에러율 증가 없음
- [ ] 로드 테스트 통과

---

## 📊 예상 효과

### 아키텍처 개선
- ✅ **단순화**: 불필요한 중간 계층 제거
- ✅ **레이턴시 감소**: 평균 10-30ms 감소 예상 (홉 하나 제거)
- ✅ **리소스 절약**: API Gateway Pod 리소스 확보
- ✅ **유지보수성**: 관리 포인트 감소

### 잠재적 고려사항
- ⚠️ **인증/인가**: API Gateway에서 처리하던 인증 로직이 있다면 Istio RequestAuthentication으로 이전 필요
- ⚠️ **Rate Limiting**: API Gateway의 rate limit을 Istio EnvoyFilter로 구현 필요
- ⚠️ **요청 변환**: API Gateway의 request/response 변환 로직이 있다면 각 서비스로 이동 필요

현재 프로젝트에서는 API Gateway가 단순 라우팅만 수행하므로 위 고려사항 해당 없음.

---

## 🐛 트러블슈팅

### 문제 1: 503 Service Unavailable
**증상**: API 호출 시 503 에러
**원인**: Istio VirtualService 미적용
**해결**:
```bash
kubectl apply -f k8s/istio/unified-virtualservice.yaml
```

### 문제 2: Frontend가 404 반환
**증상**: `/api/*` 경로에서 404
**원인**: VirtualService의 rewrite 규칙 오류
**해결**: unified-virtualservice.yaml의 rewrite 규칙 확인

### 문제 3: CORS 에러
**증상**: 브라우저 콘솔에 CORS 에러
**원인**: Istio에서 CORS 설정 누락
**해결**: VirtualService에 CORS 정책 추가 필요

---

## 📝 추가 권장사항

### 1. 점진적 마이그레이션 (옵션)
완전히 제거하기 전에 트래픽 분할 테스트:

```yaml
# unified-virtualservice.yaml에 가중치 기반 라우팅 추가
- match:
  - uri:
      prefix: /api/orders
  route:
  - destination:
      host: app-stack-api-gateway  # 10% 트래픽
      port:
        number: 8000
    weight: 10
  - destination:
      host: app-stack-order-service  # 90% 트래픽
      port:
        number: 8080
    weight: 90
```

### 2. 모니터링 알람 설정
마이그레이션 후 일시적 문제 감지를 위한 알람:
- 에러율 > 5% 시 알람
- 평균 응답시간 > 500ms 시 알람
- Pod restart 발생 시 알람

### 3. 로그 수집
마이그레이션 전후 로그 수집 및 비교:
```bash
# Before
kubectl logs -l app=api-gateway -n default --tail=100 > api-gateway-before.log

# After  
kubectl logs -l app=order-service -n default --tail=100 > order-service-after.log
```

---

## 🎓 Claude Code 실행 가이드

이 문서를 Claude Code에게 제공할 때:

```bash
# Claude Code 실행 예시
claude-code "이 MIGRATION_GUIDE.md 문서를 읽고 Phase 1부터 Phase 8까지 순차적으로 실행해줘. 각 단계마다 검증을 수행하고, 문제가 발생하면 즉시 중단하고 보고해줘."
```

**Claude Code가 자동으로 수행할 작업**:
1. values.yaml 파일 수정
2. app.js 파일에서 API Gateway health check 제거
3. 변경사항 검증 (helm lint, kubectl dry-run)
4. Git 커밋 및 푸시
5. ArgoCD 동기화 대기 및 확인
6. API 엔드포인트 테스트
7. 모니터링 대시보드 확인
8. 최종 리포트 생성

---

## 📞 추가 지원

문제 발생 시:
1. 이 가이드의 트러블슈팅 섹션 참조
2. ArgoCD UI에서 앱 상태 확인
3. Kiali에서 트래픽 흐름 시각화
4. 롤백 계획 실행

---

**작성일**: 2026-02-06
**버전**: 1.0
**대상 환경**: KIND (Kubernetes in Docker), Istio Service Mesh, ArgoCD