# Monitoring Stack

이 Helm 차트는 Jaeger와 Kiali를 포함한 모니터링 스택을 관리합니다.

## 구성 요소

### Jaeger
- **분산 트레이싱** 시스템
- All-in-One 모드로 배포
- 메모리 스토리지 사용 (개발/테스트용)

### Kiali
- **Service Mesh 시각화** 도구
- Istio 서비스 메시 관찰성
- 익명 인증 모드

## 설정

### values.yaml 주요 설정

```yaml
jaeger:
  enabled: true
  allInOne:
    enabled: true
    image: jaegertracing/all-in-one:1.76

kiali:
  enabled: true
  auth:
    strategy: anonymous
  server:
    web_root: /monitoring/kiali
```

## 접근 방법

### 직접 접근 (포트 포워딩)
```bash
# Jaeger
kubectl port-forward -n istio-system svc/jaeger-query 16686:16686

# Kiali  
kubectl port-forward -n istio-system svc/kiali 20001:20001
```

### Istio Gateway를 통한 접근
- **Jaeger**: http://localhost/monitoring/jaeger/
- **Kiali**: http://localhost/monitoring/kiali/

## ArgoCD 배포

이 차트는 ArgoCD 애플리케이션으로 관리됩니다:

```yaml
# argocd/applications/02-monitoring.yaml
source:
  repoURL: https://github.com/xaczxzz/istio-helm-practice.git
  path: helm/monitoring
```

## 의존성 관리

```bash
# 의존성 업데이트
helm dependency update helm/monitoring

# 로컬 테스트
helm template monitoring helm/monitoring
```