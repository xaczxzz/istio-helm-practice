#!/bin/bash
set -e

echo "🚀 Installing ArgoCD..."

# Create ArgoCD namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=argocd-server \
    -n argocd \
    --timeout=300s

# Get ArgoCD admin password
echo ""
echo "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)


kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'

kubectl patch deployment argocd-server -n argocd -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "argocd-server",
          "resources": {
            "requests": {
              "memory": "256Mi",
              "cpu": "100m"
            },
            "limits": {
              "memory": "512Mi",
              "cpu": "1000m"
            }
          }
        }]
      }
    }
  }
}'

echo "✅ ArgoCD installed successfully!"
echo ""
echo "📝 ArgoCD admin password: ${ARGOCD_PASSWORD}"
echo ""
echo "🔧 To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  Then visit: https://localhost:8080"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "Next step: Run ./scripts/05-deploy-argocd-apps.sh"