# SUI Price Oracle with Oyster Enclaves

> ⚠️ **WARNING: UNAUDITED CODE - EXPERIMENTAL USE ONLY**
>
> This code has NOT been audited by security professionals and may contain vulnerabilities or bugs. It is provided for experimental and educational purposes only. DO NOT use this in production environments or with real assets. Use at your own risk.

A decentralized price oracle for SUI token that uses AWS Nitro Enclaves (via Oyster) for secure, verifiable price feeds on Sui contracts. The oracle fetches prices from CoinGecko and signs them with secp256k1, enabling trustless on-chain verification.

## Overview

This project demonstrates how to build a secure price oracle using:
- **Enclave Key Registry** (`enclave_registry.move`): A shared on-chain registry that maps verified enclave public keys (secp256k1 and x25519) to their PCR values. It is application-independent and already deployed on-chain — you do not deploy it yourself.
- **Price Oracle** (`oyster_demo.move`): An application that consumes the registry to verify enclave signatures, check PCRs, and store SUI token prices on-chain. Deployed as a separate package that automatically links to the pre-deployed registry (via `published-at` in `EnclaveRegistry/Move.toml`).
- **AWS Nitro Enclaves**: Hardware-isolated execution via Oyster deployment
- **secp256k1 Signatures**: Cryptographic proof that prices come from authorized enclaves
- **PCR Attestation**: Verifies the exact enclave code running

## Architecture

```
                              ┌───────────────────┐
                              │  Enclave Registry │
                              │  (shared, generic)│
                              │  ┌──────────────┐ │
                              │  │pubkey -> PCRs│ │
                              │  └──────────────┘ │
                              └─────────┬─────────┘
                                        │
┌─────────────────┐                     │
│   CoinGecko API │                     │
└────────┬────────┘                     │
         │                              │
         ▼                              ▼
┌─────────────────────┐      ┌──────────────────┐
│  Oyster Enclave     │      │   Sui Blockchain │
│  ┌───────────────┐  │      │  ┌────────────┐  │
│  │ Price Fetcher │  │──────┼─▶│Price Oracle│  │
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
1. Enclave registers in the pre-deployed shared registry (attestation verified, public key + PCRs stored)
2. Application contract is published (automatically links to existing registry, not re-deployed)
3. Enclave fetches SUI price from CoinGecko and signs it with secp256k1
4. Anyone submits signed price to Sui blockchain
5. Application contract looks up the enclave's PCRs from the registry, checks they match expected values, and verifies the signature
6. Price stored on-chain with timestamp

## Project Structure

```
.
├── contracts/              # Sui Move smart contracts
│   ├── EnclaveRegistry/       # Enclave key registry package (pre-deployed, used as dependency)
│   │   ├── Move.toml
│   │   └── sources/
│   │       └── enclave_registry.move
│   ├── Demo/                  # Price oracle application package
│   │   ├── Move.toml
│   │   ├── sources/
│   │   │   └── oyster_demo.move
│   │   └── tests/
│   │       └── oyster_demo_tests.move
│   ├── script/            # Helper scripts for deployment
│   │   ├── register_enclave.sh
│   │   ├── update_price.sh
│   │   └── get_price.sh
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

### Step 1: Build and Deploy Enclave

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

### Step 2: Register Enclave in Registry

The enclave registry is a shared, application-independent contract already deployed on-chain. You do not need to deploy it — when you publish the Demo package in the next step, it automatically links to the existing registry via the `published-at` field in `EnclaveRegistry/Move.toml`.

| Network | Registry Package | Registry Object |
|---------|-----------------|----------------|
| Testnet | `0x05cd5a306375c49727fc2f1e667df8bcc1f5b52ad07e850074d330afda932761` | `0x7ebc3f9bc7a0cf0820d241ad767036483b885bbd62636fb9446bb0d99d2ed091` |

Register your enclave in the existing registry:

