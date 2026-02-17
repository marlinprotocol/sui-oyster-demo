#!/bin/bash

# Look up an enclave's PCR values from the on-chain registry.
# Fetches the enclave's public key, then queries the registry for its PCRs.
#
# Usage: ./get_registry_pcrs.sh <registry_id> <enclave_ip> [app_port]
# Uses the RPC URL from your active `sui client` environment.

set -e

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "Usage: $0 <registry_id> <enclave_ip> [app_port]"
    echo "Example: $0 0x7ebc... 100.26.111.45 3000"
    echo ""
    echo "  app_port defaults to 3000 if not specified"
    echo "  RPC URL is auto-detected from your active sui client environment"
    exit 1
fi

REGISTRY_ID="$1"
ENCLAVE_IP="$2"
APP_PORT="${3:-3000}"

# Auto-detect RPC URL from active sui client environment
RPC_URL=$(sui client envs --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
envs, active_alias = data[0], data[1]
match = [e['rpc'] for e in envs if e['alias'] == active_alias]
print(match[0] if match else '')
" 2>/dev/null)

if [ -z "$RPC_URL" ]; then
    echo "Error: Could not detect RPC URL from sui client. Is sui client configured?"
    exit 1
fi

echo "Using RPC: $RPC_URL"

ENCLAVE_URL="http://${ENCLAVE_IP}:${APP_PORT}"

# Step 1: Fetch the enclave's public key
echo "Fetching public key from enclave at $ENCLAVE_URL/public-key"
PK_RESPONSE=$(curl -s "$ENCLAVE_URL/public-key")
PK_HEX=$(echo "$PK_RESPONSE" | jq -r '.public_key')

if [ -z "$PK_HEX" ] || [ "$PK_HEX" = "null" ]; then
    echo "Error: Failed to fetch public key from enclave"
    echo "Response: $PK_RESPONSE"
    exit 1
fi

echo "Public key: $PK_HEX (${#PK_HEX} hex chars = $(( ${#PK_HEX} / 2 )) bytes)"

# Step 2: Query the registry's dynamic table field using the public key
# The Registry object has a Table<vector<u8>, Pcrs> field.
# We query the dynamic field where the key is the public key bytes.

# Get the Registry object to find the table's inner ID
REGISTRY_OBJ=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"jsonrpc\": \"2.0\",
        \"id\": 1,
        \"method\": \"sui_getObject\",
        \"params\": [
            \"$REGISTRY_ID\",
            { \"showContent\": true }
        ]
    }")

TABLE_ID=$(echo "$REGISTRY_OBJ" | jq -r '.result.data.content.fields.enclaves.fields.id.id')

if [ -z "$TABLE_ID" ] || [ "$TABLE_ID" = "null" ]; then
    echo "Error: Could not find enclaves table in registry object"
    echo "Response: $REGISTRY_OBJ"
    exit 1
fi

echo "Registry table ID: $TABLE_ID"

# Convert hex public key to BCS-encoded vector<u8> for the dynamic field lookup
# BCS encoding of vector<u8>: ULEB128 length prefix + raw bytes
PK_BYTES_LEN=$(( ${#PK_HEX} / 2 ))
PK_LEN_HEX=$(printf '%02x' $PK_BYTES_LEN)
BCS_KEY="${PK_LEN_HEX}${PK_HEX}"

# Query the dynamic field
FIELD_RESULT=$(curl -s -X POST "$RPC_URL" \
    -H "Content-Type: application/json" \
    -d "{
        \"jsonrpc\": \"2.0\",
        \"id\": 1,
        \"method\": \"suix_getDynamicFieldObject\",
        \"params\": [
            \"$TABLE_ID\",
            {
                \"type\": \"vector<u8>\",
                \"value\": $(python3 -c "print([int('$PK_HEX'[i:i+2], 16) for i in range(0, len('$PK_HEX'), 2)])")
            }
        ]
    }")

# Check for errors or missing data
ERROR=$(echo "$FIELD_RESULT" | jq -r '.error.message // .result.error.message // empty')
if [ -n "$ERROR" ]; then
    echo ""
    echo "Enclave public key is NOT registered in the registry."
    echo "Error: $ERROR"
    exit 1
fi

# Check if the result exists (key not found returns error, not empty result)
DATA_EXISTS=$(echo "$FIELD_RESULT" | jq -r '.result.data // empty')
if [ -z "$DATA_EXISTS" ]; then
    echo ""
    echo "Enclave public key is NOT registered in the registry."
    echo "Dynamic field not found for this public key."
    exit 1
fi

# Extract PCR values from the dynamic field
# The value is a Pcrs struct with fields 0, 1, 2, 3 (mapped to pcr0, pcr1, pcr2, pcr16)
VALUE_FIELDS=$(echo "$FIELD_RESULT" | jq '.result.data.content.fields.value.fields')

if [ -z "$VALUE_FIELDS" ] || [ "$VALUE_FIELDS" = "null" ]; then
    echo "Error: Could not parse PCR values from registry"
    echo "Full response:"
    echo "$FIELD_RESULT" | jq .
    exit 1
fi

# Sui stores the positional fields as named fields in JSON
# For a struct Pcrs(vector<u8>, vector<u8>, vector<u8>, vector<u8>),
# Sui names them pos0, pos1, pos2, pos3
PCR0_ARRAY=$(echo "$VALUE_FIELDS" | jq '.pos0')
PCR1_ARRAY=$(echo "$VALUE_FIELDS" | jq '.pos1')
PCR2_ARRAY=$(echo "$VALUE_FIELDS" | jq '.pos2')
PCR16_ARRAY=$(echo "$VALUE_FIELDS" | jq '.pos3')

# Debug: check if any arrays are null
if [ "$PCR0_ARRAY" = "null" ] || [ "$PCR1_ARRAY" = "null" ] || [ "$PCR2_ARRAY" = "null" ] || [ "$PCR16_ARRAY" = "null" ]; then
    echo "Error: One or more PCR arrays are null"
    echo "VALUE_FIELDS structure:"
    echo "$VALUE_FIELDS" | jq .
    exit 1
fi

# Convert arrays to hex
to_hex() {
    python3 -c "
import json, sys
arr = json.loads('''$1''')
if arr is None or arr == 'null':
    print('Error: null array')
    sys.exit(1)
print(''.join(f'{b:02x}' for b in arr))
"
}

PCR0_HEX=$(to_hex "$PCR0_ARRAY")
PCR1_HEX=$(to_hex "$PCR1_ARRAY")
PCR2_HEX=$(to_hex "$PCR2_ARRAY")
PCR16_HEX=$(to_hex "$PCR16_ARRAY")

echo ""
echo "=== Enclave PCR Values ==="
echo "PCR0:  $PCR0_HEX"
echo "PCR1:  $PCR1_HEX"
echo "PCR2:  $PCR2_HEX"
echo "PCR16: $PCR16_HEX"
echo ""
echo ""
echo "Use these values with update_expected_pcrs:"
echo ""
echo "sui client call \\"
echo "    --package <DEMO_PACKAGE_ID> \\"
echo "    --module oyster_demo \\"
echo "    --function update_expected_pcrs \\"
echo "    --args <PRICE_ORACLE_ID> <ADMIN_CAP_ID> 0x${PCR0_HEX} 0x${PCR1_HEX} 0x${PCR2_HEX} 0x${PCR16_HEX} \\"
echo "    --gas-budget 10000000"
