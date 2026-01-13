# API 라우팅 설정 수정 및 개선 가이드

## 1. 긴급 수정 사항

### 1.1 테스트 스크립트 포트 수정

**파일:** `scripts/07-test-api-endpoints.sh`

**현재 (❌ 잘못됨):**
```bash
BASE_URL="http://localhost:8080"
```

**수정 (✅ 올바름):**
```bash
BASE_URL="http://localhost"  # 포트 80 사용 (Istio Ingress Gateway)
```

**이유:** Istio Ingress Gateway가 포트 80에서 수신하므로, 포트 8080은 클러스터 내부 서비스 포트

---

### 1.2 모니터링 게이트웨이 포트 매핑 추가

**파일:** `k8s/kind-config.yaml`

**현재 (❌ 불완전):**
```yaml
extraPortMappings:
- containerPort: 31541
  hostPort: 80
  protocol: TCP
- containerPort: 31542
  hostPort: 8081
  protocol: TCP
- containerPort: 31543
  hostPort: 8082
  protocol: TCP
- containerPort: 31026
  hostPort: 443
  protocol: TCP
- containerPort: 15021
  hostPort: 15021
  protocol: TCP
```

**수정 (✅ 개선):**
```yaml
extraPortMappings:
# Istio HTTP (NodePort 31541 -> Host 80)
- containerPort: 31541
  hostPort: 80
  protocol: TCP
# Istio HTTPS (NodePort 31026 -> Host 443)
- containerPort: 31026
  hostPort: 443
  protocol: TCP
# Istio Ingress Gateway Status
- containerPort: 15021
  hostPort: 15021
  protocol: TCP
# Monitoring Gateway (NodePort 31090 -> Host 9090)
- containerPort: 31090
  hostPort: 9090
  protocol: TCP
```

**이유:** 모니터링 게이트웨이(포트 9090)가 접근 불가능하므로 추가 필요

---

### 1.3 VirtualService 통합 및 정리

**문제:** 두 개의 VirtualService 파일이 동일 호스트에 대해 정의됨

**파일:** `k8s/istio/frontend-virtualservice.yaml` (삭제 권장)

**파일:** `k8s/istio/virtual-services/app-vs.yaml` (유지 및 개선)

**수정된 app-vs.yaml:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: app-vs
  namespace: default
spec:
  hosts:
  - "*"
  gateways:
  - app-gateway
  http:
  # Monitoring routes with proper FQDN
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
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
  
  - match:
    - uri:
        prefix: /api/grafana
    rewrite:
      uri: /
    route:
    - destination:
        host: monitoring-stack-grafana.monitoring.svc.cluster.local
        port:
          number: 80
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
  
  - match:
    - uri:
        prefix: /api/jaeger
    rewrite:
      uri: /
    route:
    - destination:
        host: jaeger-query.istio-system.svc.cluster.local
        port:
          number: 16686
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
  
  - match:
    - uri:
        prefix: /api/prometheus
    rewrite:
      uri: /
    route:
    - destination:
        host: monitoring-stack-kube-prom-prometheus.monitoring.svc.cluster.local
        port:
          number: 9090
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
  
  # API Gateway routes with proper FQDN
  - match:
    - uri:
        prefix: /api/
    route:
    - destination:
        host: app-stack-api-gateway.default.svc.cluster.local
        port:
          number: 8000
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
  
  # Frontend routes (catch-all) with proper FQDN
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: app-stack-frontend.default.svc.cluster.local
        port:
          number: 80
    timeout: 30s
```

**개선 사항:**
- ✅ FQDN 사용으로 명시성 개선
- ✅ 타임아웃 설정 추가 (30초)
- ✅ 재시도 정책 추가 (3회 시도)
- ✅ 중복 VirtualService 제거

---

## 2. 권장 개선 사항

### 2.1 Istio Retry Policy 적용

**파일:** `k8s/istio/retry-policy.yaml` (새로 생성)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-gateway-vs
  namespace: default
spec:
  hosts:
  - api-gateway
  http:
  - route:
    - destination:
        host: app-stack-api-gateway.default.svc.cluster.local
        port:
          number: 8000
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: order-service-vs
  namespace: default
spec:
  hosts:
  - order-service
  http:
  - route:
    - destination:
        host: app-stack-order-service.default.svc.cluster.local
        port:
          number: 8080
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: inventory-service-vs
  namespace: default
spec:
  hosts:
  - inventory-service
  http:
  - route:
    - destination:
        host: app-stack-inventory-service.default.svc.cluster.local
        port:
          number: 3000
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: user-service-vs
  namespace: default
spec:
  hosts:
  - user-service
  http:
  - route:
    - destination:
        host: app-stack-user-service.default.svc.cluster.local
        port:
          number: 8000
    timeout: 30s
    retries:
      attempts: 3
      perTryTimeout: 10s
```

---

### 2.2 DestinationRule 추가 (Circuit Breaker)

**파일:** `k8s/istio/destination-rules.yaml` (새로 생성)

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: api-gateway-dr
  namespace: default
