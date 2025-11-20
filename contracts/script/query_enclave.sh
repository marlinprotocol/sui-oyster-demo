#!/bin/bash

# Script to query enclave object details
# Usage: ./query_enclave.sh <enclave_object_id>

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <enclave_object_id>"
    echo "Example: $0 0x123..."
    exit 1
fi

ENCLAVE_ID="$1"

echo "Querying enclave object: $ENCLAVE_ID"
echo ""

# Get full object data
ENCLAVE_DATA=$(sui client object "$ENCLAVE_ID" --json)

# Extract key fields
PK_ARRAY=$(echo "$ENCLAVE_DATA" | jq -r '.content.fields.pk')
CONFIG_VERSION=$(echo "$ENCLAVE_DATA" | jq -r '.content.fields.config_version')
OWNER=$(echo "$ENCLAVE_DATA" | jq -r '.content.fields.owner')

# Convert pk array to hex string
PK_HEX=$(echo "$PK_ARRAY" | jq -r '.[] | tonumber' | xargs printf "%02x")

# Display key fields
echo "=== Enclave Details ==="
echo "Object ID:       $ENCLAVE_ID"
echo "Public Key (hex): $PK_HEX"
echo "Config Version:  $CONFIG_VERSION"
echo "Owner:           $OWNER"
echo ""

# echo "=== Full Object Data ==="
# echo "$ENCLAVE_DATA" | jq '.content.fields'
