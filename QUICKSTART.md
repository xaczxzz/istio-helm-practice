# 빠른 시작 가이드

이 가이드를 따라하면 5-10분 안에 전체 시스템을 구동할 수 있습니다.

## 사전 요구사항

다음 도구들이 설치되어 있어야 합니다:

```bash
# 필수 도구 확인
docker --version
kubectl version --client
helm version
kind --version
```

설치되지 않은 도구가 있다면 [SETUP.md](./SETUP.md)를 참고하세요.

## 1단계: 환경 설정 (2분)

```bash
# 1. 로컬 Docker Registry 생성
./scripts/01-setup-registry.sh

# 2. Kind 클러스터 생성
./scripts/02-setup-cluster.sh
```

## 2단계: 이미지 빌드 (3분)

```bash
# 모든 애플리케이션 이미지 빌드 및 푸시
./scripts/03-build-images.sh
```

## 3단계: 인프라 설치 (3-5분)

```bash
# Istio, ArgoCD, Prometheus, Grafana, Loki 설치
./scripts/04-install-infra.sh
```

## 4단계: 애플리케이션 배포 (2분)

```bash
# 3-tier 애플리케이션 배포
./scripts/05-deploy-apps.sh
```

## 5단계: 접속 확인

```bash
# 포트 포워딩 설정
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &

# 애플리케이션 접속 테스트
curl http://localhost:8080/api/health
```

브라우저에서 http://localhost:8080 접속하여 Frontend 확인

## 6단계: 모니터링 도구 접속

```bash
# Grafana (별도 터미널)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Kiali (별도 터미널)
kubectl port-forward -n istio-system svc/kiali 20001:20001 &

# Jaeger (별도 터미널)
kubectl port-forward -n istio-system svc/tracing 16686:16686 &
```

접속 URL:
- **Frontend**: http://localhost:8080
- **Grafana**: http://localhost:3000 (admin/admin123)
- **Kiali**: http://localhost:20001
- **Jaeger**: http://localhost:16686

## 7단계: 부하 테스트 (선택사항)

```bash
# k6 설치 (macOS)
brew install k6

# 기본 부하 테스트 실행
./scripts/run-load-test.sh --scenario basic --url http://localhost:8080
```

## 정리

```bash
# 모든 리소스 정리
./scripts/cleanup.sh
```

## 문제 해결

### 애플리케이션이 접속되지 않는 경우

```bash
# Pod 상태 확인
kubectl get pods

# 서비스 확인
kubectl get svc

# Istio Gateway 확인
kubectl get gateway,virtualservice
```

### 이미지 Pull 실패

```bash
# Registry 상태 확인
docker ps | grep kind-registry

# Registry 재시작
docker restart kind-registry
```

### 더 자세한 정보

- [상세 설치 가이드](./SETUP.md)
- [프로젝트 개요](./PROJECT_OVERVIEW.md)
- [README](./README.md)

## 다음 단계

1. **배포 전략 실습**: Rolling Update, Canary, Blue/Green 배포 테스트
2. **모니터링 활용**: Grafana 대시보드에서 Golden Signals 확인
3. **트레이싱 분석**: Jaeger에서 분산 트레이싱 확인
4. **Service Mesh**: Kiali에서 서비스 토폴로지 확인
5. **부하 테스트**: 다양한 시나리오로 시스템 성능 테스트

즐거운 Kubernetes 학습 되세요! 🚀