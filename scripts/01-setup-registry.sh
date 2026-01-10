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
echo ""
echo "Registry URL: http://localhost:${REGISTRY_PORT}"
echo "Registry Name: ${REGISTRY_NAME}"
echo ""
echo "You can now build and push images to localhost:${REGISTRY_PORT}/"