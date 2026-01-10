# 설치 가이드

이 문서는 K8s 3-Tier Observability Lab의 상세 설치 과정을 안내합니다.

## 목차

1. [사전 요구사항](#사전-요구사항)
2. [환경 준비](#환경-준비)
3. [단계별 설치](#단계별-설치)
4. [설치 검증](#설치-검증)
5. [문제 해결](#문제-해결)

## 사전 요구사항

### 필수 도구

| 도구 | 버전 | 설치 확인 |
|------|------|----------|
| Docker Desktop | 24.0+ | `docker --version` |
| kubectl | 1.28+ | `kubectl version --client` |
| Helm | 3.12+ | `helm version` |
| Kind | 0.20+ | `kind --version` |
| Git | 2.0+ | `git --version` |

### 시스템 요구사항

- **OS**: macOS, Linux, Windows (WSL2)
- **CPU**: 4 cores 이상 권장
- **RAM**: 8GB 이상 권장
- **Disk**: 20GB 이상 여유 공간

### 도구 설치

#### macOS (Homebrew)
```bash
# Docker Desktop은 공식 웹사이트에서 설치
# https://www.docker.com/products/docker-desktop

# CLI 도구 설치
brew install kubectl helm kind git
```

#### Linux (Ubuntu/Debian)
```bash
# Docker 설치
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Helm 설치
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Kind 설치
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Git 설치
sudo apt-get update
sudo apt-get install -y git
```

#### Windows (WSL2)
```powershell
# WSL2 및 Ubuntu 설치 후 Linux 설치 과정 따르기
wsl --install -d Ubuntu

# Docker Desktop for Windows 설치 (WSL2 백엔드 활성화)
```

## 환경 준비

### 1. 저장소 클론

```bash
git clone https://github.com/your-username/k8s-3tier-observability.git
cd k8s-3tier-observability
```

### 2. 환경 변수 설정 (선택사항)

```bash
# .env 파일 생성
cat > .env << EOF
# Registry
REGISTRY_PORT=5002
REGISTRY_NAME=kind-registry

# Kind Cluster
CLUSTER_NAME=k8s-lab
WORKER_NODES=2

# Application
APP_NAMESPACE=default
APP_VERSION=v1

# Monitoring
MONITORING_NAMESPACE=monitoring
EOF

# 환경 변수 로드
source .env
```

## 단계별 설치

### Step 1: 로컬 Docker Registry 생성

```bash
./scripts/01-setup-registry.sh
```

**이 스크립트가 수행하는 작업:**
- Docker Registry 컨테이너 생성 (포트 5002)
- Kind 네트워크에 연결
- Registry 동작 확인

**확인:**
```bash
# Registry 컨테이너 확인
docker ps | grep kind-registry

# Registry API 테스트
curl http://localhost:5002/v2/_catalog
# 예상 출력: {"repositories":[]}
```

**스크립트 내용 상세:**
```bash
#!/bin/bash
set -e

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5002"

echo "🚀 Setting up local Docker registry..."

# 기존 레지스트리 제거
if [ "$(docker ps -aq -f name=${REGISTRY_NAME})" ]; then
    echo "Removing existing registry..."
    docker rm -f ${REGISTRY_NAME}
fi

# 레지스트리 생성
echo "Creating registry container..."
docker run -d \
  --restart=always \
  --name ${REGISTRY_NAME} \
  -p ${REGISTRY_PORT}:5000 \
  registry:2

# Kind 네트워크에 연결 (이미 존재하는 경우 무시)
if [ "$(docker network ls -q -f name=kind)" ]; then
    echo "Connecting registry to kind network..."
    docker network connect kind ${REGISTRY_NAME} 2>/dev/null || true
fi

# 레지스트리 동작 확인
echo "Verifying registry..."
sleep 2
curl -f http://localhost:${REGISTRY_PORT}/v2/_catalog || {
    echo "❌ Registry verification failed"
    exit 1
}

echo "✅ Local registry is ready at localhost:${REGISTRY_PORT}"
```

### Step 2: Kind 클러스터 생성

```bash
./scripts/02-setup-cluster.sh
```

**이 스크립트가 수행하는 작업:**
- Kind 클러스터 생성 (1 Control Plane + 2 Workers)
- 로컬 레지스트리와 연결
- Ingress용 포트 매핑 설정

**확인:**
```bash
# 클러스터 확인
kind get clusters
# 예상 출력: k8s-lab

# 노드 확인
kubectl get nodes
# 예상 출력:
# NAME                    STATUS   ROLES           AGE   VERSION
# k8s-lab-control-plane   Ready    control-plane   1m    v1.27.0
# k8s-lab-worker          Ready    <none>          1m    v1.27.0
# k8s-lab-worker2         Ready    <none>          1m    v1.27.0

# 컨텍스트 확인
kubectl config current-context
# 예상 출력: kind-k8s-lab
```

**Kind 설정 파일 (k8s/kind-config.yaml):**
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: k8s-lab
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  # HTTP
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  # HTTPS
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  # Istio Ingress Gateway
  - containerPort: 15021
    hostPort: 15021
    protocol: TCP
- role: worker
  labels:
    zone: zone-a
- role: worker
  labels:
    zone: zone-b
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5002"]
        endpoint = ["http://kind-registry:5002"]
```

### Step 3: 애플리케이션 이미지 빌드 및 푸시

```bash
./scripts/03-build-images.sh
```

**이 스크립트가 수행하는 작업:**
- 모든 애플리케이션 Dockerfile 빌드
- 이미지 태깅 (v1, v2, latest)
- 로컬 레지스트리에 푸시

**확인:**
```bash
# 레지스트리에 푸시된 이미지 확인
curl http://localhost:5002/v2/_catalog
# 예상 출력:
# {
#   "repositories": [
#     "frontend",
#     "api-gateway",
#     "order-service",
#     "inventory-service",
#     "user-service"
#   ]
# }

# 특정 이미지 태그 확인
curl http://localhost:5002/v2/order-service/tags/list
# 예상 출력: {"name":"order-service","tags":["latest","v1","v2"]}
```

**빌드 프로세스:**
```bash
#!/bin/bash
set -e

REGISTRY="localhost:5002"
SERVICES=("frontend" "api-gateway" "order-service" "inventory-service" "user-service")
VERSIONS=("v1" "v2")

echo "🏗️  Building application images..."

for service in "${SERVICES[@]}"; do
    echo "Building ${service}..."
    
    for version in "${VERSIONS[@]}"; do
        # v1, v2 각각 빌드
        docker build \
            -t ${REGISTRY}/${service}:${version} \
            -f apps/${service}/Dockerfile.${version} \
            apps/${service}/
        
        docker push ${REGISTRY}/${service}:${version}
    done
    
    # latest 태그 (v1 기반)
    docker tag ${REGISTRY}/${service}:v1 ${REGISTRY}/${service}:latest
    docker push ${REGISTRY}/${service}:latest
    
    echo "✅ ${service} built and pushed"
done

echo "🎉 All images built successfully!"
```

### Step 4: 인프라 컴포넌트 설치

```bash
./scripts/04-install-infra.sh
```

**이 스크립트가 수행하는 작업:**

1. **Istio 설치**
   - istioctl을 사용한 Istio 설치
   - Istio Ingress Gateway 구성
   - Kiali, Jaeger 애드온 설치

2. **ArgoCD 설치**
   - ArgoCD 네임스페이스 생성
   - ArgoCD 컴포넌트 배포
   - 초기 admin 비밀번호 설정

3. **Prometheus Stack 설치**
   - kube-prometheus-stack Helm 차트 설치
   - ServiceMonitor 및 PodMonitor 설정
   - Grafana 대시보드 프로비저닝

4. **Loki Stack 설치**
   - Loki 설치
   - Grafana Alloy 설치 및 설정
   - Loki 데이터소스 등록

**확인:**
```bash
# 모든 네임스페이스의 Pod 확인
kubectl get pods -A

# Istio 확인
kubectl get pods -n istio-system
# 예상 출력:
# NAME                                    READY   STATUS    RESTARTS   AGE
# istio-ingressgateway-xxx                1/1     Running   0          2m
# istiod-xxx                              1/1     Running   0          2m
# kiali-xxx                               1/1     Running   0          2m
# jaeger-xxx                              1/1     Running   0          2m

# ArgoCD 확인
kubectl get pods -n argocd
# 모든 Pod가 Running 상태여야 함

# Monitoring 확인
kubectl get pods -n monitoring
# prometheus, grafana, alertmanager, loki 등이 Running 상태여야 함

# ArgoCD 초기 비밀번호 확인
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo
```

**각 컴포넌트 설치 상세:**

#### 4.1 Istio 설치
```bash
# Istio 다운로드
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0
export PATH=$PWD/bin:$PATH

# Istio 설치 (demo 프로파일)
istioctl install --set profile=demo -y

# 네임스페이스에 자동 사이드카 주입 활성화
kubectl label namespace default istio-injection=enabled

# Kiali, Jaeger, Prometheus 애드온 설치
kubectl apply -f samples/addons/kiali.yaml
kubectl apply -f samples/addons/jaeger.yaml
kubectl apply -f samples/addons/prometheus.yaml
```

#### 4.2 ArgoCD 설치
```bash
# ArgoCD 네임스페이스 생성
kubectl create namespace argocd

# ArgoCD 설치
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# ArgoCD CLI 설치 (선택사항)
curl -sSL -o argocd-linux-amd64 \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

#### 4.3 Prometheus Stack 설치
```bash
# Prometheus Operator Helm 저장소 추가
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

# kube-prometheus-stack 설치
helm install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --create-namespace \
  -f helm/infra/kube-prometheus-stack/values.yaml

# Istio 메트릭을 위한 ServiceMonitor 생성
kubectl apply -f helm/infra/kube-prometheus-stack/istio-servicemonitor.yaml
```

#### 4.4 Loki Stack 설치
```bash
# Grafana Helm 저장소 추가
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Loki 설치
helm install loki grafana/loki-stack \
  -n monitoring \
  -f helm/infra/loki-stack/values.yaml

# Grafana Alloy 설치
kubectl apply -f helm/infra/loki-stack/alloy-configmap.yaml
kubectl apply -f helm/infra/loki-stack/alloy-deployment.yaml
```

### Step 5: 애플리케이션 배포

```bash
./scripts/05-deploy-apps.sh
```

**이 스크립트가 수행하는 작업:**
- ArgoCD Application 리소스 생성
- Umbrella Helm Chart를 통한 전체 애플리케이션 스택 배포
- Istio VirtualService 및 Gateway 설정

**확인:**
```bash
# ArgoCD Application 확인
kubectl get applications -n argocd
# 예상 출력:
# NAME        SYNC STATUS   HEALTH STATUS
# app-stack   Synced        Healthy

# 애플리케이션 Pod 확인
kubectl get pods
# 예상 출력:
# NAME                                READY   STATUS    RESTARTS   AGE
# frontend-xxx                        2/2     Running   0          2m
# api-gateway-xxx                     2/2     Running   0          2m
# order-service-xxx                   2/2     Running   0          2m
# inventory-service-xxx               2/2     Running   0          2m
# user-service-xxx                    2/2     Running   0          2m
# postgresql-0                        2/2     Running   0          2m

# Istio Gateway 및 VirtualService 확인
kubectl get gateway,virtualservice
```

**ArgoCD Application 매니페스트:**
```yaml
# argocd/applications/app-umbrella.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-stack
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-username/k8s-3tier-observability.git
    targetRevision: main
    path: helm/umbrella-chart
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Step 6: 접속 확인

**포트 포워딩 설정 (개발 환경):**
```bash
# Grafana
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Kiali
kubectl port-forward -n istio-system svc/kiali 20001:20001

# Jaeger
kubectl port-forward -n istio-system svc/tracing 16686:16686

# ArgoCD
kubectl port-forward -n argocd svc/argocd-server 8080:443
```

**또는 Istio Ingress Gateway를 통한 접속:**
```bash
# /etc/hosts에 도메인 추가
echo "127.0.0.1 app.local grafana.local kiali.local jaeger.local argocd.local" | sudo tee -a /etc/hosts

# 브라우저에서 접속
# http://app.local - Frontend
# http://grafana.local - Grafana
# http://kiali.local - Kiali
# http://jaeger.local - Jaeger
# http://argocd.local - ArgoCD
```

## 설치 검증

### 전체 시스템 검증 스크립트

```bash
#!/bin/bash

echo "🔍 Verifying installation..."

# 1. 클러스터 확인
echo "Checking cluster..."
kubectl cluster-info || exit 1

# 2. 노드 확인
echo "Checking nodes..."
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -ne 3 ]; then
    echo "❌ Expected 3 nodes, found $NODE_COUNT"
    exit 1
fi

# 3. Istio 확인
echo "Checking Istio..."
kubectl get pods -n istio-system | grep -E "Running|Completed" || exit 1

# 4. ArgoCD 확인
echo "Checking ArgoCD..."
kubectl get pods -n argocd | grep -E "Running|Completed" || exit 1

# 5. Monitoring 확인
echo "Checking Monitoring stack..."
kubectl get pods -n monitoring | grep -E "Running|Completed" || exit 1

# 6. 애플리케이션 확인
echo "Checking applications..."
kubectl get pods | grep -E "Running|Completed" || exit 1

# 7. Istio Sidecar 주입 확인
echo "Checking Istio sidecar injection..."
PODS_WITH_SIDECAR=$(kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}' | grep -o istio-proxy | wc -l)
if [ "$PODS_WITH_SIDECAR" -lt 5 ]; then
    echo "⚠️  Warning: Some pods might not have Istio sidecar injected"
fi

# 8. Frontend 접속 테스트
echo "Testing frontend connectivity..."
curl -f http://localhost/ || echo "⚠️  Frontend not accessible via localhost"

echo "✅ Installation verification completed!"
```

## 문제 해결

### 일반적인 문제

#### 1. Registry 접근 불가
**증상:**
```
Failed to pull image "localhost:5002/frontend:latest": rpc error: code = Unknown
```

**해결:**
```bash
# Registry가 실행 중인지 확인
docker ps | grep kind-registry

# Registry가 Kind 네트워크에 연결되어 있는지 확인
docker network inspect kind | grep kind-registry

# Registry 재시작
docker restart kind-registry

# Kind 노드에서 직접 테스트
docker exec -it kind-worker crictl pull localhost:5002/frontend:latest
```

#### 2. Istio Sidecar 미주입
**증상:**
Pod에 컨테이너가 1개만 있음 (istio-proxy 없음)

**해결:**
```bash
# 네임스페이스 라벨 확인
kubectl get namespace default --show-labels

# 라벨이 없으면 추가
kubectl label namespace default istio-injection=enabled --overwrite

# Pod 재시작
kubectl rollout restart deployment/<deployment-name>

# 확인
kubectl get pods -o jsonpath='{.items[*].spec.containers[*].name}'
# istio-proxy가 포함되어야 함
```

#### 3. ArgoCD 동기화 실패
**증상:**
```
ComparisonError: Manifest generation error
```

**해결:**
```bash
# Application 상태 확인
kubectl get application -n argocd app-stack -o yaml

# 수동 동기화
kubectl patch application -n argocd app-stack \
  --type merge \
  -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'

# Helm 차트 문법 확인
helm template ./helm/umbrella-chart --debug
```

#### 4. Prometheus 타겟 없음
**증상:**
Prometheus UI에서 타겟이 표시되지 않음

**해결:**
```bash
# ServiceMonitor 확인
kubectl get servicemonitor -A

# Prometheus 설정 확인
kubectl get prometheus -n monitoring -o yaml

# ServiceMonitor 라벨이 Prometheus selector와 일치하는지 확인
kubectl get prometheus -n monitoring -o jsonpath='{.items[0].spec.serviceMonitorSelector}'
```

#### 5. Grafana 대시보드 없음
**증상:**
Grafana에 대시보드가 표시되지 않음

**해결:**
```bash
# ConfigMap 확인
kubectl get configmap -n monitoring | grep dashboard

# Grafana Pod 로그 확인
kubectl logs -n monitoring deployment/prometheus-grafana

# 대시보드 수동 import
# Grafana UI → Create → Import → 대시보드 JSON 붙여넣기
```

### 로그 확인 방법

```bash
# 특정 Pod 로그
kubectl logs <pod-name>

# Istio Proxy 로그
kubectl logs <pod-name> -c istio-proxy

# 이전 Pod 로그 (재시작된 경우)
kubectl logs <pod-name> --previous

# 여러 Pod의 로그를 동시에 확인
kubectl logs -l app=order-service --tail=100 -f

# 모든 컨테이너의 로그
kubectl logs <pod-name> --all-containers=true
```

### 완전 재설치

모든 것을 제거하고 처음부터 다시 시작하려면:

```bash
# Kind 클러스터 삭제
kind delete cluster --name k8s-lab

# Registry 삭제
docker rm -f kind-registry

# Docker 이미지 정리 (선택사항)
docker system prune -a

# 처음부터 다시 시작
./scripts/01-setup-registry.sh
./scripts/02-setup-cluster.sh
# ... (나머지 단계 반복)
```

## 다음 단계

설치가 완료되었다면:

1. [배포 전략 가이드](./DEPLOYMENT_STRATEGIES.md)를 따라 Rolling Update, Canary, Blue/Green 배포를 실습하세요.
2. [모니터링 가이드](./MONITORING.md)를 통해 Grafana 대시보드와 Jaeger 트레이싱을 활용하세요.
3. 부하 테스트를 실행하여 시스템 동작을 확인하세요: `./scripts/run-load-test.sh`

## 추가 리소스

- [Kind Documentation](https://kind.sigs.k8s.io/)
- [Istio Installation Guide](https://istio.io/latest/docs/setup/install/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