```bash
# Register enclave (verifies attestation, stores public key + PCRs in registry)
sh contracts/script/register_enclave.sh \
  <REGISTRY_PACKAGE_ID> \
  <REGISTRY_ID> \
  <PUBLIC_IP> \
  [ATTESTATION_PORT]  # defaults to 1301
```

This fetches the attestation document from the enclave, verifies it on-chain, and stores the public key along with its PCR values in the registry. Once registered, any application can look up this enclave's PCRs.

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

### Step 3: Deploy Application Contract

With the enclave registered, publish the Demo application. Only the Demo package is published — the registry dependency is resolved to the existing on-chain package automatically.

```bash
cd contracts/Demo

# Build and publish (only publishes Demo, not the registry)
sui move build
sui client publish --gas-budget 100000000

# Save these IDs from transaction output:
# - DEMO_PACKAGE_ID (in Published Objects)
# - ORACLE_ID (shared object, type: PriceOracle)
# - ADMIN_CAP_ID (owned object, type: AdminCap)
```

See [contracts/README.md](contracts/README.md) for detailed instructions.

### Step 4: Update Expected PCRs

Configure the oracle with the PCR values of the enclave you trust.

```bash
# Get PCR values from the enclave attestation
oyster-cvm verify --enclave-ip <PUBLIC_IP>

# Update the oracle's expected PCRs
sui client call \
  --package <DEMO_PACKAGE_ID> \
  --module oyster_demo \
  --function update_expected_pcrs \
  --args <ORACLE_ID> <ADMIN_CAP_ID> 0x<PCR0> 0x<PCR1> 0x<PCR2> 0x<PCR16> \
  --gas-budget 10000000
```

### Step 5: Update Prices

```bash
# One-time update (app_port defaults to 3000)
sh contracts/script/update_price.sh <PUBLIC_IP> <DEMO_PACKAGE_ID> <ORACLE_ID> <REGISTRY_ID> [APP_PORT]

# Or query current price from enclave
sh contracts/script/get_price.sh <PUBLIC_IP> [APP_PORT]
```

## Key Features

### Security

- **Hardware Isolation**: Enclave runs in AWS Nitro Enclaves with memory encryption
- **Attestation**: PCRs prove exact enclave code is running
- **Shared Registry**: Verified (public_key, PCRs) pairs stored on-chain after attestation verification
- **secp256k1 Signatures**: 64-byte compact signatures with SHA256 hashing
- **Immutable History**: Historical prices stored on-chain, cannot be modified

### Enclave Key Registry

- **Application-independent**: A pure data store mapping public keys to PCRs. Does not enforce any application-level logic (e.g. signature verification, PCR matching).
- **One-time attestation**: Attestation verified once at registration, not per operation
- **Public queryability**: Anyone can check if a key is registered and view its PCRs
- **Composable**: Multiple applications can use the same registry, each applying their own trust policy

### Price Oracle

- **Application-level trust**: The oracle decides which PCRs to accept and verifies signatures itself
- **Real-time Prices**: Fetches from CoinGecko API
- **Precision**: 6 decimal places (price x 10^6)
- **Timestamp Mapping**: Query historical prices by timestamp
- **Latest Tracking**: Fast access to most recent price

### Deployment

- **Docker-based**: Easy reproducible builds
- **Oyster Integration**: One-command deployment to AWS
- **Flexible Duration**: Configure enclave runtime
- **Auto-scaling**: Deploy multiple instances if needed

## API Reference

### Enclave Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/public-key` | GET | Get enclave's public key (33-byte compressed secp256k1 or 32-byte x25519) |
| `/price` | GET | Get signed SUI price |
| `:1301/attestation/hex` | GET | Get attestation document for registration |

### Move Contract Functions

#### Enclave Registry (`enclave_registry::enclave_registry`)

A generic key-PCR store. Applications consume this data as they see fit.

