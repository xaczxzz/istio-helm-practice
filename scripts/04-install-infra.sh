#!/bin/bash
set -e

echo "🚀 Installing infrastructure components..."

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label_selector=$2
    local timeout=${3:-300}
    
    echo "Waiting for pods in namespace ${namespace} with selector ${label_selector}..."
    kubectl wait --for=condition=ready pod \
        -l ${label_selector} \
        -n ${namespace} \
        --timeout=${timeout}s
}

# 1. Install Istio
echo ""
echo "📦 Installing Istio..."

# Download and install istioctl if not present
if ! command -v istioctl &> /dev/null; then
    echo "Downloading istioctl..."
    curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
    export PATH="$PWD/istio-1.20.0/bin:$PATH"
fi

# Install Istio with demo profile
echo "Installing Istio with demo profile..."
istioctl install --set profile=demo -y

# Enable Istio injection for default namespace
echo "Enabling Istio injection for default namespace..."
kubectl label namespace default istio-injection=enabled --overwrite

# Install Istio addons
echo "Installing Istio addons..."
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Wait for Istio components
wait_for_pods "istio-system" "app=istiod"
wait_for_pods "istio-system" "app=istio-ingressgateway"

echo "✅ Istio installed successfully"

# 2. Install ArgoCD
echo ""
echo "📦 Installing ArgoCD..."

# Create ArgoCD namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD components
wait_for_pods "argocd" "app.kubernetes.io/name=argocd-server"

# Get ArgoCD admin password
echo "Getting ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: ${ARGOCD_PASSWORD}"

echo "✅ ArgoCD installed successfully"

# 3. Install Prometheus Stack
echo ""
echo "📦 Installing Prometheus Stack..."

# Add Helm repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Create monitoring namespace
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Install kube-prometheus-stack
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set grafana.adminPassword=admin123 \
    --set grafana.service.type=ClusterIP \
    --set prometheus.service.type=ClusterIP \
    --set alertmanager.service.type=ClusterIP

# Wait for Prometheus components
wait_for_pods "monitoring" "app=kube-prometheus-stack-operator" 300

# Wait for Prometheus instance (StatefulSet이므로 시간이 더 걸릴 수 있음)
echo "Waiting for Prometheus StatefulSet..."
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 \
    statefulset/prometheus-prometheus-kube-prometheus-prometheus \
    -n monitoring --timeout=600s || true

# Wait for Grafana
wait_for_pods "monitoring" "app.kubernetes.io/name=grafana"

echo "✅ Prometheus Stack installed successfully"

# 4. Install Loki Stack
echo ""
echo "📦 Installing Loki Stack..."

# Add Grafana Helm repository
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

# Install Loki
helm upgrade --install loki grafana/loki-stack \
    --namespace monitoring \
    --set loki.persistence.enabled=false \
    --set promtail.enabled=true \
    --set grafana.enabled=false

# Wait for Loki components
wait_for_pods "monitoring" "app=loki"

echo "✅ Loki Stack installed successfully"

# 5. Create Istio Gateway and VirtualServices for monitoring tools
echo ""
echo "📦 Creating Istio Gateway for monitoring tools..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: monitoring-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana-vs
  namespace: monitoring
spec:
  hosts:
  - "*"
  gateways:
  - istio-system/monitoring-gateway
  http:
  - match:
    - uri:
        prefix: /grafana
    route:
    - destination:
        host: prometheus-grafana
        port:
          number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kiali-vs
  namespace: istio-system
spec:
  hosts:
  - "*"
  gateways:
  - monitoring-gateway
  http:
  - match:
    - uri:
        prefix: /kiali
    route:
    - destination:
        host: kiali
        port:
          number: 20001
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: jaeger-vs
  namespace: istio-system
spec:
  hosts:
  - "*"
  gateways:
  - monitoring-gateway
  http:
  - match:
    - uri:
        prefix: /jaeger
    route:
    - destination:
        host: tracing
        port:
          number: 16686
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: argocd-vs
  namespace: argocd
spec:
  hosts:
  - "*"
  gateways:
  - istio-system/monitoring-gateway
  http:
  - match:
    - uri:
        prefix: /argocd
    route:
    - destination:
        host: argocd-server
        port:
          number: 80
EOF

echo "✅ Istio Gateway created successfully"

# Summary
echo ""
echo "🎉 Infrastructure installation completed!"
echo ""
echo "📊 Access URLs (after port-forwarding or ingress setup):"
echo "  Grafana:    http://localhost/grafana (admin/admin123)"
echo "  Kiali:      http://localhost/kiali"
echo "  Jaeger:     http://localhost/jaeger"
echo "  ArgoCD:     http://localhost/argocd (admin/${ARGOCD_PASSWORD})"
echo "  Prometheus: http://localhost/prometheus"
echo ""
echo "🔧 To access via port-forwarding:"
echo "  kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
echo "  kubectl port-forward -n istio-system svc/kiali 20001:20001"
echo "  kubectl port-forward -n istio-system svc/tracing 16686:16686"
echo "  kubectl port-forward -n argocd svc/argocd-server 8080:443"
echo ""
echo "📝 ArgoCD admin password: ${ARGOCD_PASSWORD}"
echo ""
echo "Next step: Run ./scripts/05-deploy-apps.sh to deploy applications"