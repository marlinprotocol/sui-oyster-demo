#!/bin/bash

# Script to initialize the price oracle on-chain
# Usage: ./initialize_oracle.sh <package_id>

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <package_id>"
    echo "Example: $0 0x123..."
    exit 1
fi

PACKAGE_ID="$1"

echo "Initializing price oracle..."
echo "Package ID: $PACKAGE_ID"
echo ""

# Call initialize_oracle to create and share the oracle
sui client call \
    --package "$PACKAGE_ID" \
    --module oyster_demo \
    --function initialize_oracle \
    --gas-budget 10000000

echo ""
echo "Oracle initialized successfully!"
echo "Look for the new shared PriceOracle object in the output above."
echo "Save the Oracle Object ID for future price updates."
