#!/bin/bash

# Register an enclave in the shared enclave registry.
# Fetches attestation from the enclave, verifies it on-chain, and stores
# the public key + PCR values in the registry table.
#
# Usage: ./register_enclave.sh <package_id> <registry_id> <enclave_IP>

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <package_id> <registry_id> <enclave_IP>"
    echo "Example: $0 0x872... 0x86f... 100.26.111.45"
    exit 1
fi

PACKAGE_ID=$1
REGISTRY_ID=$2
ENCLAVE_URL=$3

echo 'fetching attestation'
# Fetch attestation and store the hex
ATTESTATION_HEX=$(curl -s http://$ENCLAVE_URL:1301/attestation/hex)

echo "got attestation, length=${#ATTESTATION_HEX}"

if [ ${#ATTESTATION_HEX} -eq 0 ]; then
    echo "Error: Attestation is empty. Please check status of $ENCLAVE_URL and its get_attestation endpoint."
    exit 1
fi

# Convert hex to array using Python
ATTESTATION_ARRAY=$(python3 - <<EOF
import sys

def hex_to_vector(hex_string):
    byte_values = [str(int(hex_string[i:i+2], 16)) for i in range(0, len(hex_string), 2)]
    rust_array = [f"{byte}u8" for byte in byte_values]
    return f"[{', '.join(rust_array)}]"

print(hex_to_vector("$ATTESTATION_HEX"))
EOF
)

echo 'converted attestation'
# Execute sui client command with the converted array
sui client ptb --assign v "vector$ATTESTATION_ARRAY" \
    --move-call "0x2::nitro_attestation::load_nitro_attestation" v @0x6 \
    --assign result \
    --move-call "${PACKAGE_ID}::enclave_registry::register_enclave" @${REGISTRY_ID} result \
    --gas-budget 100000000
