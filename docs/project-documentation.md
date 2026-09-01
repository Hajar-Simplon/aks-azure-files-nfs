# Persistent MongoDB Storage on AKS with Azure Files NFS

## 1. Project objective

This project provides persistent storage for MongoDB running in Azure Kubernetes Service (AKS). MongoDB data is stored in a Premium Azure Files NFS share mounted at `/data/db`.

Kubernetes dynamically provisions the share through the AKS-native Azure Files CSI driver, `file.csi.azure.com`. Storage traffic uses a private endpoint and private DNS, while public network access to the storage account is disabled.

## 2. Final result

- The Azure Files CSI driver is installed and operational.
- The `azurefile-csi-nfs` StorageClass uses Premium Azure Files with NFS.
- A `10Gi` test PVC triggered dynamic provisioning of an NFS share.
- Azure provisioned `100Gi`, the minimum capacity for a Premium Azure Files share.
- The MongoDB PVC `mongodb-data` is `Bound` with `ReadWriteMany` access.
- MongoDB mounts the share at `/data/db`.
- A MongoDB document survived deletion and replacement of the pod.
- The storage account's public network access is disabled.

## 3. Resources

| Resource | Name | Purpose |
|---|---|---|
| Permanent Resource Group | `hmezouarRG` | Contains project resources and must never be deleted |
| AKS cluster | `velerolab-aks-sby6ie` | Runs MongoDB and the CSI driver |
| AKS VNet | `aks-vnet-55422649` | Private network used by AKS |
| AKS subnet | `aks-subnet` (`10.224.0.0/16`) | Contains the AKS nodes and private endpoint |
| Storage account | `sthmezouarnfs` | Hosts Premium Azure Files NFS shares |
| Private endpoint | `pe-sthmezouarnfs-file` | Provides private access to Azure Files |
| Private endpoint IP | `10.224.0.5` | Private address of the Azure Files endpoint |
| Private DNS zone | `privatelink.file.core.windows.net` | Resolves Azure Files to its private IP |
| DNS VNet link | `link-aks-vnet-azurefiles` | Makes private DNS available to AKS |
| Kubernetes namespace | `mongodb` | Isolates the application resources |

The `hmezouarRG` Resource Group is permanent. Cleanup operations must target individually verified resources and must never delete this Resource Group.

## 4. Architecture

```text
MongoDB container (/data/db)
          |
          v
PVC mongodb-data (RWX, 100Gi)
          |
          v
StorageClass azurefile-csi-nfs
          |
          v
CSI driver file.csi.azure.com
          |
          v
Premium Azure Files NFS share
          |
          v
Private endpoint 10.224.0.5
          |
          v
aks-subnet / aks-vnet-55422649
```

## 5. AKS and CSI validation

The cluster and CSI driver were verified with:

```bash
kubectl get nodes
kubectl get csidrivers
kubectl get pods -n kube-system
```

Observed results:

- the AKS node was `Ready`;
- `file.csi.azure.com` was registered;
- `csi-azurefile-controller` and `csi-azurefile-node` pods were `Running`.

Screenshot placeholder: `docs/images/01-aks-csi-driver.png`

## 6. Azure Files storage account

The `sthmezouarnfs` storage account was created with:

| Setting | Value |
|---|---|
| Primary service | Azure Files |
| Region | West Europe |
| Account kind | FileStorage |
| Performance | Premium SSD |
| Redundancy | Premium LRS |
| Billing model | Provisioned v1 |
| Share protocol | NFS |

The existing `sthmezouarfiles` account was not reused because it is a Standard `StorageV2` account and already contains the unrelated `company-data` share.

Screenshot placeholder: `docs/images/02-storage-account-overview.png`

## 7. Private networking and DNS

The `pe-sthmezouarnfs-file` private endpoint targets the storage account's `file` subresource. It is deployed in `aks-subnet` and uses private IP `10.224.0.5`.

The `privatelink.file.core.windows.net` private DNS zone is linked to the AKS VNet and contains:

```text
sthmezouarnfs.privatelink.file.core.windows.net -> 10.224.0.5
```

A DNS test from an AKS pod returned:

```text
sthmezouarnfs.file.core.windows.net
  canonical name = sthmezouarnfs.privatelink.file.core.windows.net
  address = 10.224.0.5
```

Public access was then disabled:

```text
PublicNetworkAccess: Disabled
DefaultAction: Deny
```

Screenshot placeholders:

- `docs/images/03-private-endpoint.png`
- `docs/images/04-private-dns.png`
- `docs/images/05-dns-test-from-aks.png`
- `docs/images/06-public-access-disabled.png`

## 8. NFS StorageClass

The StorageClass is defined in `kubernetes/storageclass.yaml`. Its principal settings are:

```yaml
provisioner: file.csi.azure.com
parameters:
  resourceGroup: hmezouarRG
  storageAccount: sthmezouarnfs
  skuName: Premium_LRS
  protocol: nfs
reclaimPolicy: Retain
allowVolumeExpansion: true
```

