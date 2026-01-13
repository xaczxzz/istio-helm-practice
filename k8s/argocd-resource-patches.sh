#!/bin/bash
# ArgoCD 컴포넌트 리소스 증설 스크립트

echo "Patching ArgoCD Server resources..."
kubectl patch deployment argocd-server -n argocd --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {
        "cpu": "500m",
        "memory": "1024Mi"
      },
      "limits": {
        "cpu": "1000m",
        "memory": "2048Mi"
      }
    }
  }
]'

echo "Patching ArgoCD Repo Server resources..."
kubectl patch deployment argocd-repo-server -n argocd --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {
        "cpu": "500m",
        "memory": "1024Mi"
      },
      "limits": {
        "cpu": "1000m",
        "memory": "2048Mi"
      }
    }
  }
]'

echo "Patching ArgoCD Application Controller resources..."
kubectl patch statefulset argocd-application-controller -n argocd --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/template/spec/containers/0/resources",
    "value": {
      "requests": {
        "cpu": "1000m",
        "memory": "2048Mi"
      },
      "limits": {
        "cpu": "2000m",
        "memory": "4096Mi"
      }
    }
  }
]'

echo "ArgoCD resource patches applied successfully!"