#!/bin/bash
set -e

echo "🚀 Deploying applications via ArgoCD..."

sleep 10
# Apply App of Apps
echo "Deploying App of Apps..."
kubectl apply -f argocd/applications/app-of-apps.yaml

echo ""
echo "✅ App of Apps deployed!"
echo ""
echo "📊 Monitoring ArgoCD applications..."
echo ""

# Wait a bit for applications to be created


# Show application status
kubectl get applications -n argocd

echo ""
echo "🔧 To watch the deployment progress:"
echo "  kubectl get applications -n argocd -w"
echo "  argocd app list"
echo "  argocd app get app-stack"
echo ""
echo "🌐 ArgoCD UI: https://localhost:8080 (if port-forwarding)"
echo ""
echo "⏳ Applications will be automatically synced by ArgoCD"
echo "   Check status with: argocd app list"