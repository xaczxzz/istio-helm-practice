# 프로젝트 개요 및 요구사항 정리

## 프로젝트 목적

Kubernetes 학습을 위한 실전형 3-tier 애플리케이션 및 완전한 Observability 스택 구축 프로젝트

## 핵심 요구사항 정리

### 1. 인프라 구성

#### Kubernetes 클러스터
- **플랫폼**: Kind (Kubernetes in Docker)
- **노드 구성**:
  - Control Plane: 1개
  - Worker Node: 2개
- **네트워크**:
  - Ingress Controller: Istio Ingress Gateway
  - 로컬 포트: 80, 443, 5002 (registry)

#### Container Registry
- **유형**: Local Docker Registry
- **포트**: 5002
- **용도**: 로컬 이미지 저장 및 Kind 클러스터 배포

### 2. 애플리케이션 아키텍처

#### 3-Tier 구조

**Tier 1: Frontend**
- **기술**: Nginx + Vanilla JavaScript
- **주요 기능**:
  - 백엔드 API 호출 버튼 인터페이스
  - Pod 라우팅 시각화 (pod-1, pod-2 등)
  - 카나리/롤링 업데이트 시 트래픽 분배 시각화
  - 실시간 응답 시간 및 에러율 표시
- **Replica**: 2개

**Tier 2: Backend Services**
- **API Gateway** (Python FastAPI)
  - 모든 요청의 단일 진입점
  - 백엔드 서비스로 라우팅
  - Replica: 2개

- **Order Service** (Go - Gin Framework)
  - 주문 처리 로직
  - Inventory Service와 통신
  - PostgreSQL 연결 (order 스키마)
  - Replica: 3개 (Rolling Update 데모용)

- **Inventory Service** (Node.js - Express)
  - 재고 관리 로직
  - PostgreSQL 연결 (inventory 스키마)
  - Replica: 2개 (Canary 배포 데모용)

- **User Service** (Python FastAPI)
  - 사용자 관리 로직
  - PostgreSQL 연결 (user 스키마)
  - Replica: 2개 (Blue/Green 배포 데모용)

**Tier 3: Database**
- **유형**: PostgreSQL
- **구성**: 단일 인스턴스, 서비스별 스키마 분리
  - `order_db` 스키마: Order Service 전용
  - `inventory_db` 스키마: Inventory Service 전용
  - `user_db` 스키마: User Service 전용
- **영속성**: 개발 환경이므로 비활성화 가능

#### 서비스 간 통신 흐름

```
User → Frontend → API Gateway → Order Service → Inventory Service
                              ↓                        ↓
                         User Service              PostgreSQL
                              ↓
                         PostgreSQL
```

**통신 특징**:
- 모든 서비스 간 통신은 Istio Service Mesh를 통해 이루어짐
- mTLS로 암호화
- Jaeger를 통한 분산 트레이싱 가능
- Kiali를 통한 시각화 가능

### 3. Service Mesh

#### Istio 구성
- **버전**: 1.20+ (최신 stable)
- **프로파일**: demo (학습용)
- **주요 기능**:
  - Traffic Management (VirtualService, DestinationRule)
  - Security (mTLS)
  - Observability (Metrics, Traces, Logs)

#### Istio 애드온
- **Kiali**: Service Mesh 토폴로지 시각화
- **Jaeger**: 분산 트레이싱
- **Prometheus**: Istio 메트릭 수집 (kube-prometheus-stack과 통합)

### 4. GitOps

#### ArgoCD
- **용도**: Kubernetes 애플리케이션 배포 자동화
- **배포 방식**: 
  - Git 저장소를 Single Source of Truth로 사용
  - Helm Chart 기반 배포
  - 자동 동기화 및 Self-Healing 활성화

#### Helm Chart 구조
- **패턴**: Umbrella Chart
- **구성**:
  ```
  umbrella-chart/
  ├── Chart.yaml
  ├── values.yaml
  ├── values-canary.yaml      # Canary 배포용
  ├── values-bluegreen.yaml   # Blue/Green 배포용
  └── charts/
      ├── frontend/
      ├── api-gateway/
      ├── order-service/
      ├── inventory-service/
      ├── user-service/
      └── postgresql/
  ```

### 5. Observability Stack

#### 메트릭 수집 및 시각화

**Prometheus**
- **배포**: kube-prometheus-stack Helm Chart
- **수집 대상**:
  - Kubernetes 클러스터 메트릭
  - Node 메트릭
  - Pod 메트릭
  - Istio 메트릭
  - 애플리케이션 custom 메트릭