spec:
  host: app-stack-api-gateway.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: order-service-dr
  namespace: default
spec:
  host: app-stack-order-service.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: inventory-service-dr
  namespace: default
spec:
  host: app-stack-inventory-service.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: user-service-dr
  namespace: default
spec:
  host: app-stack-user-service.default.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        maxRequestsPerConnection: 2
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
```

---

### 2.3 NetworkPolicy 추가 (보안)

**파일:** `k8s/network-policies.yaml` (새로 생성)

```yaml
# API Gateway는 모든 인바운드 허용 (Ingress Gateway에서 오는 트래픽)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-gateway-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: api-gateway
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: istio-system
    ports:
    - protocol: TCP
      port: 8000
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: order-service
    ports:
    - protocol: TCP
      port: 8080
  - to:
    - podSelector:
        matchLabels:
          app: inventory-service
    ports:
    - protocol: TCP
      port: 3000
  - to:
    - podSelector:
        matchLabels:
          app: user-service
    ports:
    - protocol: TCP
      port: 8000
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
---
# Order Service는 API Gateway와 Inventory Service에서만 인바운드 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: order-service-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: order-service
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - protocol: TCP
      port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: inventory-service
    ports:
    - protocol: TCP
      port: 3000
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
---
# Inventory Service는 API Gateway와 Order Service에서만 인바운드 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: inventory-service-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: inventory-service
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - protocol: TCP
      port: 3000
  - from:
    - podSelector:
        matchLabels:
          app: order-service
    ports:
    - protocol: TCP
      port: 3000
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
---
# User Service는 API Gateway에서만 인바운드 허용
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: user-service-policy
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: user-service
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: api-gateway
    ports:
    - protocol: TCP
      port: 8000
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

---

### 2.4 PeerAuthentication 추가 (mTLS)

**파일:** `k8s/istio/peer-authentication.yaml` (새로 생성)

```yaml
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: default
spec:
  mtls:
    mode: STRICT
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: istio-system
  namespace: istio-system
spec:
  mtls:
    mode: PERMISSIVE
```

---

## 3. 검증 체크리스트

### 배포 전 확인 사항

- [ ] 모든 서비스가 올바른 포트에서 수신 중인지 확인
  ```bash
  kubectl get svc -n default
  ```

- [ ] Istio Ingress Gateway가 정상 작동하는지 확인
  ```bash
  kubectl get svc -n istio-system | grep ingress
  ```

- [ ] VirtualService가 올바르게 적용되었는지 확인
  ```bash
  kubectl get vs -n default
  ```

- [ ] 테스트 엔드포인트 확인
  ```bash
  # Frontend
  curl http://localhost/
  
  # API Gateway
  curl http://localhost/api/health
  
  # Order Service
  curl http://localhost/api/orders
  
  # User Service
  curl http://localhost/api/users
  
  # Inventory Service
  curl http://localhost/api/inventory
  ```

- [ ] 모니터링 도구 접근 확인
  ```bash
  curl http://localhost:9090/api/prometheus
  curl http://localhost/api/kiali
  curl http://localhost/api/grafana
  curl http://localhost/api/jaeger
  ```

---

## 4. 배포 순서

1. **Kind 클러스터 설정 수정**
   ```bash
   # k8s/kind-config.yaml 수정 후 클러스터 재생성
   kind delete cluster --name k8s-lab
   kind create cluster --config k8s/kind-config.yaml
   ```

2. **Istio 설정 적용**
   ```bash
   kubectl apply -f k8s/istio/gateway.yaml
   kubectl apply -f k8s/istio/virtual-services/app-vs.yaml
   kubectl delete -f k8s/istio/frontend-virtualservice.yaml  # 중복 제거
   kubectl apply -f k8s/istio/destination-rules.yaml
   kubectl apply -f k8s/istio/peer-authentication.yaml
   ```

3. **보안 정책 적용**
   ```bash
   kubectl apply -f k8s/network-policies.yaml
   ```

4. **애플리케이션 배포**
   ```bash
   helm install app-stack helm/umbrella-chart
   ```

5. **테스트 실행**
   ```bash
   bash scripts/07-test-api-endpoints.sh
   ```

---

## 5. 모니터링 및 디버깅

### Istio 라우팅 확인
```bash
# VirtualService 상태 확인
kubectl describe vs app-vs -n default

# DestinationRule 상태 확인
kubectl describe dr api-gateway-dr -n default

# Envoy 설정 확인
istioctl analyze
```

### 트래픽 흐름 추적
```bash
# Kiali 접근
http://localhost/api/kiali

# Jaeger 접근
http://localhost/api/jaeger

# Prometheus 접근
http://localhost/api/prometheus
```

### 로그 확인
```bash
# API Gateway 로그
kubectl logs -f deployment/app-stack-api-gateway

# Order Service 로그
kubectl logs -f deployment/app-stack-order-service

# Istio Ingress Gateway 로그
kubectl logs -f deployment/istio-ingressgateway -n istio-system
```

