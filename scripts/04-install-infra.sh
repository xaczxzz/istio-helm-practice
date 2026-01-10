#!/bin/bash
set -e

echo "🚀 Installing ArgoCD..."
kubectl label namespace default istio-injection=enabled
# Create ArgoCD namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
# kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.16/manifests/install.yaml

# Wait for ArgoCD pods to be created
echo "Waiting for ArgoCD pods to be created..."
sleep 10

# Patch ArgoCD Server for insecure mode (before it starts)
echo "Configuring ArgoCD Server..."
kubectl patch deployment argocd-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--insecure"
  }
]'


# Get ArgoCD admin password
echo ""
echo "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Install Metrics Server
echo ""
echo "📊 Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Wait for Metrics Server to be created
sleep 5

# Patch Metrics Server for Kind
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'

echo ""
echo "✅ ArgoCD installed successfully!"
echo ""
echo "📝 ArgoCD admin password: ${ARGOCD_PASSWORD}"
echo ""
echo "🔧 To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:80"
echo "  Then visit: http://localhost:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "📊 ArgoCD Components:"
kubectl get pods -n argocd
echo ""
echo "💡 Note: Notifications, Dex, and ApplicationSet controllers are disabled for local development"
echo ""
echo "Next step: Run ./scripts/05-deploy-argocd-apps.sh"