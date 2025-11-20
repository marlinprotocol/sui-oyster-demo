#!/bin/bash

# Script to fetch price from enclave and update it on-chain
# Usage: ./update_price.sh <enclave_ip> <package_id> <oracle_id> <enclave_id>

set -e

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Usage: $0 <enclave_ip> <package_id> <oracle_id> <enclave_id>"
    echo "Example: $0 192.168.1.100 0x123... 0x456... 0x789..."
    exit 1
fi

ENCLAVE_IP="$1"
PACKAGE_ID="$2"
ORACLE_ID="$3"
ENCLAVE_ID="$4"

ENCLAVE_URL="http://${ENCLAVE_IP}:3000"

echo "Fetching price from enclave at $ENCLAVE_URL/price"

# Fetch price from enclave
RESPONSE=$(curl -s "$ENCLAVE_URL/price")

if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch price from enclave"
    exit 1
fi

# Check if response is valid JSON
if ! echo "$RESPONSE" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response from enclave"
    echo "Response: $RESPONSE"
    exit 1
fi

# Extract values
PRICE=$(echo "$RESPONSE" | jq -r '.price')
TIMESTAMP_MS=$(echo "$RESPONSE" | jq -r '.timestamp_ms')
SIGNATURE=$(echo "$RESPONSE" | jq -r '.signature')

echo "Price (raw):  $PRICE"
echo "Price (USD):  \$$(echo "scale=6; $PRICE / 1000000" | bc)"
echo "Timestamp ms: $TIMESTAMP_MS"
echo "Signature:    ${SIGNATURE:0:20}...${SIGNATURE: -20}"
echo ""

# Convert hex signature to vector format for Move
SIG_VECTOR=$(python3 -c "
sig = '$SIGNATURE'
bytes = [int(sig[i:i+2], 16) for i in range(0, len(sig), 2)]
print('[' + ','.join(map(str, bytes)) + ']')
")

echo "Submitting price update to blockchain..."

# Submit the price update
sui client call \
    --package "$PACKAGE_ID" \
    --module oyster_demo \
    --function update_sui_price \
    --args "$ORACLE_ID" "$ENCLAVE_ID" "$PRICE" "$TIMESTAMP_MS" "$SIG_VECTOR" \
    --gas-budget 10000000

echo ""
echo "Price update completed successfully!"
