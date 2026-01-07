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

- **Sui CLI**: [docs](https://docs.sui.io/guides/developer/getting-started/sui-install#quick-install)
- **Docker**: For building enclave images; **29+ recommended** so image digests remain stable after `docker load` (older Docker may alter hashes on load, builds still work)
- **Oyster CLI**: [docs](https://docs.marlin.org/oyster/build-cvm/tutorials/setup#install-the-oyster-cvm-cli-tool)
- **Wallet**: With SUI tokens for gas fees and USDC for enclave deployments

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

Pick an implementation and target architecture, then build reproducibly with Nix (artifacts are tarballs you can `docker load`).

```bash
# From repo root
./nix.sh build-rust-arm64    # or build-rust-amd64
./nix.sh build-node-arm64    # or build-node-amd64
./nix.sh build-python-arm64  # or build-python-amd64

docker load < ./rust-arm64-image.tar.gz   # example for Rust/arm64
# Tag/push (example for Rust/arm64)
# Replace <registry> with your docker hub username
docker tag sui-price-oracle:rust-reproducible-arm64 <registry>/sui-price-oracle:rust-reproducible-arm64
docker push <registry>/sui-price-oracle:rust-reproducible-arm64

# Get the pushed digest and update compose (per architecture)
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' <registry>/sui-price-oracle:rust-reproducible-arm64)
# Update the image with it's sha256 in docker-compose.yml
sed -i '' "s@^\s*image: .*@    image: ${DIGEST}@" enclave_rust/docker-compose.yml

# Deploy with Oyster (point docker-compose to your pushed image/digest)
# export the PRIVATE_KEY with Sui and USDC used for deployments
export PRIVATE_KEY="suiprivkey......."
oyster-cvm deploy \
  --wallet-private-key $PRIVATE_KEY \
  --docker-compose ./enclave_rust/docker-compose.yml \
  --instance-type c6g.xlarge \
  --duration-in-minutes 60 \
  --deployment sui
# Save PUBLIC_IP from output
# For Node/Python, adjust the tag/push, update the compose image to the digest, and use ./enclave_node or ./enclave_python compose files
```

See the language-specific READMEs for deployment details.

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
  --args <ENCLAVE_CONFIG_ID> <CAP_ID> 0x<PCR0> 0x<PCR1> 0x<PCR2> 0x<PCR16> \
  --type-args "<PACKAGE_ID>::oyster_demo::OYSTER_DEMO" \
  --gas-budget 10000000

# Register enclave
sh contracts/script/register_enclave.sh \
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
# Pick implementation + architecture
./nix.sh build-rust-arm64    # or build-rust-amd64
./nix.sh build-node-arm64    # or build-node-amd64
./nix.sh build-python-arm64  # or build-python-amd64

# Load the image into Docker (example for Rust/arm64)
docker load < ./rust-arm64-image.tar.gz

# Get the image digest
docker images --digests --format '{{.Digest}}' sui-price-oracle:rust-reproducible-arm64
# or:
docker images --digests --format '{{.Digest}}' sui-price-oracle:node-reproducible-arm64
docker images --digests --format '{{.Digest}}' sui-price-oracle:python-reproducible-arm64
```

**Step 2: Verify the image hash matches docker-compose.yml**

The digest from the previous step should match the hash specified in `enclave_rust/docker-compose.yml` (or `enclave_python/docker-compose.yml` for Python). This confirms the image was built from the source code in this repository.

**Note**: Builds are reproducible for both arm64 and ARM64. Use the artifact that matches your deployment architecture.

**Step 3: Compute and compare imageId**

```sh
# Calculate the expected imageId from docker-compose.yml
oyster-cvm compute-image-id --docker-compose ./enclave_rust/docker-compose.yml
# or for Python:
oyster-cvm compute-image-id --docker-compose ./enclave_python/docker-compose.yml

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

## Reproducible Builds: Pitfalls & Best Practices

When building reproducible enclave images, avoid these common gotchas:

### ❌ **Native/Compiled Dependencies**
- **Pitfall**: Using native modules (e.g., original secp256k1, node-gyp) breaks reproducibility across architectures.
- **Fix**: Prefer pure-language implementations (@noble/secp256k1 for JS, libsodium for bindings, etc.) or accept per-architecture builds.

### ❌ **Old Docker Versions (overlay2 vs containerd)**
- **Pitfall**: Docker <29 may produce different digests when loading images (`docker load`) due to storage backend differences. Build output is fine; hashes can shift only after load.
- **Fix**: Use Docker 29+ when you need stable digests after `docker load`.

### ❌ **Using Tags Instead of Digests**
- **Pitfall**: Docker tags (`:latest`, `:v1.0`) move and don't guarantee content—digest mismatches lead to PCR failures.
- **Fix**: Always use image digests (`sha256:abc...`) in docker-compose.yml; capture with `docker inspect --format='{{index .RepoDigests 0}}'` after pushing.

### ❌ **Modifying Dependencies Without Updating Hashes**
- **Pitfall**: Changing package.json/Cargo.toml but forgetting to update npmDepsHash or Cargo.lock; builds silently succeed with wrong deps.
- **Fix**: Update lock files first, then let Nix build fail with the new hash; copy the "got" value into build.nix.

### ❌ **Not Verifying Reproducibility**
- **Pitfall**: Assuming builds are reproducible without testing—hidden non-determinism (timestamps, random UUIDs) only surfaces in PCR mismatches post-deployment.
- **Fix**: Build twice from the same source and compare hashes: `shasum -a 256 image-run1.tar.gz image-run2.tar.gz`; hashes must match exactly.

### ❌ **Forgetting to Commit Lock Files**
- **Pitfall**: Lock files in .gitignore; rebuild and gets different images (different PCRs, deploy breaks).
- **Fix**: Commit Cargo.lock, package-lock.json, and flake.lock to version control so all builds use identical dependencies.

### ✅ **Best Practices**
- Verify reproducibility early and often; catch non-determinism before deployment.
- Use **digests** (not tags) for content-addressed images.
- Keep **lock files** in git; treat them as part of the source.
- Build **per-architecture** if native code is involved.

## Resources

- [Sui Documentation](https://docs.sui.io/)
- [Nautilus Framework](https://github.com/MystenLabs/nautilus)
- [Oyster Documentation](https://docs.marlin.org/oyster/)
- [Oyster CVM CLI](https://docs.marlin.org/oyster/build-cvm/quickstart)
- [AWS Nitro Enclaves](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
- [CoinGecko API](https://www.coingecko.com/en/api)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
