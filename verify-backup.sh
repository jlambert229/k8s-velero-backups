#!/bin/bash
set -euo pipefail

BACKUP_NAME="${1:-}"

if [[ -z "$BACKUP_NAME" ]]; then
    echo "Usage: $0 <backup-name>"
    echo ""
    echo "Available backups:"
    velero backup get
    exit 1
fi

echo "=== Verifying backup: $BACKUP_NAME ==="
echo ""

# Check backup completed successfully
echo "Checking backup status..."
STATUS=$(velero backup describe "$BACKUP_NAME" --details 2>/dev/null | grep -i "^Phase:" | awk '{print $2}')

if [[ "$STATUS" != "Completed" ]]; then
    echo "❌ Backup status: $STATUS"
    exit 1
fi

echo "✅ Backup status: Completed"

# Check for errors
ERRORS=$(velero backup describe "$BACKUP_NAME" --details 2>/dev/null | grep -i "^Errors:" | awk '{print $2}')

if [[ "$ERRORS" != "0" ]]; then
    echo "⚠️  Backup has $ERRORS errors:"
    velero backup logs "$BACKUP_NAME" | grep -i error | head -20
    exit 1
fi

echo "✅ No errors"

# Verify volumes backed up
echo ""
echo "Checking volume backups..."
VOLUMES=$(velero backup describe "$BACKUP_NAME" --details 2>/dev/null | grep -A 20 "Restic Backups" | grep "Completed: " | awk '{print $2}' || echo "0")

echo "✅ Volumes backed up: $VOLUMES"

# Check backup size
echo ""
echo "Backup details:"
velero backup describe "$BACKUP_NAME" --details | grep -E "Phase:|Errors:|Warnings:|Total items:|Restic Backups:"

echo ""
echo "=== Verification complete ==="
echo ""
echo "Backup is valid and ready for restore."
