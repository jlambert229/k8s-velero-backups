# Velero Deployment Status

## Current State

**Date:** 2026-02-08  
**Cluster:** talos (1 CP + 2 workers, 2 vCPU / ~3.5GB RAM each)

### ✅ Successfully Deployed via Helm

1. **MinIO** - S3-compatible storage backend
   - Helm release: `minio` (namespace: `velero`)
   - Status: Running (pod healthy)
   - Storage: 50GB NFS PVC
   - Access: Internal only (`minio.velero.svc.cluster.local:9000`)
   - Credentials: velero / velero-secret-key

2. **Velero Controller** - Backup orchestration
   - Helm release: `velero` (namespace: `velero`)
   - Status: Deployed via Helm (pod pending due to resource constraints)
   - Configuration: Manifest backups only (node-agent disabled)

### ⚠️  Resource Constraints

**Issue:** Worker nodes are heavily loaded (53-71% memory usage)

**Running services:**
- Full media stack (Plex, Sonarr, Radarr, qBit, Bazarr, Overseerr, Tautulli, SABnzbd)
- Prometheus + Grafana monitoring
- Vault + External Secrets Operator
- Consul
- VPA (Vertical Pod Autoscaler)
- cert-manager
- Traefik

**Velero status:** Pod cannot schedule (insufficient memory)

## Completion Options

### Option 1: Increase Worker Resources (Recommended)

Increase worker RAM from 4GB to 6GB:

```bash
cd ~/Repos/k8s-deploy
# Edit terraform.tfvars
# worker_memory_mb = 6144

terraform apply
```

Then check Velero status:
```bash
export KUBECONFIG=~/Repos/k8s-deploy/generated/kubeconfig
kubectl get pods -n velero
```

### Option 2: Reduce Cluster Load

Scale down non-essential services temporarily:

```bash
export KUBECONFIG=~/Repos/k8s-deploy/generated/kubeconfig

# Scale down VPA
kubectl scale -n vpa-system deploy --all --replicas=0

# Wait for Velero to schedule
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=velero -n velero --timeout=5m

# Re-enable VPA
kubectl scale -n vpa-system deploy vpa-admission-controller --replicas=1
kubectl scale -n vpa-system deploy vpa-recommender --replicas=1
kubectl scale -n vpa-system deploy vpa-updater --replicas=1
```

### Option 3: Accept Manifest-Only Backups

Velero is already configured. Once the pod runs, it will back up:
- ✅ All Kubernetes manifests (Deployments, Services, ConfigMaps, Secrets)
- ✅ Namespace configurations
- ❌ PVC data (node-agent disabled to save resources)

This still provides cluster-level disaster recovery for resource definitions.

## Verify Deployment

Once Velero pod is running:

```bash
export KUBECONFIG=~/Repos/k8s-deploy/generated/kubeconfig

# Check pod status
kubectl get pods -n velero

# Check backup storage location
kubectl get backupstoragelocation -n velero

# Test backup
kubectl create -f backup-schedules/media-daily.yaml

# Check backups
kubectl get backups -n velero
```

## Current Helm Configuration

```yaml
releases:
  - minio (failed but pod running)
  - velero (deployed, pod pending)

namespace: velero

resources:
  MinIO:
    cpu: 50m / 200m
    memory: 128Mi / 256Mi
  Velero:
    cpu: 25m / 200m
    memory: 128Mi / 256Mi
```

## Next Steps

1. **Choose an option above** to resolve resource constraints
2. **Verify Velero is running:**
   ```bash
   kubectl get pods -n velero -w
   ```
3. **Apply backup schedules:**
   ```bash
   kubectl apply -f backup-schedules/
   ```
4. **Verify backup location:**
   ```bash
   kubectl get backupstoragelocation -n velero
   ```

## Repository

Full deployment code: https://github.com/jlambert229/k8s-velero-backups

**To redeploy from scratch:**
```bash
cd ~/Repos/k8s-velero-backups
./deploy.sh  # Automated deployment (requires sufficient resources)
```