**Grafana**
- **용도**: 메트릭 시각화
- **주요 대시보드**:
  1. **Golden Signals Dashboard**
     - Latency: P50, P95, P99 응답 시간
     - Traffic: RPS (Requests Per Second)
     - Errors: 에러율 및 HTTP 상태 코드 분포
     - Saturation: CPU, 메모리, 네트워크 사용률
  
  2. **Istio Service Mesh Dashboard**
     - Request Volume
     - Success Rate
     - Request Duration
     - Bytes In/Out
     - Service-to-Service 통신 현황
  
  3. **Application Metrics Dashboard**
     - 서비스별 상세 메트릭
     - Database 연결 풀 상태
     - 비즈니스 메트릭 (주문 수, 재고 변경 등)

#### 분산 트레이싱

**Jaeger**
- **통합**: Istio와 자동 통합
- **추적 범위**:
  - Frontend → API Gateway
  - API Gateway → Order Service
  - Order Service → Inventory Service
  - 모든 서비스 → PostgreSQL
- **활용**:
  - 요청 경로 추적
  - 지연 시간 분석
  - 병목 구간 식별

**Kiali**
- **기능**: Service Mesh 시각화
- **주요 뷰**:
  - Graph View: 서비스 토폴로지 및 트래픽 흐름
  - Versioned App Graph: 버전별 트래픽 분배 확인
  - Workload View: Pod 상태 및 메트릭
  - Istio Config: VirtualService, DestinationRule 설정 확인

#### 로그 수집

**Loki Stack**
- **구성**: Grafana Alloy → Loki
- **Alloy (OpenTelemetry Collector)**:
  - 모든 Pod의 로그 수집
  - 메타데이터 enrichment (namespace, pod, container)
  - Loki로 전송
- **Loki**:
  - 로그 저장 및 인덱싱
  - LogQL을 통한 쿼리
  - Grafana와 통합

**로그 쿼리 예시**:
```logql
# 특정 서비스의 에러 로그
{app="order-service"} |= "error"

# 느린 요청 필터링
{app="api-gateway"} | json | latency > 1000

# 특정 사용자의 요청 추적
{app="user-service"} |= "user_id=12345"
```

### 6. 배포 전략

#### Rolling Update (Order Service)
- **대상**: Order Service v1 → v2
- **설정**:
  ```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  ```
- **시각화**: Frontend에서 실시간 Pod 전환 확인

#### Canary Deployment (Inventory Service)
- **대상**: Inventory Service v1 (90%) + v2 (10%)
- **Istio 설정**:
  ```yaml
  apiVersion: networking.istio.io/v1beta1
  kind: VirtualService
  spec:
    http:
    - match:
      - headers:
          canary:
            exact: "true"
      route:
      - destination:
          host: inventory-service
          subset: v2
        weight: 10
      - destination:
          host: inventory-service
          subset: v1
        weight: 90
  ```
- **검증**: Kiali Graph에서 트래픽 분배 확인

#### Blue/Green Deployment (User Service)
- **대상**: User Service Blue → Green 전환
- **방식**:
  1. Green 버전 배포 (새로운 Deployment)
  2. 테스트 완료 후 VirtualService 업데이트
  3. 트래픽 100% Green으로 전환
  4. Blue 버전 제거
- **Istio 설정**:
  ```yaml
  apiVersion: networking.istio.io/v1beta1
  kind: VirtualService
  spec:
    http:
    - route:
      - destination:
          host: user-service
          subset: green
        weight: 100
  ```

### 7. 부하 테스트

#### k6
- **시나리오**:
  1. **기본 부하**: 일정한 RPS로 모든 엔드포인트 호출
  2. **점진적 증가**: VU 점진적 증가 (Ramp-up)
  3. **스파이크**: 갑작스런 트래픽 증가
  4. **Circuit Breaker 테스트**: 특정 서비스 부하로 차단 동작 확인

**예시 스크립트**:
```javascript
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '30s', target: 10 },  // 10 VU로 증가
    { duration: '1m', target: 10 },   // 1분간 유지
    { duration: '30s', target: 50 },  // 50 VU로 증가
    { duration: '1m', target: 50 },   // 1분간 유지
    { duration: '30s', target: 0 },   // 감소
  ],
};

export default function() {
  // Order 생성
  let orderRes = http.post('http://localhost/api/orders', JSON.stringify({
    user_id: 1,
    product_id: 100,
    quantity: 1
  }), {
    headers: { 'Content-Type': 'application/json' },
  });
  
  check(orderRes, {
    'order created': (r) => r.status === 201,
  });
  
  sleep(1);
}
```

### 8. 프로젝트 디렉토리 구조

