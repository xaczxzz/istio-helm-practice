#!/bin/bash
set -e

CLUSTER_NAME="k8s-lab"
REGISTRY_NAME="kind-registry"

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
    
    # 클러스터 노드에 레지스트리 설정 적용
    echo "Configuring registry in cluster nodes..."
    for node in $(kind get nodes --name ${CLUSTER_NAME}); do
        docker exec "${node}" sh -c "echo '127.0.0.1 ${REGISTRY_NAME}' >> /etc/hosts"
    done
fi

# kubectl 컨텍스트 설정
echo "Setting kubectl context..."
kubectl cluster-info --context kind-${CLUSTER_NAME}

# 클러스터 상태 확인
echo "Verifying cluster..."
kubectl get nodes

echo "✅ Kind cluster '${CLUSTER_NAME}' is ready!"
echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide
echo ""
echo "Current context: $(kubectl config current-context)"
echo ""
echo "To delete this cluster later, run:"
echo "  kind delete cluster --name ${CLUSTER_NAME}"