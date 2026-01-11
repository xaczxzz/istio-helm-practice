#!/bin/bash

echo "🔧 Installing MetalLB for LoadBalancer support..."

# MetalLB 설치
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

echo "⏳ Waiting for MetalLB to be ready..."
kubectl wait --namespace metallb-system \
                --for=condition=ready pod \
                --selector=app=metallb \
                --timeout=90s

# Docker 네트워크 정보 확인
NETWORK=$(docker network inspect -f '{{.IPAM.Config}}' kind | grep -oE '172\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1)
echo "📡 Kind network: $NETWORK"

# IP 범위 계산 (예: 172.18.255.200-172.18.255.250)
BASE_IP=$(echo $NETWORK | cut -d'/' -f1 | cut -d'.' -f1-3)
IP_RANGE="${BASE_IP}.255.200-${BASE_IP}.255.250"

echo "🌐 Setting up IP address pool: $IP_RANGE"

# MetalLB 설정
cat <<EOF | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: example
  namespace: metallb-system
spec:
  addresses:
  - $IP_RANGE
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: empty
  namespace: metallb-system
EOF

echo "⏳ Waiting for LoadBalancer IP assignment..."
sleep 10

# LoadBalancer IP 확인
EXTERNAL_IP=$(kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -n "$EXTERNAL_IP" ]; then
    echo "✅ MetalLB setup complete!"
    echo "🌐 External IP: $EXTERNAL_IP"
    echo "🚀 Application is now accessible at: http://$EXTERNAL_IP"
    echo ""
    echo "📋 Available endpoints:"
    echo "   - Frontend: http://$EXTERNAL_IP"
    echo "   - API Health: http://$EXTERNAL_IP/api/health"
    echo "   - Orders API: http://$EXTERNAL_IP/api/orders"
else
    echo "⚠️  LoadBalancer IP not assigned yet. Please wait a moment and check:"
    echo "   kubectl get svc -n istio-system istio-ingressgateway"
fi