```
k8s-3tier-observability/
├── README.md                          # 프로젝트 소개
├── docs/
│   ├── SETUP.md                       # 설치 가이드
│   ├── DEPLOYMENT_STRATEGIES.md       # 배포 전략 상세 가이드
│   ├── MONITORING.md                  # 모니터링 활용 가이드
│   └── PROJECT_OVERVIEW.md            # 본 문서
│
├── apps/                              # 애플리케이션 소스 코드
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── nginx.conf
│   │   ├── index.html
│   │   └── app.js
│   ├── api-gateway/
│   │   ├── Dockerfile.v1
│   │   ├── Dockerfile.v2
│   │   ├── main.py
│   │   ├── requirements.txt
│   │   └── config.py
│   ├── order-service/
│   │   ├── Dockerfile.v1
│   │   ├── Dockerfile.v2
│   │   ├── main.go
│   │   ├── handlers/
│   │   └── models/
│   ├── inventory-service/
│   │   ├── Dockerfile.v1
│   │   ├── Dockerfile.v2
│   │   ├── server.js
│   │   ├── routes/
│   │   └── models/
│   ├── user-service/
│   │   ├── Dockerfile.v1
│   │   ├── Dockerfile.v2
│   │   ├── main.py
│   │   └── requirements.txt
│   └── load-test/
│       ├── basic-load.js
│       ├── ramp-up.js
│       ├── spike.js
│       └── circuit-breaker.js
│
├── k8s/                               # Kubernetes 매니페스트
│   ├── kind-config.yaml
│   ├── istio/
│   │   ├── gateway.yaml
│   │   ├── virtual-services/
│   │   ├── destination-rules/
│   │   ├── circuit-breaker.yaml
│   │   ├── retry-policy.yaml
│   │   └── timeout-policy.yaml
│   └── postgresql/
│       ├── init-scripts/
│       │   ├── 01-create-schemas.sql
│       │   ├── 02-order-schema.sql
│       │   ├── 03-inventory-schema.sql
│       │   └── 04-user-schema.sql
│       └── configmap.yaml
│
├── helm/                              # Helm Charts
│   ├── umbrella-chart/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values-canary.yaml
│   │   ├── values-bluegreen.yaml
│   │   ├── templates/
│   │   └── charts/
│   │       ├── frontend/
│   │       │   ├── Chart.yaml
│   │       │   ├── values.yaml
│   │       │   └── templates/
│   │       ├── api-gateway/
│   │       ├── order-service/
│   │       ├── inventory-service/
│   │       ├── user-service/
│   │       └── postgresql/
│   └── infra/
│       ├── istio/
│       │   └── values.yaml
│       ├── argocd/
│       │   └── values.yaml
│       ├── kube-prometheus-stack/
│       │   ├── values.yaml
│       │   └── istio-servicemonitor.yaml
│       └── loki-stack/
│           ├── values.yaml
│           ├── alloy-configmap.yaml
│           └── alloy-deployment.yaml
│
├── argocd/                            # ArgoCD Applications
│   ├── app-of-apps.yaml
│   └── applications/
│       ├── app-umbrella.yaml
│       ├── monitoring.yaml
│       └── istio.yaml
│
├── grafana/                           # Grafana Dashboards
│   └── dashboards/
│       ├── golden-signals.json
│       ├── istio-service-mesh.json
│       ├── application-metrics.json
│       └── loki-logs.json
│
└── scripts/                           # 자동화 스크립트
    ├── 01-setup-registry.sh
    ├── 02-setup-cluster.sh
    ├── 03-build-images.sh
    ├── 04-install-infra.sh
    ├── 05-deploy-apps.sh
    ├── run-load-test.sh
    ├── cleanup.sh
    └── utils/
        ├── check-health.sh
        └── get-credentials.sh
```

## 학습 목표

이 프로젝트를 완료하면 다음을 학습할 수 있습니다:

### Kubernetes 핵심 개념
- [ ] Pod, Deployment, Service, ConfigMap, Secret
- [ ] Namespace 격리
- [ ] Resource Limits 및 Requests
- [ ] Health Checks (Liveness, Readiness Probe)
- [ ] Multi-container Pods (Sidecar 패턴)

### Service Mesh (Istio)
- [ ] Service Mesh 아키텍처 이해
- [ ] Traffic Management (VirtualService, DestinationRule)
- [ ] Security (mTLS, Authorization Policy)
- [ ] Observability (Metrics, Traces, Logs)
- [ ] Resilience (Circuit Breaking, Retry, Timeout)

### GitOps (ArgoCD)
- [ ] GitOps 철학 이해
- [ ] Application 리소스 관리
- [ ] 자동 동기화 및 Self-Healing
- [ ] App of Apps 패턴

### Helm
- [ ] Chart 구조 이해
- [ ] Values 파일 관리
- [ ] Umbrella Chart 패턴
- [ ] Chart Dependencies

