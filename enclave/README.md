# SUI Price Oracle - Oyster Enclave

Rust HTTP server that fetches SUI token price from CoinGecko and signs it with secp256k1 for on-chain verification. Deployed as an Oyster Enclave using Oyster CVM CLI.

## Features

- **CoinGecko Integration**: Fetches real-time SUI/USD price from CoinGecko free tier API
- **secp256k1 Signing**: Signs price data with SHA256 hashing
- **BCS Serialization**: Compatible with Sui Move contract verification
- **Oyster Deployment**: Deploys to Oyster Enclaves via Oyster CVM

## Prerequisites

- Docker installed
- Docker Hub account
- Oyster CLI installed ([docs](https://docs.marlin.org/oyster/build-cvm/quickstart#install-oyster-cvm))
- Wallet with funds for deployment

## Deployment Steps

### 1. Build Docker Image

```bash
cd enclave
docker build -t <your-dockerhub-username>/sui-price-oracle .
```

### 2. Push to Docker Hub

```bash
docker push <your-dockerhub-username>/sui-price-oracle:latest
```

### 3. Deploy with Oyster CVM

Update `docker-compose.yml` with your Docker image name, then deploy:

```bash
oyster-cvm deploy \
  --wallet-private-key $PRIVATE_KEY \
  --docker-compose ./docker-compose.yml \
  --instance-type c6g.xlarge \
  --duration-in-minutes 30
```

**Parameters:**
- `--wallet-private-key`: Your wallet's private key for paying deployment costs
- `--docker-compose`: Path to docker-compose.yml
- `--instance-type`: instance type (c6g.xlarge recommended)
- `--duration-in-minutes`: How long the enclave runs (atleast 20 min)

**Output**: The command returns the enclave's public IP address.

Save the **Enclave IP** for the next steps.

### 5. Verify Deployment

```bash
# Health check
curl http://<ENCLAVE_IP>:3000/health

# Get public key
curl http://<ENCLAVE_IP>:3000/public-key

# Fetch signed price
curl http://<ENCLAVE_IP>:3000/price

# Get attestation document
curl http://<ENCLAVE_IP>:1301/attestation/hex

# Verify the attestation of enclave
oyster-cvm verify --enclave-ip <ENCLAVE_IP> -p 1301
```

## API Endpoints

### GET /health

Health check endpoint.

**Response:**
```json
{
  "status": "ok"
}
```

### GET /public-key

Get the enclave's secp256k1 public key (compressed, 33 bytes).

**Response:**
```json
{
  "public_key": "02a1b2c3d4..."
}
```

Use this public key when registering the enclave on-chain.

### GET /price

Fetch current SUI price with secp256k1 signature.

**Response:**
```json
{
  "price": 1234567,
  "timestamp_ms": 1704067200000,
  "signature": "a1b2c3d4..."
}
```

- `price`: SUI/USD price × 10^6 (e.g., 1234567 = $1.234567)
- `timestamp_ms`: Unix timestamp in milliseconds
- `signature`: Hex-encoded secp256k1 signature (64 bytes) over BCS-serialized IntentMessage

### GET (Oyster) :1301/attestation/hex

Get the attestation document for on-chain registration.

**Response:** Attestation document as hex string

Use this attestation document when registering the enclave with PCRs on-chain.

## Integration with Move Contract

The signature covers the following BCS-serialized structure:

```rust
IntentMessage {
    intent: 0u8,
    timestamp_ms: u64,  // milliseconds
    data: PriceUpdatePayload {
        price: u64,
    }
}
```

**Signature Details:**
- **Algorithm**: secp256k1
- **Hash Function**: SHA256
- **Format**: 64 bytes compact (r + s)
- **Public Key**: 33 bytes compressed (0x02/0x03 prefix + X coordinate)

This matches the Move contract's expected format for `ecdsa_k1::secp256k1_verify()`.

## Complete Workflow

### 1. Deploy Enclave
```bash
# Build and push Docker image
docker build -t <username>/sui-price-oracle .
docker push <username>/sui-price-oracle:latest

# Deploy with Oyster
oyster-cvm deploy \
  --wallet-private-key $PRIVATE_KEY \
  --docker-compose ./docker-compose.yml \
  --instance-type c6g.xlarge \
  --duration-in-minutes 20

# Note the Public IP from output
```

### 2. Register Enclave On-Chain
```bash
# Get attestation
curl http://<PUBLIC_IP>:1301/attestation/hex

# Register using the attestation and PCR values
# See ../contracts/README.md for detailed instructions
```

### 3. Use the Oracle
```bash
# Fetch signed price from enclave
curl http://<PUBLIC_IP>:3000/price

# Response:
# {
#   "price": 1234567,
#   "timestamp_ms": 1704067200000,
#   "signature": "3f8a2b..."
# }

# Update on-chain using the script
cd ../contracts/script
sh update_price.sh <PUBLIC_IP> <PACKAGE_ID> <ORACLE_ID> <ENCLAVE_ID>
```

## Rate Limiting

CoinGecko free tier is used which allows around 10 calls/minute.

## Security Considerations

### Enclave Security
- **Attestation**: PCRs verify the exact enclave code running
- **Key Isolation**: Private key never leaves the enclave memory
- **Immutable Execution**: AWS Nitro Enclaves provide hardware-level isolation

### Key Management
- **Generation**: Generate keys inside the enclave
- **Storage**: Keys are ephemeral and mounted read-only

### On-Chain Security
- **PCR Verification**: Move contract verifies enclave code integrity via PCRs
- **Signature Verification**: secp256k1 signature proves data came from registered enclave
- **Public Key Binding**: Enclave's public key stored on-chain during registration