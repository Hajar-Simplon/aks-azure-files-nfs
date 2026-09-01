#!/usr/bin/env bash

set -euo pipefail

PROJECT_RESOURCE_GROUP="${PROJECT_RESOURCE_GROUP:-hmezouarRG}"
AKS_CLUSTER_NAME="${AKS_CLUSTER_NAME:-velerolab-aks-sby6ie}"
AKS_NODE_RESOURCE_GROUP="${AKS_NODE_RESOURCE_GROUP:-MC_hmezouarRG_velerolab-aks-sby6ie_westeurope}"
AKS_VNET_NAME="${AKS_VNET_NAME:-aks-vnet-55422649}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-sthmezouarnfs}"

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

command -v az >/dev/null 2>&1 || fail "Azure CLI (az) is not available."
az account show >/dev/null 2>&1 || fail "Azure CLI is not authenticated. Run: az login"

SIGNED_USER_ID=$(az ad signed-in-user show --query id --output tsv)

AKS_VNET_ID=$(az network vnet show \
  --resource-group "$AKS_NODE_RESOURCE_GROUP" \
  --name "$AKS_VNET_NAME" \
  --query id \
  --output tsv 2>/dev/null) || fail "AKS VNet ${AKS_VNET_NAME} was not found."

STORAGE_ID=$(az storage account show \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT_NAME" \
  --query id \
  --output tsv 2>/dev/null) || fail "Storage account ${STORAGE_ACCOUNT_NAME} was not found."

CONTROL_PLANE_ID=$(az aks show \
  --resource-group "$PROJECT_RESOURCE_GROUP" \
  --name "$AKS_CLUSTER_NAME" \
  --query identity.principalId \
  --output tsv 2>/dev/null) || fail "AKS control-plane identity was not found."

USER_NETWORK_ROLE_COUNT=$(az role assignment list \
  --assignee "$SIGNED_USER_ID" \
  --scope "$AKS_VNET_ID" \
  --query "[?roleDefinitionName=='Network Contributor'] | length(@)" \
  --output tsv)

if [[ "$USER_NETWORK_ROLE_COUNT" -eq 0 ]]; then
  info "Assigning Network Contributor to the signed-in user on ${AKS_VNET_NAME}."
  az role assignment create \
    --assignee-object-id "$SIGNED_USER_ID" \
    --assignee-principal-type User \
    --role "Network Contributor" \
    --scope "$AKS_VNET_ID" \
    --output none
  success "Network Contributor was assigned on the AKS VNet."
else
  success "The signed-in user already has Network Contributor on the AKS VNet."
fi

CSI_STORAGE_ROLE_COUNT=$(az role assignment list \
  --assignee "$CONTROL_PLANE_ID" \
  --scope "$STORAGE_ID" \
  --query "[?roleDefinitionName=='Storage Account Contributor'] | length(@)" \
  --output tsv)

if [[ "$CSI_STORAGE_ROLE_COUNT" -eq 0 ]]; then
  info "Assigning Storage Account Contributor to the AKS control-plane identity."
  az role assignment create \
    --assignee-object-id "$CONTROL_PLANE_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Account Contributor" \
    --scope "$STORAGE_ID" \
    --output none
  success "Storage Account Contributor was assigned on ${STORAGE_ACCOUNT_NAME}."
else
  success "The AKS control-plane identity already has Storage Account Contributor on ${STORAGE_ACCOUNT_NAME}."
fi

printf '\nRequired scoped role assignments are present. No broader roles were granted.\n'
