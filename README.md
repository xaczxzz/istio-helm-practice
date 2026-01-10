# K8s 3-Tier Observability Lab

Kubernetes 학습을 위한 완전한 3-tier 애플리케이션과 observability 스택 프로젝트입니다.

## 📋 프로젝트 개요

이 프로젝트는 다음을 학습하고 실습하기 위한 종합 환경을 제공합니다:

- **Kubernetes 기본**: Kind 클러스터, 멀티 노드 구성
- **Service Mesh**: Istio를 통한 트래픽 관리, mTLS, 관찰성
- **배포 전략**: Rolling Update, Canary, Blue/Green 배포
- **GitOps**: ArgoCD를 통한 선언적 배포
- **Observability**: Prometheus, Grafana, Jaeger, Kiali, Loki
- **Helm**: Umbrella Chart 패턴, 차트 관리

## 🏗️ 아키텍처

### 애플리케이션 구조

```
┌─────────────┐
│  Frontend   │ (Nginx + Vanilla JS - 트래픽 시각화)
└──────┬──────┘
       │
┌──────▼──────┐
│ API Gateway │ (Python FastAPI)
└──────┬──────┘
       │
   ┌───┴───────────┬────────────┐
   │               │            │
┌──▼─────────┐ ┌──▼──────────┐ ┌▼───────────┐
│   Order    │ │  Inventory  │ │    User    │
│  Service   │ │   Service   │ │  Service   │
│ (Go/Gin)   │ │ (Node.js)   │ │ (FastAPI)  │
└──────┬─────┘ └──────┬──────┘ └─────┬──────┘
       │              │               │
       └──────────────┼───────────────┘
                      │
              ┌───────▼────────┐
              │   PostgreSQL   │
              │ (서비스별 스키마) │
              └────────────────┘
```

### 인프라 스택

- **Kubernetes**: Kind (1 Control Plane + 2 Worker Nodes)
- **Service Mesh**: Istio (트래픽 관리, mTLS, 관찰성)
- **GitOps**: ArgoCD (애플리케이션 배포 관리)
- **Monitoring**: 
  - Prometheus (메트릭 수집)
  - Grafana (시각화)
  - Jaeger (분산 트레이싱)
  - Kiali (Service Mesh 시각화)
- **Logging**: Grafana Alloy → Loki
- **Load Testing**: k6

## 🎯 주요 기능

### 1. 트래픽 시각화 Frontend
- 실시간 Pod 라우팅 확인 (클릭 시 pod-1, pod-2 표시)
- 카나리/블루그린 배포 시 트래픽 분배 시각화
- 응답 시간 및 에러율 표시

### 2. 배포 전략 데모
- **Rolling Update**: Order Service v1 → v2 점진적 업데이트
- **Canary**: Inventory Service (90% stable, 10% canary)
- **Blue/Green**: User Service 전체 전환

### 3. Istio 트래픽 관리
- VirtualService를 통한 라우팅 제어
- DestinationRule을 통한 subset 관리
- Circuit Breaking 및 Retry 정책
- mTLS 보안

### 4. Golden Signals 모니터링
- **Latency**: 응답 시간 분포 및 백분위수
- **Traffic**: 초당 요청 수 (RPS)
- **Errors**: 에러율 및 HTTP 상태 코드 분포
- **Saturation**: CPU, 메모리, 네트워크 사용률

## 📦 기술 스택

### 애플리케이션
| 서비스 | 언어/프레임워크 | 목적 |
|--------|----------------|------|
| Frontend | Nginx + Vanilla JS | 사용자 인터페이스 및 트래픽 시각화 |
| API Gateway | Python FastAPI | 단일 진입점, 라우팅 |
| Order Service | Go (Gin) | 주문 처리 로직 |
| Inventory Service | Node.js (Express) | 재고 관리 |
| User Service | Python FastAPI | 사용자 관리 |
| Database | PostgreSQL | 데이터 저장 (서비스별 스키마) |

### 인프라
- **Container Runtime**: Docker
- **Orchestration**: Kubernetes (Kind)
- **Service Mesh**: Istio
- **Package Manager**: Helm
- **GitOps**: ArgoCD
- **Monitoring**: Prometheus, Grafana, Jaeger, Kiali
- **Logging**: Grafana Alloy, Loki
- **Load Testing**: k6
- **Container Registry**: Local Docker Registry (localhost:5002)

## 🚀 빠른 시작

### 사전 요구사항
- Docker Desktop
- kubectl
- Helm 3
- Kind
- Git

### 설치 순서

```bash
# 1. 저장소 클론
git clone <repository-url>
cd k8s-3tier-observability

# 2. 로컬 레지스트리 생성
./scripts/01-setup-registry.sh

# 3. Kind 클러스터 생성
./scripts/02-setup-cluster.sh

# 4. 애플리케이션 이미지 빌드 및 푸시
./scripts/03-build-images.sh

# 5. 인프라 설치 (Istio, ArgoCD, Prometheus, Grafana, Loki)
./scripts/04-install-infra.sh

# 6. 애플리케이션 배포
./scripts/05-deploy-apps.sh

# 7. 부하 테스트 실행 (선택사항)
./scripts/run-load-test.sh
```

