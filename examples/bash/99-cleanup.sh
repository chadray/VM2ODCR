#!/usr/bin/env bash
# Cleanup: remove everything created by the walkthrough.
set -euo pipefail
source "$(dirname "$0")/00-vars.sh"

az group delete -n "$RG" --yes --no-wait
echo "Delete queued for resource group $RG (VM + CRG + reservation)."
