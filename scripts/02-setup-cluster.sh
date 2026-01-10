#!/bin/bash
set -e

CLUSTER_NAME="k8s-lab"
REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5000"

echo "🚀 Setting up Kind cluster..."

# 기존 클러스터 제거 (있는 경우)
if kind get clusters | grep -q ${CLUSTER_NAME}; then
    echo "Removing existing cluster..."
    kind delete cluster --name ${CLUSTER_NAME}
fi

# Kind 클러스터 생성
echo "Creating Kind cluster..."
kind create cluster --config k8s/kind-config.yaml --name ${CLUSTER_NAME}

# 레지스트리를 Kind 네트워크에 연결
if [ "$(docker ps -q -f name=${REGISTRY_NAME})" ]; then
    echo "Connecting registry to kind network..."
    docker network connect kind ${REGISTRY_NAME} 2>/dev/null || true
    
    # 레지스트리 IP 확인
    REGISTRY_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${REGISTRY_NAME})
    echo "Registry IP: ${REGISTRY_IP}"
    
    # 클러스터 노드에 레지스트리 설정 적용
    echo "Configuring registry in cluster nodes..."
    for node in $(kind get nodes --name ${CLUSTER_NAME}); do
        echo "Configuring node: ${node}"
        
        # containerd 설정 생성 (기존 설정 덮어쓰기)
        docker exec "${node}" sh -c "cat > /etc/containerd/config.toml <<'CONFEOF'
version = 2

[plugins]
  [plugins.\"io.containerd.grpc.v1.cri\"]
    [plugins.\"io.containerd.grpc.v1.cri\".registry]
      [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors]
        [plugins.\"io.containerd.grpc.v1.cri\".registry.mirrors.\"kind-registry:5000\"]
          endpoint = [\"http://kind-registry:5000\"]
      [plugins.\"io.containerd.grpc.v1.cri\".registry.configs]
        [plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"kind-registry:5000\"]
          [plugins.\"io.containerd.grpc.v1.cri\".registry.configs.\"kind-registry:5000\".tls]
            insecure_skip_verify = true
CONFEOF
"
        
        # containerd 재시작
        docker exec "${node}" systemctl restart containerd
        
        # 레지스트리 접근 테스트
        echo "Testing registry access from ${node}..."
        docker exec "${node}" sh -c "curl -s http://${REGISTRY_NAME}:${REGISTRY_PORT}/v2/_catalog || echo 'Registry not accessible yet'"
    done
    
    echo ""
    echo "✅ Registry configured successfully!"
    echo "   Access from nodes: ${REGISTRY_NAME}:${REGISTRY_PORT}"
    echo "   Access from host:  localhost:5002"
fi

# kubectl 컨텍스트 설정
echo ""
echo "Setting kubectl context..."
kubectl cluster-info --context kind-${CLUSTER_NAME}

# 클러스터 상태 확인
echo ""
echo "Verifying cluster..."
kubectl get nodes

echo ""
echo "✅ Kind cluster '${CLUSTER_NAME}' is ready!"
echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide
echo ""
echo "Current context: $(kubectl config current-context)"
echo ""
echo "Registry configuration:"
echo "  - In your values files, use: ${REGISTRY_NAME}:${REGISTRY_PORT}/image-name:tag"
echo "  - Example: ${REGISTRY_NAME}:${REGISTRY_PORT}/api-gateway:v1"
echo ""
echo "To delete this cluster later, run:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"