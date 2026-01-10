#!/bin/bash
set -e

echo "🚀 Deploying applications..."

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

# 1. Create PostgreSQL deployment
echo ""
echo "📦 Deploying PostgreSQL..."

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: postgres-init-script
  namespace: default
data:
  init.sql: |
    -- Create databases for each service
    CREATE DATABASE IF NOT EXISTS order_db;
    CREATE DATABASE IF NOT EXISTS inventory_db;
    CREATE DATABASE IF NOT EXISTS user_db;
    
    -- Grant permissions
    GRANT ALL PRIVILEGES ON DATABASE order_db TO postgres;
    GRANT ALL PRIVILEGES ON DATABASE inventory_db TO postgres;
    GRANT ALL PRIVILEGES ON DATABASE user_db TO postgres;
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgresql
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgresql
  template:
    metadata:
      labels:
        app: postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:15
        env:
        - name: POSTGRES_DB
          value: postgres
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_PASSWORD
          value: postgres
        ports:
        - containerPort: 5432
        volumeMounts:
        - name: init-script
          mountPath: /docker-entrypoint-initdb.d
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "1000m"
      volumes:
      - name: init-script
        configMap:
          name: postgres-init-script
---
apiVersion: v1
kind: Service
metadata:
  name: postgresql
  namespace: default
spec:
  selector:
    app: postgresql
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF

# Wait for PostgreSQL to be ready
wait_for_pods "default" "app=postgresql"

echo "✅ PostgreSQL deployed successfully"

# 2. Deploy applications using kubectl
echo ""
echo "📦 Deploying applications..."

# Frontend
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
      version: v1
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      containers:
      - name: frontend
        image: localhost:5002/frontend:v1
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "200m"
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  namespace: default
spec:
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

# API Gateway
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
      version: v1
  template:
    metadata:
      labels:
        app: api-gateway
        version: v1
    spec:
      containers:
      - name: api-gateway
        image: localhost:5002/api-gateway:v1
        ports:
        - containerPort: 8000
        env:
        - name: ORDER_SERVICE_URL
          value: "http://order-service:8080"
        - name: INVENTORY_SERVICE_URL
          value: "http://inventory-service:3000"
        - name: USER_SERVICE_URL
          value: "http://user-service:8000"
        - name: JAEGER_AGENT_HOST
          value: "jaeger"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
  namespace: default
spec:
  selector:
    app: api-gateway
  ports:
  - port: 8000
    targetPort: 8000
  type: ClusterIP
EOF

# Order Service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: order-service
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: order-service
      version: v1
  template:
    metadata:
      labels:
        app: order-service
        version: v1
    spec:
      containers:
      - name: order-service
        image: localhost:5002/order-service:v1
        ports:
        - containerPort: 8080
        env:
        - name: DB_HOST
          value: "postgresql"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "postgres"
        - name: DB_USER
          value: "postgres"
        - name: DB_PASSWORD
          value: "postgres"
        - name: JAEGER_ENDPOINT
          value: "jaeger"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: order-service
  namespace: default
spec:
  selector:
    app: order-service
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
EOF

# Inventory Service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-service
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory-service
      version: v1
  template:
    metadata:
      labels:
        app: inventory-service
        version: v1
    spec:
      containers:
      - name: inventory-service
        image: localhost:5002/inventory-service:v1
        ports:
        - containerPort: 3000
        env:
        - name: DB_HOST
          value: "postgresql"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "postgres"
        - name: DB_USER
          value: "postgres"
        - name: DB_PASSWORD
          value: "postgres"
        - name: JAEGER_ENDPOINT
          value: "jaeger"
        - name: SERVICE_VERSION
          value: "v1.0.0"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: inventory-service
  namespace: default
spec:
  selector:
    app: inventory-service
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
EOF

# User Service
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: user-service
  namespace: default
spec:
  replicas: 2
  selector:
    matchLabels:
      app: user-service
      version: v1
  template:
    metadata:
      labels:
        app: user-service
        version: v1
    spec:
      containers:
      - name: user-service
        image: localhost:5002/user-service:v1
        ports:
        - containerPort: 8000
        env:
        - name: DB_HOST
          value: "postgresql"
        - name: DB_PORT
          value: "5432"
        - name: DB_NAME
          value: "postgres"
        - name: DB_USER
          value: "postgres"
        - name: DB_PASSWORD
          value: "postgres"
        - name: JAEGER_AGENT_HOST
          value: "jaeger"
        - name: SERVICE_VERSION
          value: "v1.0.0"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
---
apiVersion: v1
kind: Service
metadata:
  name: user-service
  namespace: default
spec:
  selector:
    app: user-service
  ports:
  - port: 8000
    targetPort: 8000
  type: ClusterIP
EOF

# 3. Create Istio Gateway and VirtualService for the application
echo ""
echo "📦 Creating Istio Gateway for applications..."

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: app-gateway
  namespace: default
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
  name: app-vs
  namespace: default
spec:
  hosts:
  - "*"
  gateways:
  - app-gateway
  http:
  - match:
    - uri:
        prefix: /api/
    route:
    - destination:
        host: api-gateway
        port:
          number: 8000
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: frontend
        port:
          number: 80
EOF

# Wait for all applications to be ready
echo ""
echo "⏳ Waiting for applications to be ready..."

wait_for_pods "default" "app=frontend"
wait_for_pods "default" "app=api-gateway"
wait_for_pods "default" "app=order-service"
wait_for_pods "default" "app=inventory-service"
wait_for_pods "default" "app=user-service"

# 4. Create ServiceMonitors for Prometheus
echo ""
echo "📦 Creating ServiceMonitors for Prometheus..."

cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-services
  namespace: default
  labels:
    app: app-services
spec:
  selector:
    matchLabels:
      app: api-gateway
  endpoints:
  - port: http
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-service
  namespace: default
  labels:
    app: order-service
spec:
  selector:
    matchLabels:
      app: order-service
  endpoints:
  - port: http
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: inventory-service
  namespace: default
  labels:
    app: inventory-service
spec:
  selector:
    matchLabels:
      app: inventory-service
  endpoints:
  - port: http
    path: /metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: user-service
  namespace: default
  labels:
    app: user-service
spec:
  selector:
    matchLabels:
      app: user-service
  endpoints:
  - port: http
    path: /metrics
EOF

echo "✅ Applications deployed successfully!"

# Summary
echo ""
echo "🎉 Application deployment completed!"
echo ""
echo "📊 Deployed services:"
kubectl get pods -o wide
echo ""
echo "🌐 Access URLs:"
echo "  Frontend:   http://localhost (via Istio Ingress Gateway)"
echo "  API:        http://localhost/api/"
echo ""
echo "🔧 To access the application:"
echo "  kubectl port-forward -n istio-system svc/istio-ingressgateway 8080:80"
echo "  Then visit: http://localhost:8080"
echo ""
echo "📝 Check application health:"
echo "  curl http://localhost:8080/api/health"
echo ""
echo "Next step: Run ./scripts/run-load-test.sh to test the application"