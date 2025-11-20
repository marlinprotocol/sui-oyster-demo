# SUI Price Oracle with Oyster Enclaves

A decentralized price oracle for SUI token that uses AWS Nitro Enclaves (via Oyster) for secure, verifiable price feeds on Sui contracts. The oracle fetches prices from CoinGecko and signs them with secp256k1, enabling trustless on-chain verification.

## Overview

This project demonstrates how to build a secure price oracle using:
- **Sui Move Smart Contracts**: On-chain price storage and signature verification
- **AWS Nitro Enclaves**: Hardware-isolated execution via Oyster deployment
- **secp256k1 Signatures**: Cryptographic proof that prices come from authorized enclaves
- **PCR Attestation**: Verifies the exact enclave code running

## Architecture

```
┌─────────────────┐
│   CoinGecko API │
└────────┬────────┘
         │
         ▼
┌─────────────────────┐      ┌──────────────────┐
│  Oyster Enclave     │      │   Sui Blockchain │
│  ┌───────────────┐  │      │  ┌────────────┐  │
│  │ Price Fetcher │  │──────┼─▶│ Move Oracle│  │
│  └───────────────┘  │      │  └────────────┘  │
│  ┌───────────────┐  │      │         │        │
│  │ secp256k1 Key │  │      │         ▼        │
│  └───────────────┘  │      │  ┌────────────┐  │
│  ┌───────────────┐  │      │  │Price History│ │
│  │   Signature   │  │      │  └────────────┘  │
│  └───────────────┘  │      │                  │
└─────────────────────┘      └──────────────────┘
```

**Flow:**
1. Enclave fetches SUI price from CoinGecko
2. Enclave signs price data with secp256k1 private key
3. Anyone submits signed price to Sui blockchain
4. Move contract verifies signature against registered enclave
5. Price stored on-chain with timestamp

## Project Structure

```
.
├── contracts/              # Sui Move smart contracts
│   ├── sources/
│   │   └── oyster_demo.move   # Price oracle with attestation verification
│   ├── script/            # Helper scripts for deployment
│   │   ├── initialize_oracle.sh
│   │   ├── update_price.sh
│   │   └── query_enclave.sh
│   └── README.md          # Contract deployment guide
│
├── enclave/               # Rust enclave server
│   ├── src/
│   │   └── main.rs        # HTTP server with price signing
│   ├── Dockerfile         # Container for Oyster deployment
│   ├── docker-compose.yml # Oyster deployment config
│   └── README.md          # Enclave deployment guide
│
├── sui-client/            # Rust SDK utilities (optional)
│   ├── src/
│   │   ├── register_enclave.rs
│   │   └── update_price.rs
│   └── README.md
│
└── README.md              # This file
```

## Quick Start

### Prerequisites

- **Sui CLI**: `cargo install --git https://github.com/MystenLabs/sui.git --branch main sui`
- **Docker**: For building enclave images
- **Oyster CLI**: `npm install -g @marlinprotocol/oyster-cvm-cli`
- **Wallet**: With SUI tokens for gas fees

### Step 1: Deploy Smart Contracts

```bash
cd contracts

# Build and publish
sui move build
sui client publish --gas-budget 100000000 --with-unpublished-dependencies

# Save from output:
# - PACKAGE_ID
# - ENCLAVE_CONFIG_ID (shared)
# - CAP_ID (owned)
```

See [contracts/README.md](contracts/README.md) for detailed instructions.

### Step 2: Build and Deploy Enclave

```bash
cd enclave

# Generate secp256k1 key
sh generate_secp256k1_key.sh

# Build Docker image
docker build -t <your-dockerhub-username>/sui-price-oracle .
docker push <your-dockerhub-username>/sui-price-oracle:latest

# Deploy with Oyster
oyster-cvm deploy \
  --wallet-private-key $PRIVATE_KEY \
  --docker-compose ./docker-compose.yml \
  --instance-type c6g.xlarge \
  --duration-in-minutes 60

# Save PUBLIC_IP from output
```

See [enclave/README.md](enclave/README.md) for detailed instructions.