### Observability
- [ ] Metrics 수집 및 쿼리 (PromQL)
- [ ] Distributed Tracing 분석
- [ ] Log Aggregation 및 검색 (LogQL)
- [ ] Dashboard 구성 및 Alert 설정
- [ ] Golden Signals 모니터링

### 배포 전략
- [ ] Rolling Update 이해 및 실습
- [ ] Canary Deployment 구현
- [ ] Blue/Green Deployment 구현
- [ ] 각 전략의 장단점 이해

### Container & Registry
- [ ] Dockerfile 작성
- [ ] Multi-stage Build
- [ ] Local Registry 운영
- [ ] 이미지 태깅 전략

### 네트워킹
- [ ] Kubernetes Service Types
- [ ] Ingress 설정
- [ ] Service Mesh Routing
- [ ] DNS 이해

## 확장 가능성

이 프로젝트를 기반으로 다음과 같은 확장이 가능합니다:

### 고급 기능 추가
1. **Horizontal Pod Autoscaler (HPA)**
   - CPU/메모리 기반 자동 스케일링
   - Custom Metrics 기반 스케일링

2. **Vertical Pod Autoscaler (VPA)**
   - Resource Requests 자동 조정

3. **Cluster Autoscaler**
   - 노드 수준 자동 스케일링 (클라우드 환경)

4. **Advanced Istio Features**
   - Rate Limiting
   - Authorization Policies
   - External Authorization (OPA)

5. **Security**
   - Pod Security Standards
   - Network Policies
   - Secret Management (Vault)

6. **CI/CD**
   - GitHub Actions 통합
   - 자동 이미지 빌드
   - 자동 배포 파이프라인

7. **Advanced Monitoring**
   - SLO/SLI 정의 및 모니터링
   - Alert Manager 규칙
   - PagerDuty/Slack 통합

8. **Chaos Engineering**
   - Chaos Mesh 도입
   - Failure Injection 테스트

### 다른 환경으로 확장
1. **클라우드 환경**
   - AWS EKS, GKE, AKS로 마이그레이션
   - Cloud Load Balancer 사용
   - Managed Services 활용

2. **멀티 클러스터**
   - Istio Multi-cluster Setup
   - ArgoCD ApplicationSet

3. **프로덕션 준비**
   - High Availability 구성
   - Backup & Restore
   - Disaster Recovery

## 예상 리소스 사용량

### 로컬 개발 환경
- **CPU**: 4-6 cores
- **Memory**: 8-12 GB
- **Disk**: 20-30 GB

### Pod 리소스 예상치
| 컴포넌트 | CPU Request | Memory Request | CPU Limit | Memory Limit | Replicas |
|---------|-------------|----------------|-----------|--------------|----------|
| Frontend | 50m | 64Mi | 200m | 128Mi | 2 |
| API Gateway | 100m | 128Mi | 500m | 256Mi | 2 |
| Order Service | 100m | 128Mi | 500m | 256Mi | 3 |
| Inventory Service | 100m | 128Mi | 500m | 256Mi | 2 |
| User Service | 100m | 128Mi | 500m | 256Mi | 2 |
| PostgreSQL | 250m | 256Mi | 1000m | 512Mi | 1 |
| Prometheus | 500m | 1Gi | 2000m | 2Gi | 1 |
| Grafana | 100m | 128Mi | 500m | 256Mi | 1 |
| Loki | 250m | 256Mi | 1000m | 512Mi | 1 |
| Jaeger | 200m | 256Mi | 1000m | 512Mi | 1 |
| Kiali | 100m | 128Mi | 500m | 256Mi | 1 |

**총 예상 리소스**:
- CPU Request: ~2.5 cores
- Memory Request: ~3.5 GB
- CPU Limit: ~10 cores
- Memory Limit: ~6 GB

## 참고 자료

### 공식 문서
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Istio Documentation](https://istio.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Helm Documentation](https://helm.sh/docs/)

### 학습 자료
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way)
- [Istio in Action](https://www.manning.com/books/istio-in-action)
- [GitOps Principles](https://opengitops.dev/)

### 커뮤니티
- [Kubernetes Slack](https://slack.k8s.io/)
- [Istio Discuss](https://discuss.istio.io/)
- [CNCF Slack](https://slack.cncf.io/)

## 버전 정보

- **Kubernetes**: 1.28+
- **Kind**: 0.20+
- **Istio**: 1.20+
- **ArgoCD**: 2.9+
- **Prometheus Operator**: 0.70+
- **Grafana**: 10.0+
- **Loki**: 2.9+
- **Helm**: 3.12+

## 라이선스

MIT License

---

**작성일**: 2026-01-10
**최종 업데이트**: 2026-01-10
**버전**: 1.0.0
