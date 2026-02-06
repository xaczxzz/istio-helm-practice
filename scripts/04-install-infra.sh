#!/bin/bash
set -e

echo "🚀 Installing Infrastructure..."

###########################
# 1. Namespace 준비
###########################
echo "Preparing namespaces..."
kubectl label namespace default istio-injection=enabled --overwrite
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace argocd istio-injection=enabled --overwrite

###########################
# 2. ArgoCD 설치
###########################
echo ""
echo "📦 Installing ArgoCD..."
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.16/manifests/install.yaml

echo "Waiting for ArgoCD pods to be created..."
sleep 10

# Patch ArgoCD Server
kubectl patch deployment argocd-server -n argocd --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--insecure"
  }
]'

echo "Waiting for ArgoCD to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

###########################
# 3. Metrics Server
###########################
echo ""
echo "📊 Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
sleep 5

kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--kubelet-insecure-tls"
  }
]'

###########################
# 완료
###########################
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "✅ Infrastructure installed successfully!"
echo ""
echo "📝 ArgoCD admin password: ${ARGOCD_PASSWORD}"
echo ""
echo "� To access ArgoCD UI:"
echo "  kubectl port-forward svc/argocd-server -n argocd 8888:80"
echo "  Then visit: http://localhost:8888"
echo "  Username: admin"
echo "  Password: ${ARGOCD_PASSWORD}"
echo ""
echo "📊 Next steps:"
echo "  1. Deploy ArgoCD applications: kubectl apply -f argocd/applications/app-of-apps.yaml"
echo "  2. Monitor deployment: kubectl get applications -n argocd"
echo ""
echo "💡 Note: Jaeger and Kiali will be installed via ArgoCD applications"