`Retain` protects the underlying storage from automatic deletion when the PVC is removed. `allowVolumeExpansion` allows online expansion testing.

## 9. Dynamic provisioning test

The test claim in `tests/pvc-test.yaml` requests:

```text
StorageClass: azurefile-csi-nfs
Requested capacity: 10Gi
Access mode: ReadWriteMany
```

The CSI driver automatically created:

```text
PVC: azurefiles-nfs-test
State: Bound
PV: pvc-079a5a66-95e3-45b7-9288-52ced90df697
Azure share: pvcn-079a5a66-95e3-45b7-9288-52ced90df697
Actual capacity: 100Gi
Protocol: NFS
```

Although Kubernetes accepted a `10Gi` request, Azure Files Premium provisioned its minimum capacity of `100Gi`.

The pod in `tests/pod-test.yaml` mounted the claim at `/mnt/azure`. The `proof.txt` file remained available after deleting and recreating the pod.

Screenshot placeholders:

- `docs/images/07-pvc-test-bound.png`
- `docs/images/08-nfs-share-created.png`
- `docs/images/09-test-file-persistence.png`

## 10. MongoDB deployment

The manifests were deployed with:

```bash
kubectl apply -k kubernetes/
```

Kustomize deployed:

- the `mongodb` namespace;
- the `azurefile-csi-nfs` StorageClass;
- the `mongodb-data` PVC;
- the `mongodb` Deployment;
- the `mongodb` Service;
- a generated Kubernetes Secret.

The MongoDB claim produced:

```text
PVC: mongodb-data
State: Bound
Capacity: 100Gi
Access mode: RWX
StorageClass: azurefile-csi-nfs
PV: pvc-c0a0fd1e-c200-4aff-8361-fd08d35bf19d
```

The required mount check was performed with:

```bash
kubectl exec -n mongodb deployment/mongodb -- df -h /data/db
```

Result:

```text
sthmezouarnfs.file.core.windows.net:/sthmezouarnfs/pvcn-c0a0fd1e-c200-4aff-8361-fd08d35bf19d
100G  300M  100G  1%  /data/db
```

Screenshot placeholders:

- `docs/images/10-mongodb-pvc-bound.png`
- `docs/images/11-mongodb-running.png`
- `docs/images/12-data-db-mount.png`

## 11. MongoDB persistence proof

The following document was inserted into the `persistence_demo` database:

```javascript
{
  _id: "aks-nfs-persistence-proof",
  message: "This document must survive pod deletion",
  createdAt: ISODate("2026-09-01T13:50:00.189Z")
}
```

Pod before deletion:

```text
Name: mongodb-54449bb667-xspnx
UID: bcddcfdf-7ae5-4680-9dde-053f108f31fe
```

Pod created by the Deployment afterward:

```text
Name: mongodb-54449bb667-2xrsd
UID: c83b6cd8-b725-4d2c-947d-3d2525ffdfb8
```

The changed name and UID prove that Kubernetes created a new pod. The new pod returned the same document with the same identifier and creation timestamp.

**Conclusion: MongoDB data is persisted in Azure Files and is independent of the pod lifecycle.**

Screenshot placeholders:

- `docs/images/13-document-before-deletion.png`
- `docs/images/14-old-pod-deleted.png`
- `docs/images/15-new-pod-and-document.png`

## 12. Mounting issue and resolution

The initial NFS mount failed with:

```text
mount.nfs: access denied by server
```

The private endpoint, DNS, NFS share and network path were correct. However, storage accounts created through the Azure Portal enable the separate `Require encryption in transit for NFS` setting by default.

The CSI driver used the standard NFS client rather than the AZNFS TLS helper. The setting was therefore explicitly disabled for this lab:

```bash
az storage account file-service-properties update \
  --resource-group "hmezouarRG" \
  --account-name "sthmezouarnfs" \
  --nfs-eit \
  --require-nfs-encryption-in-transit false
```

The mount succeeded after the test pod was recreated.

Network security remains enforced through the private endpoint and disabled public access. For production, AZNFS and NFS encryption in transit should be evaluated.

## 13. Security considerations and limitations

- Public network access to `sthmezouarnfs` is disabled.
- NFS access is primarily authorized at the network level.
- The password currently present in `kustomization.yaml` is a lab value and must be replaced before real use.
- MongoDB runs with one replica. Independent MongoDB instances must not write directly into the same data directory without a correctly configured replica set.
- `ReadWriteMany` describes an Azure Files capability; it does not automatically make MongoDB safe for multiple writers.
- Subscription identifiers, passwords, access keys, connection strings and tokens must be hidden in screenshots.

## 14. Cleanup warning

The `hmezouarRG` Resource Group must never be deleted.

Cleanup must be performed one resource at a time after verifying its exact identity and dependencies. Because the StorageClass uses `reclaimPolicy: Retain`, deleting a PVC does not automatically delete its PV or Azure File Share. This protects data from accidental loss, but retained shares may continue to incur costs.