## 🔍 접속 정보

배포 완료 후 다음 URL로 접속할 수 있습니다:

```bash
# 애플리케이션
Frontend:        http://localhost
API Gateway:     http://localhost/api

# 모니터링 도구
Grafana:         http://localhost/grafana
  - Username: admin
  - Password: (스크립트에서 출력)

Kiali:           http://localhost/kiali
Jaeger:          http://localhost/jaeger
Prometheus:      http://localhost/prometheus

# GitOps
ArgoCD:          http://localhost/argocd
  - Username: admin
  - Password: (스크립트에서 출력)
```

## 📚 학습 가이드

### 1. 배포 전략 실습

#### Rolling Update
```bash
# Order Service v2로 업데이트
kubectl set image deployment/order-service \
  order-service=localhost:5002/order-service:v2

# 롤아웃 상태 확인
kubectl rollout status deployment/order-service

# Frontend에서 트래픽 분배 확인
```

#### Canary 배포
```bash
# Canary 배포 활성화
helm upgrade app-stack ./helm/umbrella-chart \
  -f ./helm/umbrella-chart/values-canary.yaml

# Kiali에서 트래픽 분배 확인 (90% stable, 10% canary)
```

#### Blue/Green 배포
```bash
# Green 버전 배포
helm upgrade app-stack ./helm/umbrella-chart \
  -f ./helm/umbrella-chart/values-bluegreen.yaml

# VirtualService 업데이트하여 트래픽 전환
kubectl apply -f k8s/user-service-vs-green.yaml
```

### 2. Observability 실습

#### Jaeger를 통한 분산 트레이싱
1. Frontend에서 주문 생성 요청
2. Jaeger UI에서 trace 확인
3. API Gateway → Order → Inventory → User 흐름 분석

#### Kiali로 Service Mesh 시각화
1. Kiali Graph 탭 접속
2. Versioned app graph 선택
3. 트래픽 흐름 및 에러율 확인

#### Grafana 대시보드
- **Golden Signals Dashboard**: 전체 서비스 건강 상태
- **Istio Service Dashboard**: Service Mesh 메트릭
- **Application Metrics**: 각 서비스별 상세 메트릭

#### Loki로 로그 검색
```logql
# 특정 서비스 로그
{app="order-service"}

# 에러 로그만
{app="order-service"} |= "error"

# 특정 시간대 로그
{app="order-service"} |= "error" | json | latency > 1000
```

### 3. Istio 트래픽 관리 실습

#### Circuit Breaking
```bash
# Circuit Breaker 설정 적용
kubectl apply -f k8s/istio/circuit-breaker.yaml

# 부하 테스트로 Circuit Breaker 동작 확인
./scripts/run-load-test.sh --scenario circuit-breaker
```

#### Retry 정책
```bash
# Retry 정책 적용
kubectl apply -f k8s/istio/retry-policy.yaml

# 일부 Pod 중단 후 동작 확인
kubectl scale deployment inventory-service --replicas=1
```

#### Timeout 설정
```bash
# Timeout 설정 적용
kubectl apply -f k8s/istio/timeout-policy.yaml

# 느린 응답 시뮬레이션
curl http://localhost/api/inventory?delay=5000
```

## 📊 모니터링 메트릭

### Golden Signals

**Latency (지연 시간)**
- P50, P95, P99 응답 시간
- 서비스별 평균 응답 시간
- 엔드포인트별 응답 시간 분포

**Traffic (트래픽)**
- RPS (Requests Per Second)
- 서비스별 요청 수
- HTTP 메서드별 분포

**Errors (에러)**
- 전체 에러율 (%)
- HTTP 상태 코드 분포 (4xx, 5xx)
- 서비스별 에러 수

**Saturation (포화도)**
- CPU 사용률
- 메모리 사용률
- 네트워크 I/O
- Pod 개수 및 상태

### Istio 메트릭
- Request Volume (요청량)
- Success Rate (성공률)
- Request Duration (요청 시간)
- Bytes In/Out (네트워크 트래픽)

## 🛠️ 트러블슈팅

### 이미지 Pull 실패
```bash
# 레지스트리 연결 확인
docker exec -it kind-registry registry --version

# Kind 노드에서 레지스트리 접근 확인
docker exec -it kind-worker crictl pull localhost:5002/frontend:latest
```

### Istio Sidecar 미주입
```bash
# 네임스페이스에 Istio 자동 주입 활성화
kubectl label namespace default istio-injection=enabled

# Pod 재시작
kubectl rollout restart deployment <deployment-name>
```

### ArgoCD 동기화 실패
```bash
# ArgoCD Application 상태 확인
kubectl get applications -n argocd

# 동기화 재시도
argocd app sync <app-name>
```

## 📖 추가 문서

- [상세 설치 가이드](./docs/SETUP.md)
- [배포 전략 가이드](./docs/DEPLOYMENT_STRATEGIES.md)
- [모니터링 가이드](./docs/MONITORING.md)

## 🤝 기여

이슈 및 풀 리퀘스트를 환영합니다!

## 📝 라이선스

MIT License

## 🙏 참고 자료

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Istio Documentation](https://istio.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
