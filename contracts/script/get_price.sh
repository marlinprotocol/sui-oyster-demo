#!/bin/bash

# Script to fetch price from enclave and display it
# Usage: ./get_price.sh <enclave_ip> [app_port]

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <enclave_ip> [app_port]"
    echo "Example: $0 192.168.1.100 3000"
    echo ""
    echo "  app_port defaults to 3000 if not specified"
    exit 1
fi

ENCLAVE_IP="$1"
APP_PORT="${2:-3000}"
ENCLAVE_URL="http://${ENCLAVE_IP}:${APP_PORT}"

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

# Extract and display values
PRICE=$(echo "$RESPONSE" | jq -r '.price')
TIMESTAMP_MS=$(echo "$RESPONSE" | jq -r '.timestamp_ms')
SIGNATURE=$(echo "$RESPONSE" | jq -r '.signature')

echo ""
echo "=== SUI Price Data ==="
echo "Price (raw):  $PRICE"
echo "Price (USD):  \$$(echo "scale=6; $PRICE / 1000000" | bc)"
echo "Timestamp ms: $TIMESTAMP_MS"
echo "Date:         $(date -r $(echo "$TIMESTAMP_MS / 1000" | bc) '+%Y-%m-%d %H:%M:%S')"
echo "Signature:    ${SIGNATURE:0:20}...${SIGNATURE: -20}"
echo ""
echo "Full response:"
echo "$RESPONSE" | jq .