### Step 3: Register Enclave On-Chain

```bash
# Get attestation
curl http://<PUBLIC_IP>:1301/attestation/hex

# Update PCRs (after building enclave)
sui client call \
  --package <ENCLAVE_PACKAGE_ID> \
  --module enclave \
  --function update_pcrs \
  --args <ENCLAVE_CONFIG_ID> <CAP_ID> 0x<PCR0> 0x<PCR1> 0x<PCR2> \
  --type-args "<PACKAGE_ID>::oyster_demo::OYSTER_DEMO" \
  --gas-budget 10000000

# Register enclave
sh register_enclave.sh \
  <ENCLAVE_PACKAGE_ID> \
  <PACKAGE_ID> \
  <ENCLAVE_CONFIG_ID> \
  <PUBLIC_IP> \
  oyster_demo \
  OYSTER_DEMO

# Save ENCLAVE_ID from output
```

### Step 4: Initialize Oracle

```bash
cd contracts/script
sh initialize_oracle.sh <PACKAGE_ID>

# Save ORACLE_ID from output
```

### Step 5: Update Prices

```bash
# One-time update
sh update_price.sh <PUBLIC_IP> <PACKAGE_ID> <ORACLE_ID> <ENCLAVE_ID>

# Or query current price
sh get_price.sh <PUBLIC_IP>
```

## Key Features

### 🔒 Security

- **Hardware Isolation**: Enclave runs in AWS Nitro Enclaves with memory encryption
- **Attestation**: PCRs prove exact enclave code is running
- **secp256k1 Signatures**: 64-byte compact signatures with SHA256 hashing
- **Immutable History**: Historical prices stored on-chain, cannot be modified

### 📊 Price Oracle

- **Real-time Prices**: Fetches from CoinGecko API
- **Precision**: 6 decimal places (price × 10^6)
- **Timestamp Mapping**: Query historical prices by timestamp
- **Latest Tracking**: Fast access to most recent price

### 🚀 Deployment

- **Docker-based**: Easy reproducible builds
- **Oyster Integration**: One-command deployment to AWS
- **Flexible Duration**: Configure enclave runtime
- **Auto-scaling**: Deploy multiple instances if needed

## API Reference

### Enclave Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/public-key` | GET | Get enclave's secp256k1 public key (33 bytes compressed) |
| `/price` | GET | Get signed SUI price |
| `:1301/attestation/hex` | GET | Get attestation document for registration |

### Move Contract Functions

| Function | Access | Description |
|----------|--------|-------------|
| `initialize_oracle()` | Entry | Create and share the oracle |
| `update_sui_price()` | Entry | Update price with valid signature |
| `get_latest_price()` | Public | Get most recent price and timestamp |
| `get_price_at_timestamp()` | Public | Get historical price |
| `has_price_at_timestamp()` | Public | Check if price exists |

## Testing

### Integration Test
```bash
# 1. Deploy enclave
# 2. Register on-chain
# 3. Fetch and submit price
sh contracts/script/update_price.sh <PUBLIC_IP> <PACKAGE_ID> <ORACLE_ID> <ENCLAVE_ID>

# 4. Query on-chain
sui client call \
  --package <PACKAGE_ID> \
  --module oyster_demo \
  --function get_latest_price \
  --args <ORACLE_ID> \
  --type-args "<PACKAGE_ID>::oyster_demo::OYSTER_DEMO"
```

## Examples

### Query Historical Prices
```bash
# Get price at specific timestamp
sui client call \
  --package <PACKAGE_ID> \
  --module oyster_demo \
  --function get_price_at_timestamp \
  --args <ORACLE_ID> <TIMESTAMP_MS> \
  --type-args "<PACKAGE_ID>::oyster_demo::OYSTER_DEMO"
```

## Resources

- [Sui Documentation](https://docs.sui.io/)
- [Nautilus Framework](https://github.com/MystenLabs/nautilus)
- [Oyster Documentation](https://docs.marlin.org/oyster/)
- [AWS Nitro Enclaves](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
- [CoinGecko API](https://www.coingecko.com/en/api)