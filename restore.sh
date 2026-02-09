#!/bin/bash
set -euo pipefail

BACKUP_NAME="${1:-}"
NAMESPACE_FILTER="${2:-}"

if [[ -z "$BACKUP_NAME" ]]; then
    echo "Usage: $0 <backup-name> [namespace-to-restore]"
    echo ""
    echo "Available backups:"
    velero backup get
    exit 1
fi

echo "=== Restoring from backup: $BACKUP_NAME ==="
echo ""

if [[ -n "$NAMESPACE_FILTER" ]]; then
    echo "Restoring only namespace: $NAMESPACE_FILTER"
    read -p "⚠️  This will restore resources in namespace $NAMESPACE_FILTER. Continue? (y/N) " -n 1 -r
else
    echo "Restoring all namespaces from backup"
    read -p "⚠️  This will restore ALL resources from the backup. Continue? (y/N) " -n 1 -r
fi
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    exit 0
fi

# Generate unique restore name
RESTORE_NAME="restore-$(date +%s)"

# Build velero restore command
CMD="velero restore create $RESTORE_NAME --from-backup $BACKUP_NAME"

if [[ -n "$NAMESPACE_FILTER" ]]; then
    CMD="$CMD --include-namespaces $NAMESPACE_FILTER"
fi

CMD="$CMD --wait"

echo ""
echo "Running restore..."
echo "Command: $CMD"
echo ""

# Execute restore
eval "$CMD"

echo ""
echo "=== Restore complete ==="
echo ""
echo "Check restore status:"
echo "  velero restore describe $RESTORE_NAME"
echo "  velero restore logs $RESTORE_NAME"
echo ""
echo "Verify restored resources:"
if [[ -n "$NAMESPACE_FILTER" ]]; then
    echo "  kubectl get all -n $NAMESPACE_FILTER"
else
    echo "  kubectl get namespaces"
    echo "  kubectl get all -A"
fi