| Function | Access | Description |
|----------|--------|-------------|
| `register_enclave()` | Public | Register enclave after attestation verification |
| `is_registered()` | Public | Check if a public key is registered |
| `get_pcrs()` | Public | Get PCR values for a registered public key |
| `new_pcrs()` | Public | Construct a Pcrs value |

#### Price Oracle (`oyster_demo::oyster_demo`)

An application that uses the registry to verify and store prices.

| Function | Access | Description |
|----------|--------|-------------|
| `update_expected_pcrs()` | Entry (admin) | Update the oracle's expected PCR values |
| `update_sui_price()` | Public | Verify signature, check PCRs from registry, and update price |
| `get_latest_price()` | Public | Get most recent price and timestamp |
| `get_price_at_timestamp()` | Public | Get historical price |
| `has_price_at_timestamp()` | Public | Check if price exists |

## Testing

### Integration Test
```bash
# 1. Deploy enclave
# 2. Register enclave in registry (pre-deployed, no registry deployment needed)
# 3. Deploy Demo application (automatically links to existing registry)
# 4. Update expected PCRs on oracle
# 5. Fetch and submit price
sh contracts/script/update_price.sh <PUBLIC_IP> <DEMO_PACKAGE_ID> <ORACLE_ID> <REGISTRY_ID> [APP_PORT]
```

### Unit Tests
```bash
cd contracts/Demo
sui move test
```

## Reproducible Builds: Pitfalls & Best Practices

When building reproducible enclave images, avoid these common gotchas:

### **Native/Compiled Dependencies**
- **Pitfall**: Using native modules (e.g., original secp256k1, node-gyp) breaks reproducibility across architectures.
- **Fix**: Prefer pure-language implementations (@noble/secp256k1 for JS, libsodium for bindings, etc.) or accept per-architecture builds.

### **Old Docker Versions (overlay2 vs containerd)**
- **Pitfall**: Docker <29 may produce different digests when loading images (`docker load`) due to storage backend differences. Build output is fine; hashes can shift only after load.
- **Fix**: Use Docker 29+ when you need stable digests after `docker load`.

### **Using Tags Instead of Digests**
- **Pitfall**: Docker tags (`:latest`, `:v1.0`) move and don't guarantee content.
- **Fix**: Always use image digests (`sha256:abc...`) in docker-compose.yml; capture with `docker inspect --format='{{index .RepoDigests 0}}'` after pushing.

### **Modifying Dependencies Without Updating Hashes**
- **Pitfall**: Changing package.json/Cargo.toml but forgetting to update npmDepsHash or Cargo.lock; builds silently succeed with wrong deps.
- **Fix**: Update lock files first, then let Nix build fail with the new hash; copy the "got" value into build.nix.

### **Not Verifying Reproducibility**
- **Pitfall**: Assuming builds are reproducible without testing -- hidden non-determinism (timestamps, random UUIDs) only surfaces in PCR mismatches post-deployment.
- **Fix**: Build twice from the same source and compare hashes: `shasum -a 256 image-run1.tar.gz image-run2.tar.gz`; hashes must match exactly.

### **Forgetting to Commit Lock Files**
- **Pitfall**: Lock files in .gitignore; rebuild and gets different images (different PCRs, deploy breaks).
- **Fix**: Commit Cargo.lock, package-lock.json, and flake.lock to version control so all builds use identical dependencies.

### **Best Practices**
- Verify reproducibility early and often; catch non-determinism before deployment.
- Use **digests** (not tags) for content-addressed images.
- Keep **lock files** in git; treat them as part of the source.
- Build **per-architecture** if native code is involved.

## Resources

- [Sui Documentation](https://docs.sui.io/)
- [Oyster Documentation](https://docs.marlin.org/oyster/)
- [Oyster CVM CLI](https://docs.marlin.org/oyster/build-cvm/quickstart)
- [AWS Nitro Enclaves](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
- [CoinGecko API](https://www.coingecko.com/en/api)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
