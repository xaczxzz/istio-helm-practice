#!/bin/bash

echo "🚀 Setting up local access to the application..."

# Istio Ingress Gateway 포트포워딩 설정
echo "📡 Setting up Istio Ingress Gateway port forwarding..."

# 기존 포트포워딩 프로세스 종료
pkill -f "kubectl port-forward.*istio-ingressgateway" || true

# Istio Ingress Gateway를 통한 포트포워딩 (백그라운드)
kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80 &
GATEWAY_PID=$!

echo "✅ Istio Ingress Gateway port forwarding started (PID: $GATEWAY_PID)"
echo "🌐 Application is now accessible at: http://localhost:8080"
echo ""
echo "📋 Available endpoints:"
echo "   - Frontend: http://localhost:8080"
echo "   - API Health: http://localhost:8080/api/health"
echo "   - Orders API: http://localhost:8080/api/orders"
echo "   - Users API: http://localhost:8080/api/users"
echo "   - Inventory API: http://localhost:8080/api/inventory"
echo ""
echo "🛑 To stop port forwarding:"
echo "   kill $GATEWAY_PID"
echo "   or run: pkill -f 'kubectl port-forward.*istio-ingressgateway'"
echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5

# 서비스 상태 확인
echo "🔍 Checking service status..."
curl -s http://localhost:8080/health && echo "✅ Frontend is healthy" || echo "❌ Frontend not responding"
curl -s http://localhost:8080/api/health && echo "✅ API Gateway is healthy" || echo "❌ API Gateway not responding"

echo ""
echo "🎉 Setup complete! Open http://localhost:8080 in your browser"