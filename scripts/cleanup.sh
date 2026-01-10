#!/bin/bash
set -e

CLUSTER_NAME="k8s-lab"
REGISTRY_NAME="kind-registry"

echo "🧹 Cleaning up K8s 3-Tier Observability Lab..."

# Function to ask for confirmation
confirm() {
    read -p "$1 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
}

# Parse command line arguments
FORCE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --force    Skip confirmation prompts"
            echo "  --help     Show this help message"
            echo ""
            echo "This script will:"
            echo "  1. Delete the Kind cluster"
            echo "  2. Remove the local Docker registry"
            echo "  3. Clean up Docker images (optional)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ "$FORCE" = false ]; then
    echo "This will delete:"
    echo "  - Kind cluster: $CLUSTER_NAME"
    echo "  - Docker registry: $REGISTRY_NAME"
    echo "  - All associated resources"
    echo ""
    
    if ! confirm "Are you sure you want to continue?"; then
        echo "Cleanup cancelled."
        exit 0
    fi
fi

# 1. Delete Kind cluster
echo ""
echo "🗑️  Deleting Kind cluster..."
if kind get clusters | grep -q $CLUSTER_NAME; then
    kind delete cluster --name $CLUSTER_NAME
    echo "✅ Kind cluster '$CLUSTER_NAME' deleted"
else
    echo "ℹ️  Kind cluster '$CLUSTER_NAME' not found"
fi

# 2. Remove Docker registry
echo ""
echo "🗑️  Removing Docker registry..."
if [ "$(docker ps -aq -f name=$REGISTRY_NAME)" ]; then
    docker rm -f $REGISTRY_NAME
    echo "✅ Docker registry '$REGISTRY_NAME' removed"
else
    echo "ℹ️  Docker registry '$REGISTRY_NAME' not found"
fi

# 3. Clean up Docker images (optional)
echo ""
if [ "$FORCE" = true ] || confirm "Do you want to remove Docker images built for this project?"; then
    echo "🗑️  Removing Docker images..."
    
    # Remove application images
    SERVICES=("frontend" "api-gateway" "order-service" "inventory-service" "user-service")
    for service in "${SERVICES[@]}"; do
        # Remove all versions of the service images
        docker images --format "table {{.Repository}}:{{.Tag}}" | grep "localhost:5002/$service" | while read image; do
            if [ ! -z "$image" ]; then
                docker rmi "$image" 2>/dev/null || true
            fi
        done
    done
    
    # Remove dangling images
    docker image prune -f
    
    echo "✅ Docker images cleaned up"
else
    echo "ℹ️  Skipping Docker image cleanup"
fi

# 4. Clean up kubectl context (if it exists)
echo ""
echo "🗑️  Cleaning up kubectl context..."
if kubectl config get-contexts | grep -q "kind-$CLUSTER_NAME"; then
    kubectl config delete-context "kind-$CLUSTER_NAME" 2>/dev/null || true
    echo "✅ kubectl context cleaned up"
fi

# 5. Remove temporary files
echo ""
echo "🗑️  Removing temporary files..."
rm -f /tmp/k6-test-*.js
rm -rf istio-1.20.0/ 2>/dev/null || true
echo "✅ Temporary files cleaned up"

# Summary
echo ""
echo "🎉 Cleanup completed!"
echo ""
echo "What was cleaned up:"
echo "  ✅ Kind cluster '$CLUSTER_NAME'"
echo "  ✅ Docker registry '$REGISTRY_NAME'"
if [ "$FORCE" = true ] || docker images | grep -q "localhost:5002"; then
    echo "  ✅ Docker images"
else
    echo "  ⏭️  Docker images (skipped)"
fi
echo "  ✅ kubectl context"
echo "  ✅ Temporary files"
echo ""
echo "💡 To start over, run:"
echo "  ./scripts/01-setup-registry.sh"
echo "  ./scripts/02-setup-cluster.sh"
echo "  # ... and so on"