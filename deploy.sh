#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-velero}"

echo "=== Deploying Velero + MinIO for Kubernetes Backups ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

step() {
    echo -e "${GREEN}==>${NC} $1"
}

info() {
    echo -e "${YELLOW}→${NC} $1"
}

fail() {
    echo -e "${RED}❌${NC} $1"
    exit 1
}

# Check prerequisites
step "1/6: Checking prerequisites"

if ! command -v kubectl &> /dev/null; then
    fail "kubectl not found. Please install kubectl."
fi

if ! command -v helm &> /dev/null; then
    fail "helm not found. Please install helm."
fi

if ! kubectl cluster-info &> /dev/null; then
    fail "Cannot connect to Kubernetes cluster. Check your KUBECONFIG."
fi

echo "✅ Prerequisites met"
echo ""

# Add Helm repos
step "2/6: Adding Helm repositories"
helm repo add minio https://charts.min.io/ 2>/dev/null || true
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts 2>/dev/null || true
helm repo update
echo ""

# Create namespace
step "3/6: Creating namespace: $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo ""

# Deploy MinIO (S3-compatible backend)
step "4/6: Deploying MinIO"
helm upgrade --install minio minio/minio \
    --namespace "$NAMESPACE" \
    --values minio-values.yaml \
    --wait \
    --timeout 5m
echo "✅ MinIO deployed"
echo ""

# Create Velero credentials secret
step "5/6: Creating Velero credentials"

if kubectl get secret velero-credentials -n "$NAMESPACE" &>/dev/null; then
    info "Credentials secret already exists, skipping"
else
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: velero-credentials
  namespace: $NAMESPACE
type: Opaque
stringData:
  cloud: |
    [default]
    aws_access_key_id = velero
    aws_secret_access_key = velero-secret-key
EOF
    echo "✅ Credentials created"
fi
echo ""

# Deploy Velero
step "6/6: Deploying Velero"
helm upgrade --install velero vmware-tanzu/velero \
    --namespace "$NAMESPACE" \
    --values velero-values.yaml \
    --wait \
    --timeout 5m
echo "✅ Velero deployed"
echo ""

# Wait for pods
info "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod --all -n "$NAMESPACE" --timeout=300s 2>/dev/null || true
echo ""

# Deploy backup schedules
step "Deploying backup schedules"
kubectl apply -f backup-schedules/
echo "✅ Schedules deployed"
echo ""

# Verify backup storage location
info "Verifying backup storage location..."
sleep 5
if kubectl -n "$NAMESPACE" get backupstoragelocation default -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Available"; then
    echo "✅ Backup storage location is available"
else
    echo "⚠️  Backup storage location not available yet. Check logs:"
    echo "   kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=velero"
fi
echo ""

# Summary
step "Deployment complete!"
echo ""
echo "MinIO S3 Console:"
MINIO_HOST=$(kubectl get ingress -n "$NAMESPACE" -l app=minio -o jsonpath='{.items[0].spec.rules[0].host}' 2>/dev/null || echo "minio-console.media.lan")
echo "  http://$MINIO_HOST"
echo "  User: velero"
echo "  Password: velero-secret-key"
echo ""
echo "Velero CLI:"
echo "  velero backup-location get"
echo "  velero schedule get"
echo "  velero backup get"
echo ""
echo "Backup schedules:"
echo "  • media-daily: 2am daily (7 day retention)"
echo "  • cluster-weekly: 3am Sunday (30 day retention)"
echo ""
echo "Manual backup:"
echo "  velero backup create media-manual --include-namespaces media --default-volumes-to-fs-backup --wait"
echo ""
echo "Check logs:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=velero"
echo "  kubectl logs -n $NAMESPACE -l name=node-agent"
