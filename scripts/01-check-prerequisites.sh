#!/usr/bin/env bash

set -euo pipefail

PROJECT_RESOURCE_GROUP="${PROJECT_RESOURCE_GROUP:-hmezouarRG}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-velerolab-aks-sby6ie}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-sthmezouarnfs}"
EXPECTED_STORAGE_SKU="Premium_LRS"
EXPECTED_STORAGE_KIND="FileStorage"
EXPECTED_CSI_DRIVER="file.csi.azure.com"

info() {
  printf '[INFO] %s\n' "$1"
}

success() {
  printf '[OK] %s\n' "$1"
}

fail() {
  printf '[ERROR] %s\n' "$1" >&2
  exit 1
}

command -v az >/dev/null 2>&1 || fail "Azure CLI (az) is not installed or not in PATH."
command -v kubectl >/dev/null 2>&1 || fail "kubectl is not installed or not in PATH."

success "Azure CLI and kubectl are available."

SIGNED_IN_USER=$(az account show --query user.name --output tsv 2>/dev/null) || \
  fail "Azure CLI is not authenticated. Run: az login"

SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
info "Signed in as: ${SIGNED_IN_USER}"
info "Active subscription: ${SUBSCRIPTION_NAME}"

RESOURCE_GROUP_EXISTS=$(az group exists --name "$PROJECT_RESOURCE_GROUP")
[[ "$RESOURCE_GROUP_EXISTS" == "true" ]] || \
  fail "Protected Resource Group ${PROJECT_RESOURCE_GROUP} was not found."

success "Protected Resource Group ${PROJECT_RESOURCE_GROUP} exists. This script never deletes it."

AKS_STATE=$(az aks show \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --query provisioningState \
  --output tsv 2>/dev/null) || \
  fail "AKS cluster ${AKS_CLUSTER_NAME} was not found in ${PROJECT_RESOURCE_GROUP}."

[[ "$AKS_STATE" == "Succeeded" ]] || \
  fail "AKS provisioning state is ${AKS_STATE}, expected Succeeded."

success "AKS cluster ${AKS_CLUSTER_NAME} is provisioned successfully."

kubectl cluster-info >/dev/null 2>&1 || \
  fail "kubectl cannot reach the current cluster. Refresh AKS credentials first."

NOT_READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {count++} END {print count+0}')
[[ "$NOT_READY_NODES" -eq 0 ]] || fail "At least one Kubernetes node is not Ready."

success "kubectl can reach the cluster and all nodes are Ready."

kubectl get csidriver "$EXPECTED_CSI_DRIVER" >/dev/null 2>&1 || \
  fail "CSI driver ${EXPECTED_CSI_DRIVER} is not registered."

success "CSI driver ${EXPECTED_CSI_DRIVER} is registered."

STORAGE_KIND=$(az storage account show \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT_NAME" \
  --query 'kind' \
  --output tsv 2>/dev/null) || \
  fail "Storage account ${STORAGE_ACCOUNT_NAME} was not found."

STORAGE_SKU=$(az storage account show \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT_NAME" \
  --query 'sku.name' \
  --output tsv)

PUBLIC_ACCESS=$(az storage account show \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT_NAME" \
  --query 'publicNetworkAccess' \
  --output tsv)

[[ "$STORAGE_KIND" == "$EXPECTED_STORAGE_KIND" ]] || \
  fail "Storage kind is ${STORAGE_KIND}, expected ${EXPECTED_STORAGE_KIND}."

[[ "$STORAGE_SKU" == "$EXPECTED_STORAGE_SKU" ]] || \
  fail "Storage SKU is ${STORAGE_SKU}, expected ${EXPECTED_STORAGE_SKU}."

[[ "$PUBLIC_ACCESS" == "Disabled" ]] || \
  fail "Storage public network access is ${PUBLIC_ACCESS}, expected Disabled."

success "Storage account ${STORAGE_ACCOUNT_NAME} is ${STORAGE_KIND}/${STORAGE_SKU} with public access disabled."

PRIVATE_ENDPOINT_COUNT=$(az network private-endpoint list \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --query "[?name=='pe-sthmezouarnfs-file' && privateLinkServiceConnections[0].privateLinkServiceConnectionState.status=='Approved'] | length(@)" \
  --output tsv)

[[ "$PRIVATE_ENDPOINT_COUNT" -eq 1 ]] || \
  fail "Approved private endpoint pe-sthmezouarnfs-file was not found."

success "The Azure Files private endpoint is present and approved."

printf '\nAll prerequisite checks passed. No resources were changed.\n'
