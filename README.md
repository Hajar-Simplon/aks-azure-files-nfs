# MongoDB Persistence on AKS with Azure Files NFS

This project deploys MongoDB on Azure Kubernetes Service (AKS) with persistent storage dynamically provisioned from a private Premium Azure Files NFS storage account.

MongoDB data is mounted at `/data/db` and remains available when the MongoDB pod is deleted and replaced.

## Architecture

```text
MongoDB pod (/data/db)
        |
        v
PVC mongodb-data (RWX)
        |
        v
StorageClass azurefile-csi-nfs
        |
        v
Azure Files CSI driver (file.csi.azure.com)
        |
        v
Premium Azure Files NFS share
        |
        v
Private endpoint + private DNS + AKS VNet
```

## Implemented features

- Existing AKS cluster reused and validated.
- Native Azure Files CSI driver verified.
- Premium `FileStorage` account using `Premium_LRS`.
- Private endpoint deployed in the AKS node subnet.
- Private DNS zone linked to the AKS VNet.
- Public network access to the storage account disabled.
- Custom NFS StorageClass with dynamic provisioning.
- `allowVolumeExpansion: true` enabled.
- `Retain` reclaim policy used to protect stored data.
- Separate `10Gi` provisioning test PVC.
- MongoDB data persisted through pod deletion and replacement.
- Local MongoDB credentials excluded from Git.

## Repository structure

```text
.
├── docs/
│   ├── images/
│   └── project-documentation.md
├── kubernetes/
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   ├── mongodb.env.example
│   ├── namespace.yaml
│   ├── pvc-mongodb.yaml
│   ├── service.yaml
│   └── storageclass.yaml
├── scripts/
│   ├── 01-check-prerequisites.sh
│   └── 02-configure-permissions.sh
└── tests/
    ├── pod-test.yaml
    └── pvc-test.yaml
```

## Prerequisites

- An Azure subscription and authenticated Azure CLI.
- Access to the existing AKS cluster.
- `kubectl` configured for the cluster.
- A Premium Azure Files `FileStorage` account.
- A local `kubernetes/mongodb.env` file created from the example.

Run the read-only validation script:

```bash
bash scripts/01-check-prerequisites.sh
```

## Local MongoDB secret

Create the ignored local environment file:

```bash
cp kubernetes/mongodb.env.example kubernetes/mongodb.env
```

Replace the example password before deployment. Never commit `kubernetes/mongodb.env`.

## Deploy MongoDB

```bash
kubectl apply -k kubernetes/
kubectl rollout status deployment/mongodb -n mongodb --timeout=180s
kubectl get pvc,pods -n mongodb
```

Verify that Azure Files is mounted at MongoDB's data directory:

```bash
kubectl exec -n mongodb deployment/mongodb -- df -h /data/db
```

## Test dynamic provisioning

```bash
kubectl apply -f tests/pvc-test.yaml
kubectl apply -f tests/pod-test.yaml
kubectl get pvc,pods -n mongodb
```

The PVC requests `10Gi`, but Premium Azure Files provisions a minimum capacity of `100Gi`.

## Persistence proof

The validation performed for this project was:

1. Insert a document into the `persistence_demo` MongoDB database.
2. Record the MongoDB pod name and UID.
3. Delete only the MongoDB pod.
4. Wait for the Deployment to create a replacement pod.
5. Confirm that the replacement has a different name and UID.
6. Read the same MongoDB document with the same identifier and timestamp.

Verified document identifier:

```text
aks-nfs-persistence-proof
```

## Security

- Storage public network access is disabled.
- Azure Files resolves to private IP `10.224.0.5` from AKS.
- The private endpoint targets the `file` subresource.
- Credentials are supplied through an ignored local environment file.
- The AKS control-plane identity has a scoped storage role.
- The user network role is scoped to the AKS VNet.

## Important cleanup warning

**The `hmezouarRG` Resource Group is permanent and must never be deleted.**

Cleanup must target only individually verified project resources. Because the StorageClass uses `reclaimPolicy: Retain`, deleting a PVC does not automatically delete the underlying Azure File Share.

## Documentation

See [the complete project documentation](docs/project-documentation.md) for the implementation details, observed results, troubleshooting and persistence evidence.

