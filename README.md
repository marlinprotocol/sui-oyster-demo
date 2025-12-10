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
│   │   ├── register_enclave.sh
│   │   ├── update_price.sh
│   │   ├── get_price.sh
│   │   └── query_enclave.sh
│   └── README.md          # Contract deployment guide
│
├── enclave_rust/          # Rust enclave server
│   ├── src/
│   │   └── main.rs        # HTTP server with price signing
│   ├── Dockerfile         # Container for Oyster deployment
│   ├── docker-compose.yml # Oyster deployment config
│   └── README.md          # Enclave deployment guide
│
├── enclave_node/          # Node.js enclave implementation (alternative)
│   └── README.md
│
├── enclave_python/        # Python enclave implementation (alternative)
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

# Save these IDs from transaction output:
# - PACKAGE_ID (in Published Objects)
# - ENCLAVE_CONFIG_ID (shared object, type: EnclaveConfig)
# - CAP_ID (owned object, type: Cap)
```

See [contracts/README.md](contracts/README.md) for detailed instructions.

### Step 2: Build and Deploy Enclave

```bash
cd enclave_rust

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

See [enclave_rust/README.md](enclave_rust/README.md) for detailed instructions.

### Step 3: Register Enclave On-Chain

```bash
# Get attestation
curl http://<PUBLIC_IP>:1301/attestation/hex

# Get PCR values to extract the PCR values from the enclave attestation. Record PCR0, PCR1, PCR2, PCR16 and imageId for later use.
oyster-cvm verify --enclave-ip <PUBLIC_IP>

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

#### Verifying Enclave Integrity

Enclave verification involves two separate checks:

1. **Base Image Verification** (PCR0, PCR1, PCR2): Confirms the enclave uses the official Oyster blue base image
2. **Application Verification** (PCR16/imageId): Confirms the exact application code running in the enclave

#### Verify Base Image (PCR0, PCR1, PCR2)

Rebuild the Oyster base image from source and compare PCR values to confirm you're running the canonical blue base image.

```sh
# Launch Nix environment in Docker (no local installation needed)
docker run -it nixos/nix bash

# Inside the container, clone and build the Oyster base image
git clone https://github.com/marlinprotocol/oyster-monorepo.git
cd oyster-monorepo && git checkout base-blue-v3.0.0

# Build the enclave image reproducibly
nix build -vL \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  --accept-flake-config \
  .#default.enclaves.blue.default

# View PCR values from the reproducible build
cat result/pcr.json
```

Compare the PCR0, PCR1, and PCR2 values in `result/pcr.json` with those from `oyster-cvm verify --enclave-ip <PUBLIC_IP>`.

#### Verify Application Code (PCR16/imageId)

Rebuild the application Docker image and verify it matches the deployed enclave.

**Step 1: Build the Docker image reproducibly**

```sh
# Build the Rust enclave image (Node.js and Python support coming soon)
./nix.sh build-rust

# Load the image into Docker
docker load < rust-image.tar.gz

# Get the image digest
docker images --digests --format '{{.Digest}}' sui-price-oracle:rust-reproducible-latest
```

**Step 2: Verify the image hash matches docker-compose.yml**

The digest from the previous step should match the hash specified in `enclave_rust/docker-compose.yml`. This confirms the image was built from the source code in this repository.

**Note**: Cross-platform builds are not currently supported, so the build architecture must match the deployment architecture(ARM64 and AMD64 are currently supported architectures).

**Step 3: Compute and compare imageId**

```sh
# Calculate the expected imageId from docker-compose.yml
oyster-cvm compute-image-id --docker-compose ./enclave_rust/docker-compose.yml

# Compare with the imageId from the running enclave
oyster-cvm verify --enclave-ip <PUBLIC_IP>
```

If both imageId values match, you have cryptographic proof that the deployed enclave is running the exact code you inspected and built locally.

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
| `/public-key` | GET | Get enclave's secp256k1 public key (65 bytes uncompressed) |
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

## Reproducible Builds with Nix

For production deployments, you can use Nix flakes to create **fully reproducible** Docker images with locked dependencies. This ensures identical builds across all machines and enables PCR attestation.

### Prerequisites

Only **Docker** is required. No need to install Nix on your machine.

### Quick Start

```bash
# Using the helper script (recommended)
./nix.sh build-rust    # Build Rust implementation
./nix.sh build-node    # Build Node.js implementation
./nix.sh build-python  # Build Python implementation

# Load and run the Docker image
docker load < result
```

### Available Commands

```bash
./nix.sh build-rust     # Build Rust Docker image (recommended for production)
./nix.sh build-node     # Build Node.js Docker image
./nix.sh build-python   # Build Python Docker image
./nix.sh build-all      # Build all implementations
./nix.sh update         # Update flake dependencies
```

### How It Works

The Nix build system uses:
- **flake.nix**: Defines all three language implementations and dev environments
- **flake.lock**: Locks system package versions (Rust, Node.js, Python, etc.)
- **Cargo.lock**: Locks Rust dependencies
- **package-lock.json**: Locks Node.js dependencies
- **requirements.txt**: Pins Python dependencies

All builds run inside Docker using `nixos/nix:latest`, so you don't need to install Nix locally.

### Manual Docker Commands

If you prefer not to use the helper script:

```bash
# Build
docker run --rm -it \
  -v $(pwd):/workspace -w /workspace \
  -e NIX_CONFIG='experimental-features = nix-command flakes' \
  nixos/nix:latest \
  nix build .#rust --out-link result

# Development shell
docker run --rm -it \
  -v $(pwd):/workspace -w /workspace \
  -e NIX_CONFIG='experimental-features = nix-command flakes' \
  nixos/nix:latest \
  nix develop
```

### Why Nix for Enclaves?

1. **Reproducibility**: Identical builds on any machine → consistent PCR values
2. **Attestation**: Users can rebuild images and verify they match deployed enclaves
3. **Security**: Locked dependencies prevent supply chain attacks
4. **Simplicity**: Single command builds entire stack with all dependencies

## Resources

- [Sui Documentation](https://docs.sui.io/)
- [Nautilus Framework](https://github.com/MystenLabs/nautilus)
- [Oyster Documentation](https://docs.marlin.org/oyster/)
- [Oyster CVM CLI](https://docs.marlin.org/oyster/build-cvm/quickstart)
- [AWS Nitro Enclaves](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
- [CoinGecko API](https://www.coingecko.com/en/api)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)