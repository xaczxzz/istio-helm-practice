# API 라우팅 설정 분석 보고서

## 📋 목차
1. [전체 아키텍처 개요](#전체-아키텍처-개요)
2. [포트 설정 분석](#포트-설정-분석)
3. [Istio 라우팅 설정](#istio-라우팅-설정)
4. [API Gateway 설정](#api-gateway-설정)
5. [마이크로서비스 엔드포인트](#마이크로서비스-엔드포인트)
6. [서비스 디스커버리](#서비스-디스커버리)
7. [문제점 및 개선사항](#문제점-및-개선사항)
8. [라우팅 플로우 다이어그램](#라우팅-플로우-다이어그램)

---

## 전체 아키텍처 개요

### 시스템 구성
```
클라이언트 (localhost:80, :443, :8081, :8082)
    ↓
Kind 클러스터 (NodePort 31541, 31542, 31543, 31026)
    ↓
Istio Ingress Gateway (app-gateway)
    ↓
VirtualService (frontend-virtualservice.yaml, app-vs.yaml)
    ↓
마이크로서비스 (API Gateway, Frontend, Order, Inventory, User)
```

---

## 포트 설정 분석

### 1. Kind 클러스터 포트 매핑 (k8s/kind-config.yaml)

| 컨테이너 포트 | 호스트 포트 | 프로토콜 | 용도 |
|---|---|---|---|
| 31541 | 80 | TCP | Istio HTTP (기본 트래픽) |
| 31542 | 8081 | TCP | 추가 HTTP 포트 |
| 31543 | 8082 | TCP | 추가 HTTP 포트 |
| 31026 | 443 | TCP | Istio HTTPS |
| 15021 | 15021 | TCP | Istio Ingress Gateway 상태 |

**분석:**
- ✅ HTTP/HTTPS 포트 매핑 정상
- ✅ 여러 포트 지원으로 다양한 서비스 노출 가능
- ⚠️ 8081, 8082 포트는 정의되었으나 사용 중인 서비스 없음

### 2. 서비스 포트 설정

| 서비스 | 컨테이너 포트 | 서비스 포트 | 프로토콜 |
|---|---|---|---|
| API Gateway | 8000 | 8000 | TCP |
| Frontend | 80 | 80 | TCP |
| Order Service | 8080 | 8080 | TCP |
| Inventory Service | 3000 | 3000 | TCP |
| User Service | 8000 | 8000 | TCP |

---

## Istio 라우팅 설정

### 1. Istio Gateway (k8s/istio/gateway.yaml)

#### app-gateway (기본 애플리케이션)
```yaml
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

**분석:**
- ✅ 모든 호스트에서 HTTP 80 포트 수신
- ✅ 기본 라우팅 게이트웨이로 적절

#### monitoring-gateway (모니터링 도구)
```yaml
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 9090
      name: http
      protocol: HTTP
    hosts:
    - "*"
```

**분석:**
- ⚠️ 포트 9090은 Kind 클러스터에 매핑되지 않음
- ❌ 모니터링 게이트웨이 접근 불가능

### 2. VirtualService 라우팅

#### frontend-virtualservice.yaml
```yaml
http:
- match:
    - uri:
        prefix: /api/
  route:
  - destination:
      host: app-stack-api-gateway
      port:
        number: 8000
- match:
    - uri:
        prefix: /monitoring/
  route:
  - destination:
      host: app-stack-api-gateway
      port:
        number: 8000
- match:
    - uri:
        prefix: /
  route:
  - destination:
      host: app-stack-frontend
      port:
        number: 80
```

**문제점:**
- ❌ 서비스 이름 불일치: `app-stack-api-gateway` vs 실제 `api-gateway`
- ❌ 서비스 이름 불일치: `app-stack-frontend` vs 실제 `frontend`

#### app-vs.yaml
```yaml
http:
- match:
    - uri:
        prefix: /api/kiali
  rewrite:
    uri: /
  route:
  - destination:
      host: kiali.istio-system.svc.cluster.local
      port:
        number: 20001
- match:
    - uri:
        prefix: /api/grafana
  route:
  - destination:
      host: monitoring-stack-grafana.monitoring.svc.cluster.local
      port:
        number: 80
- match:
    - uri:
        prefix: /api/jaeger
  route:
  - destination:
      host: jaeger-query.istio-system.svc.cluster.local
      port:
        number: 16686
- match:
    - uri:
        prefix: /api/prometheus
  route:
  - destination:
      host: monitoring-stack-kube-prom-prometheus.monitoring.svc.cluster.local
      port:
        number: 9090
- match:
    - uri:
        prefix: /api/
  route:
  - destination:
      host: api-gateway
      port:
        number: 8000
- match:
    - uri:
        prefix: /
  route:
  - destination:
      host: frontend
      port:
        number: 80
```

**분석:**
- ✅ 모니터링 도구 라우팅 정의 (Kiali, Grafana, Jaeger, Prometheus)
- ✅ API Gateway 라우팅 정의
- ✅ Frontend 캐치-올 라우팅
- ⚠️ 두 개의 VirtualService 파일이 동일 호스트에 대해 정의됨 (충돌 가능성)

---

## API Gateway 설정

### 1. API Gateway 구현 (apps/api-gateway/main.py)

#### 서비스 엔드포인트 설정
```python
SERVICES = {
    "order": os.getenv("ORDER_SERVICE_URL", "http://order-service:8080"),
    "inventory": os.getenv("INVENTORY_SERVICE_URL", "http://inventory-service:3000"),
    "user": os.getenv("USER_SERVICE_URL", "http://user-service:8000"),
}
```

#### 환경 변수 (helm/api-gateway/values.yaml)
```yaml
env:
  ORDER_SERVICE_URL: "http://app-stack-order-service:8080"
  INVENTORY_SERVICE_URL: "http://app-stack-inventory-service:3000"
  USER_SERVICE_URL: "http://app-stack-user-service:8000"
```

**문제점:**
- ❌ 환경 변수의 서비스 이름이 실제 Helm 생성 이름과 불일치
- ❌ `app-stack-order-service` vs 실제 `order-service`

### 2. API Gateway 라우트

| 엔드포인트 | 메서드 | 대상 서비스 | 설명 |
|---|---|---|---|
| `/health` | GET | - | API Gateway 헬스 체크 |
| `/metrics` | GET | - | Prometheus 메트릭 |
| `/` | GET | - | 루트 정보 |
| `/orders` | GET | Order Service | 주문 조회 |
| `/orders` | POST | Order Service | 주문 생성 |
| `/orders/health` | GET | Order Service | 주문 서비스 헬스 체크 |
| `/inventory` | GET | Inventory Service | 재고 조회 |
| `/inventory/health` | GET | Inventory Service | 재고 서비스 헬스 체크 |
| `/users` | GET | User Service | 사용자 조회 |
| `/users/health` | GET | User Service | 사용자 서비스 헬스 체크 |
| `/monitoring/*` | GET | - | 모니터링 도구 정보 |

---

## 마이크로서비스 엔드포인트

### 1. Order Service (apps/order-service/main.go)

| 엔드포인트 | 메서드 | 설명 |
|---|---|---|
| `/health` | GET | 헬스 체크 |
| `/metrics` | GET | Prometheus 메트릭 |
| `/orders` | GET | 모든 주문 조회 |
| `/orders` | POST | 새 주문 생성 |

**포트:** 8080
**데이터베이스:** PostgreSQL

### 2. Inventory Service (apps/inventory-service/server.js)

| 엔드포인트 | 메서드 | 설명 |
|---|---|---|
| `/health` | GET | 헬스 체크 |
| `/metrics` | GET | Prometheus 메트릭 |
| `/inventory` | GET | 전체 재고 조회 |
| `/inventory/:productId` | GET | 특정 상품 재고 조회 |
| `/inventory/:productId` | PUT | 재고 수량 업데이트 |
| `/inventory/check` | POST | 재고 확인 (주문 서비스용) |

**포트:** 3000
**데이터베이스:** PostgreSQL

### 3. User Service (apps/user-service/main.py)

| 엔드포인트 | 메서드 | 설명 |
|---|---|---|
| `/health` | GET | 헬스 체크 |
| `/metrics` | GET | Prometheus 메트릭 |
| `/users` | GET | 모든 사용자 조회 |
| `/users/{user_id}` | GET | 특정 사용자 조회 |
| `/users` | POST | 새 사용자 생성 |
| `/users/{user_id}` | PUT | 사용자 정보 업데이트 |
| `/users/{user_id}` | DELETE | 사용자 삭제 |

**포트:** 8000
**데이터베이스:** PostgreSQL

### 4. Frontend

| 엔드포인트 | 설명 |
|---|---|
| `/` | 정적 HTML 페이지 |
| `/style.css` | 스타일시트 |
| `/app.js` | JavaScript 애플리케이션 |

**포트:** 80
**웹 서버:** Nginx

---

## 서비스 디스커버리

### 1. Helm 생성 서비스 이름

Helm 차트의 `fullname` 템플릿에 따라 생성되는 서비스 이름:

```
{{ .Release.Name }}-{{ .Chart.Name }}
```

**예상 서비스 이름:**
- `app-stack-frontend`
- `app-stack-api-gateway`
- `app-stack-order-service`
- `app-stack-inventory-service`
- `app-stack-user-service`

### 2. 실제 서비스 이름 (Helm 템플릿 기반)

각 차트의 `_helpers.tpl`에서 정의:

```yaml
{{- define "service-name.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- .Release.Name }}-{{ .Chart.Name }}
{{- end }}
{{- end }}
```

**실제 생성 이름 (Release: app-stack):**
- `app-stack-frontend`
- `app-stack-api-gateway`
- `app-stack-order-service`
- `app-stack-inventory-service`
- `app-stack-user-service`

### 3. DNS 해석

Kubernetes 클러스터 내에서:
```
<service-name>.<namespace>.svc.cluster.local
```

**예:**
- `app-stack-api-gateway.default.svc.cluster.local:8000`
- `app-stack-order-service.default.svc.cluster.local:8080`
- `app-stack-inventory-service.default.svc.cluster.local:3000`
- `app-stack-user-service.default.svc.cluster.local:8000`

---

## 문제점 및 개선사항

### 🔴 심각한 문제

#### 1. VirtualService 서비스 이름 불일치
**파일:** `k8s/istio/frontend-virtualservice.yaml`
**문제:**
```yaml
destination:
  host: app-stack-api-gateway  # ❌ 잘못된 이름
  port:
    number: 8000
```

**해결책:**
```yaml
destination:
  host: app-stack-api-gateway.default.svc.cluster.local
  port:
    number: 8000
```

#### 2. API Gateway 환경 변수 불일치
**파일:** `helm/api-gateway/values.yaml`
**문제:**
```yaml
env:
  ORDER_SERVICE_URL: "http://app-stack-order-service:8080"  # ✅ 올바름
  INVENTORY_SERVICE_URL: "http://app-stack-inventory-service:3000"  # ✅ 올바름
  USER_SERVICE_URL: "http://app-stack-user-service:8000"  # ✅ 올바름
```

**분석:** 실제로는 올바르게 설정되어 있음

#### 3. 모니터링 게이트웨이 포트 미매핑
**파일:** `k8s/kind-config.yaml`
**문제:** 포트 9090이 Kind 클러스터에 매핑되지 않음
**해결책:**
```yaml
extraPortMappings:
- containerPort: 31090  # Istio NodePort
  hostPort: 9090
  protocol: TCP
```

### 🟡 중간 수준의 문제

#### 4. 두 개의 VirtualService 충돌
**파일:** `k8s/istio/frontend-virtualservice.yaml` vs `k8s/istio/virtual-services/app-vs.yaml`
**문제:** 동일한 호스트에 대해 두 개의 VirtualService 정의
**해결책:** 하나의 VirtualService로 통합

#### 5. 미사용 포트 매핑
**파일:** `k8s/kind-config.yaml`
**문제:** 포트 8081, 8082가 정의되었으나 사용되지 않음
**해결책:** 필요 없으면 제거

### 🟢 개선 권장사항

#### 6. 서비스 이름 명시성 개선
**현재:** 짧은 이름 사용 (예: `api-gateway`)
**권장:** FQDN 사용 (예: `api-gateway.default.svc.cluster.local`)

#### 7. 헬스 체크 엔드포인트 통일
**현재:** 각 서비스마다 다른 경로
**권장:** 모든 서비스에서 `/health` 사용

#### 8. 타임아웃 설정 추가
**현재:** VirtualService에 타임아웃 설정 없음
**권장:**
```yaml
http:
- match:
    - uri:
        prefix: /api/
  route:
  - destination:
      host: api-gateway
      port:
        number: 8000
  timeout: 30s
  retries:
    attempts: 3
    perTryTimeout: 10s
```

---

## 라우팅 플로우 다이어그램

### 요청 흐름 (정상 케이스)

```
클라이언트 요청
  ↓
localhost:80 (Host Port)
  ↓
Kind 클러스터 31541 (NodePort)
  ↓
Istio Ingress Gateway (app-gateway)
  ↓
VirtualService (app-vs.yaml)
  ↓
┌─────────────────────────────────────────────────────────┐
│ 경로 매칭                                                 │
├─────────────────────────────────────────────────────────┤
│ /api/kiali → kiali.istio-system:20001                   │
│ /api/grafana → monitoring-stack-grafana.monitoring:80   │
│ /api/jaeger → jaeger-query.istio-system:16686           │
│ /api/prometheus → monitoring-stack-kube-prom-prometheus │
│ /api/* → api-gateway:8000                               │
│ /* → frontend:80                                        │
└─────────────────────────────────────────────────────────┘
  ↓
대상 서비스
  ↓
응답 반환
```

### API Gateway 내부 라우팅

```
API Gateway (:8000)
  ↓
┌──────────────────────────────────────────────────────┐
│ 경로 매칭                                              │
├──────────────────────────────────────────────────────┤
│ /orders → Order Service:8080                         │
│ /inventory → Inventory Service:3000                  │
│ /users → User Service:8000                           │
│ /monitoring/* → 모니터링 도구 정보 반환               │
│ /health → API Gateway 헬스 체크                       │
│ /metrics → Prometheus 메트릭                          │
└──────────────────────────────────────────────────────┘
  ↓
마이크로서비스 또는 응답 반환
```

---

## 테스트 엔드포인트 (scripts/07-test-api-endpoints.sh)

### 테스트 URL 분석

| 테스트 | URL | 예상 결과 |
|---|---|---|
| Frontend Health | `http://localhost:8080/health` | ❌ 잘못된 포트 |
| API Gateway Health | `http://localhost:8080/api/health` | ❌ 잘못된 포트 |
| Order Service Health | `http://localhost:8080/api/orders/health` | ❌ 잘못된 포트 |
| User Service Health | `http://localhost:8080/api/users/health` | ❌ 잘못된 포트 |
| Inventory Service Health | `http://localhost:8080/api/inventory/health` | ❌ 잘못된 포트 |

**문제:** 테스트 스크립트가 포트 8080을 사용하지만, 실제 Istio Ingress Gateway는 포트 80에서 수신

**해결책:**
```bash
BASE_URL="http://localhost"  # 포트 80 사용
```

---

## 요약 및 권장사항

### ✅ 올바르게 설정된 항목
1. Kind 클러스터 기본 포트 매핑 (80, 443)
2. 마이크로서비스 포트 설정
3. API Gateway 환경 변수 (실제로는 올바름)
4. 각 서비스의 엔드포인트 구현

### ❌ 수정 필요한 항목
1. 모니터링 게이트웨이 포트 매핑 추가
2. VirtualService 통합 (중복 제거)
3. 테스트 스크립트 포트 수정 (8080 → 80)

### 🔧 개선 권장사항
1. FQDN 사용으로 서비스 이름 명시성 개선
2. VirtualService에 타임아웃/재시도 정책 추가
3. 미사용 포트 매핑 제거
4. 서비스 간 통신 정책 (NetworkPolicy) 추가
5. 모니터링 도구 접근성 개선

