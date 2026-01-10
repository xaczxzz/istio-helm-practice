#!/bin/bash
set -e

REGISTRY="localhost:5002"
SERVICES=("frontend" "api-gateway" "order-service" "inventory-service" "user-service")
VERSIONS=("v1" "v2")

echo "🏗️  Building application images..."

for service in "${SERVICES[@]}"; do
    echo ""
    echo "Building ${service}..."
    
    for version in "${VERSIONS[@]}"; do
        echo "  Building ${service}:${version}..."
        
        # v1, v2 각각 빌드
        docker build \
            -t ${REGISTRY}/${service}:${version} \
            -f apps/${service}/Dockerfile.${version} \
            apps/${service}/
        
        echo "  Pushing ${service}:${version}..."
        docker push ${REGISTRY}/${service}:${version}
    done
    
    # latest 태그 (v1 기반)
    echo "  Tagging ${service}:latest..."
    docker tag ${REGISTRY}/${service}:v1 ${REGISTRY}/${service}:latest
    docker push ${REGISTRY}/${service}:latest
    
    echo "✅ ${service} built and pushed"
done

echo ""
echo "🎉 All images built successfully!"
echo ""
echo "Verifying images in registry..."
curl -s http://localhost:5002/v2/_catalog | jq '.'

echo ""
echo "Available images:"
for service in "${SERVICES[@]}"; do
    echo "  ${REGISTRY}/${service}:latest"
    echo "  ${REGISTRY}/${service}:v1"
    echo "  ${REGISTRY}/${service}:v2"
done