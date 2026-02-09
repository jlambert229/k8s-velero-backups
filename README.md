## k8s-velero-backups

Cluster-level disaster recovery for Kubernetes using [Velero](https://velero.io/) with MinIO as S3-compatible backend.

**Blog post:** [Kubernetes Cluster Backups with Velero](https://foggyclouds.io/post/k8s-velero-backups/)

## Features

- **Full namespace backups** - All resources (Deployments, Services, PVCs, Secrets, ConfigMaps)
- **Persistent volume snapshots** - Restic for filesystem-level backups
- **Scheduled backups** - Daily/weekly cron-like automation
- **Cross-cluster restore** - Rebuild on new hardware
- **Selective recovery** - Restore one app or the whole cluster
- **Deduplication & compression** - Efficient storage usage
- **MinIO backend** - S3-compatible storage on your NFS

## Prerequisites

- Kubernetes cluster (tested on Talos)
- Helm 3.x
- NFS CSI driver with `nfs-appdata` StorageClass (for MinIO storage)
- `velero` CLI (optional but recommended)

Install Velero CLI:

```bash
# macOS
brew install velero

# Linux
wget https://github.com/vmware-tanzu/velero/releases/download/v1.14.1/velero-v1.14.1-linux-amd64.tar.gz
tar -xvf velero-v1.14.1-linux-amd64.tar.gz
sudo mv velero-v1.14.1-linux-amd64/velero /usr/local/bin/
```

## Quick Start

```bash
# Clone the repo
git clone https://github.com/YOUR-USERNAME/k8s-velero-backups.git
cd k8s-velero-backups

# Deploy Velero + MinIO
./deploy.sh

# Verify deployment
velero backup-location get
velero schedule get
```

## What Gets Deployed

1. **MinIO** - S3-compatible object storage backed by NFS
2. **Velero** - Backup controller and CLI
3. **Node Agent (Restic)** - DaemonSet for PVC filesystem backups
4. **Backup Schedules** - Automated daily/weekly jobs

## Backup Schedules

### media-daily

- **Schedule:** 2am daily
- **Scope:** `media` namespace
- **Retention:** 7 days
- **Includes:** All resources + PVC data

### cluster-weekly

- **Schedule:** 3am Sunday
- **Scope:** All namespaces (except kube-system, kube-public, kube-node-lease)
- **Retention:** 30 days
- **Includes:** All resources + PVC data

## Manual Backups

### Backup entire namespace

```bash
velero backup create media-manual \
    --include-namespaces media \
    --default-volumes-to-fs-backup \
    --wait
```

### Backup single app

```bash
velero backup create sonarr-manual \
    --include-namespaces media \
    --selector app.kubernetes.io/name=sonarr \
    --default-volumes-to-fs-backup \
    --wait
```

### Full cluster backup

```bash
velero backup create cluster-manual \
    --exclude-namespaces kube-system,kube-public,kube-node-lease \
    --default-volumes-to-fs-backup \
    --wait
```

### Check backup status

```bash
velero backup get
velero backup describe media-manual
velero backup logs media-manual
```

## Restore

### Restore entire namespace

```bash
# Interactive restore
./restore.sh media-daily-20260208020000 media

# Or manually
velero restore create media-restore-$(date +%s) \
    --from-backup media-daily-20260208020000 \
    --wait
```

### Restore single app

```bash
# Scale down the app first
kubectl scale -n media deploy/sonarr --replicas=0

# Restore
velero restore create sonarr-restore-$(date +%s) \
    --from-backup media-daily-20260208020000 \
    --include-resources deployment,service,ingress,pvc,secret,configmap \
    --selector app.kubernetes.io/name=sonarr \
    --wait
```

### Disaster recovery (new cluster)

1. Build new cluster (same Kubernetes version recommended)
2. Deploy foundation layer (MetalLB, Traefik, NFS CSI)
3. Deploy Velero (same config, points to existing MinIO/NFS)
4. Restore cluster state:

```bash
velero backup get  # Should show existing backups
velero restore create full-restore-$(date +%s) \
    --from-backup cluster-weekly-20260202030000 \
    --wait
```

## Verify Backups

Test backup integrity:

```bash
./verify-backup.sh media-daily-20260208020000
```

Checks:
- Backup completed successfully
- No errors in backup process
- Volume backups completed
- Displays backup size and details

## Configuration

### minio-values.yaml

MinIO S3-compatible storage:

- **Storage:** 50 GB PVC on `nfs-appdata` StorageClass
- **Bucket:** `velero` (auto-created)
- **Credentials:** `velero` / `velero-secret-key`
- **Console:** http://minio-console.media.lan

### velero-values.yaml

Velero backup controller:

- **Uploader:** Restic (filesystem-level PVC backups)
- **Backup location:** MinIO at `http://minio.velero.svc.cluster.local:9000`
- **Default:** Backup all volumes to Restic
- **Timeout:** 4h for large volumes

### Backup Schedules

Edit `backup-schedules/*.yaml` to customize:

- **Schedule:** Cron syntax (`0 2 * * *`)
- **Namespaces:** Include/exclude specific namespaces
- **TTL:** Retention period (168h = 7 days)

Apply changes:

```bash
kubectl apply -f backup-schedules/
```

## Troubleshooting

### Backup stuck in Progress

Check node agent logs:

```bash
kubectl logs -n velero -l name=node-agent
```

**Common causes:**
- Large volumes taking time (check timeout in `velero-values.yaml`)
- Node agent can't access PVC

### Restore fails with "Already Exists"

Delete resources first:

```bash
kubectl delete namespace media
velero restore create media-restore-$(date +%s) --from-backup <backup> --wait
```

### MinIO connection refused

Verify MinIO is running:

```bash
kubectl get pods -n velero
kubectl logs -n velero -l app=minio
```

Test connectivity from Velero pod:

```bash
kubectl exec -n velero deploy/velero -- wget -O- http://minio.velero.svc.cluster.local:9000
```

### Backup storage location unavailable

Check credentials and MinIO access:

```bash
velero backup-location describe default
kubectl logs -n velero -l app.kubernetes.io/name=velero | grep -i minio
```

Verify secret:

```bash
kubectl get secret velero-credentials -n velero -o yaml
```

## Resource Usage

Tested on 2-worker cluster (2 vCPU, 4 GB RAM per worker):

- **Velero server:** 50 MB RAM, <1% CPU (idle)
- **Node agent (per node):** 100 MB RAM, <5% CPU (during backup)
- **MinIO:** 200 MB RAM, <5% CPU

**Backup times:**
- Media namespace (8 apps, 40 GB PVCs): ~15 minutes
- Full cluster (3 namespaces, 60 GB total): ~25 minutes

**Storage:**
- Daily media backups: ~8 GB each (compressed)
- 7-day retention: ~56 GB
- Weekly full cluster: ~15 GB each
- 30-day retention: ~120 GB total

Provision 200 GB on your NAS for Velero backups.

## Teardown

```bash
helm uninstall velero -n velero
helm uninstall minio -n velero
kubectl delete namespace velero
```

⚠️ **Warning:** This does NOT delete backup data in MinIO storage. Backups remain on your NFS share.

## References

- [Velero Documentation](https://velero.io/docs/)
- [Velero Helm Chart](https://github.com/vmware-tanzu/helm-charts/tree/main/charts/velero)
- [MinIO Helm Chart](https://github.com/minio/minio/tree/master/helm/minio)
- [Restic Integration](https://velero.io/docs/main/file-system-backup/)
- [Blog post: Kubernetes Cluster Backups](https://foggyclouds.io/post/k8s-velero-backups/)

## License

MIT
