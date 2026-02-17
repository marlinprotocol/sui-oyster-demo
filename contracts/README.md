# SUI Token Price Oracle with Enclave Key Registry

> ⚠️ **WARNING: UNAUDITED CODE - EXPERIMENTAL USE ONLY**
>
> This code has NOT been audited by security professionals and may contain vulnerabilities or bugs. It is provided for experimental and educational purposes only. DO NOT use this in production environments or with real assets. Use at your own risk.

A Move smart contract that uses a shared enclave key registry for looking up verified enclave public keys and their PCR values, then applies application-specific trust logic (signature verification, PCR matching) to store SUI token prices on-chain.

## Architecture

### Enclave Key Registry (`enclave_registry.move`)

A generic, application-independent shared registry that stores verified enclave public keys and their PCR values. It is a pure data store — applications consume registry data however they see fit (e.g. verify signatures, check PCRs, gate access).

**The registry is already deployed on-chain as a shared package.** You do not need to deploy it yourself. When you publish the Demo package, the Sui build system automatically links to the existing on-chain registry via the `published-at` field in `EnclaveRegistry/Move.toml` — only the Demo package is published.

| Network | Registry Package | Registry Object |
|---------|-----------------|----------------|
| Testnet | `0x05cd5a306375c49727fc2f1e667df8bcc1f5b52ad07e850074d330afda932761` | `0x7ebc3f9bc7a0cf0820d241ad767036483b885bbd62636fb9446bb0d99d2ed091` |

- **`Registry`**: Shared object containing a `Table<vector<u8>, Pcrs>` mapping public keys to their PCR values. Supports secp256k1 (stored as 33-byte compressed) and x25519 (stored as 32-byte raw) keys
- **`register_enclave`**: Verifies a NitroAttestationDocument and stores the public key + PCRs in the registry
- **`get_pcrs`**: Returns PCR values for a registered public key
- **`is_registered`**: Checks if a public key exists in the registry
- **`new_pcrs`**: Constructs a Pcrs value from individual PCR vectors

### Price Oracle (`oyster_demo.move`)

A demo application that consumes the enclave registry. It implements its own trust logic. Deployed as its own package (`Demo/`) that depends on the pre-deployed `EnclaveRegistry` package. This module is specific to the application and contains:
- Looks up an enclave's PCRs from the registry
- Checks that the PCRs match the oracle's expected values
- Verifies secp256k1 signatures over price payloads
- Stores verified prices on-chain with timestamps

#### `PriceOracle`
The main oracle object that stores all price data:
- `prices: Table<u64, u64>` - Maps timestamps to prices
- `latest_price: u64` - The most recent price
- `latest_timestamp: u64` - When the latest price was recorded
- `expected_pcrs: Pcrs` - Expected PCR values for trusted enclaves
- `pcrs_initialized: bool` - Whether PCRs have been explicitly configured

#### `AdminCap`
Capability for the deployer to update expected PCR values.

### Key Functions

#### Update Price (Requires Valid Enclave Signature + PCR Match)
```move
public fun update_sui_price(
    oracle: &mut PriceOracle,
    registry: &Registry,
    clock: &Clock,
    enclave_pk: vector<u8>,
    price: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
)
```

The function:
1. Checks the oracle is fully configured (PCRs initialized)
2. Validates freshness via the on-chain clock (max 1 hour staleness)
3. Looks up the enclave's PCRs from the registry
4. Checks the PCRs match the oracle's expected values
5. Verifies the secp256k1 signature over the price payload
6. Stores the price at the timestamp

#### Query Functions (Public Access)
```move
// Get the latest price and its timestamp
let (price, timestamp) = get_latest_price(&oracle);

// Get price at a specific timestamp
let price = get_price_at_timestamp(&oracle, timestamp);

// Check if a price exists at a timestamp
let exists = has_price_at_timestamp(&oracle, timestamp);

// Get the latest timestamp
let timestamp = get_latest_timestamp(&oracle);
```

## Setup & Deployment

### Prerequisites

1. **Oyster Enclave Setup**: Follow the [enclave deployment instructions](../enclave_rust/README.md) to:
   - Deploy an Oyster Enclave
   - Configure it to fetch SUI prices
   - Build and get the PCR values

2. **Dependencies**: Already configured in `Move.toml`

### Deployment Steps

The enclave registry is already deployed on-chain. You only need to publish the Demo package — it automatically links to the existing registry via `published-at` in `EnclaveRegistry/Move.toml`.

**Step 1: Register your enclave in the registry**

Register your enclave's public key and PCR values in the pre-deployed registry:

```bash
sh script/register_enclave.sh \
    <REGISTRY_PACKAGE_ID> \
    <REGISTRY_ID> \
    <ENCLAVE_IP> \
    [ATTESTATION_PORT]  # defaults to 1301
```

This fetches the attestation from the enclave, verifies it on-chain, and stores the public key + PCR values in the shared registry.

**Step 2: Publish the application package**
```bash
cd Demo
sui move build
sui client publish --gas-budget 100000000
```

Since the enclave registry is already published, only the Demo package is deployed. This creates (via `init` functions):
- **PriceOracle** (shared) — from the oyster_demo module
- **AdminCap** (owned by deployer) — for updating expected PCRs

Save these IDs from the transaction output:
- **Package ID** (`<DEMO_PACKAGE_ID>`): `0x...`
- **PriceOracle Object ID**: `0x...` (shared object)
- **AdminCap Object ID**: `0x...` (owned by deployer)

**Step 3: Update expected PCRs (after building your enclave)**
```bash
sui client call \
    --package <DEMO_PACKAGE_ID> \
    --module oyster_demo \
    --function update_expected_pcrs \
    --args <ORACLE_ID> <ADMIN_CAP_ID> 0x<PCR0> 0x<PCR1> 0x<PCR2> 0x<PCR16> \
    --gas-budget 10000000
```

**Step 4: Update prices**
```bash
sh script/update_price.sh <ENCLAVE_IP> <DEMO_PACKAGE_ID> <ORACLE_ID> <REGISTRY_ID> [APP_PORT]
```

`APP_PORT` defaults to 3000. Your oracle is now ready to accept price updates from enclaves whose PCRs match the expected values.

## Usage Example

### Off-Chain: Enclave Server

Your enclave server should implement an endpoint that:
1. Fetches the SUI token price from an external API
2. Creates a `PriceUpdatePayload` with price only
3. Wraps it in an `IntentMessage` with intent=0 and timestamp_ms
4. Signs it with the enclave's secp256k1 key using SHA256 hashing
5. Returns 64-byte secp256k1 signature (non-recoverable, compact format: r + s)

Example response:
```json
{
  "price": 1250000,
  "timestamp_ms": 1700000000000,
  "signature": "a1b2c3..."
}
```

### On-Chain: Update Price

Use the provided script to fetch the price from the enclave and submit it on-chain:

```bash
sh script/update_price.sh <ENCLAVE_IP> <DEMO_PACKAGE_ID> <ORACLE_ID> <REGISTRY_ID> [APP_PORT]
```

The script will:
1. Fetch the enclave's public key from `http://<ENCLAVE_IP>:<APP_PORT>/public-key`
2. Fetch the signed price from `http://<ENCLAVE_IP>:<APP_PORT>/price`
3. Convert the public key and signature to the proper format
4. Submit the transaction on-chain

### On-Chain: Read Prices

```move
// Get the latest SUI price
let (current_price, timestamp) = get_latest_price(&oracle);

// Get historical price
let historical_price = get_price_at_timestamp(&oracle, old_timestamp);

// Check if price exists before querying
if (has_price_at_timestamp(&oracle, some_timestamp)) {
    let price = get_price_at_timestamp(&oracle, some_timestamp);
    // Use the price...
}
```

## Trust Model

The enclave key registry and the application have clearly separated responsibilities:

1. **Registry stores data**: When an enclave registers, the registry verifies the NitroAttestationDocument and stores the (public_key, PCRs) pair. This is a one-time operation. The registry does not enforce any trust policy.
2. **Applications define trust**: Applications query the registry to get the PCR values for a public key and compare against their expected values. Each application independently decides which PCR values to trust.
3. **Applications verify signatures**: Signature verification is the application's responsibility. The application uses the public key from the registry and verifies the signature over its own payload format.

This means:
- The registry is a generic, reusable component
- Multiple applications can share the same registry
- Applications independently decide which PCR values to trust
- Applications define their own payload formats and signature verification logic
- Attestation verification happens only once per enclave, not per application

## Error Codes

- `EInvalidSignature (0)`: The provided signature is invalid or doesn't match the payload
- `ENoPriceAtTimestamp (1)`: No price exists at the requested timestamp
- `ENoPriceAvailable (2)`: The oracle has no prices yet (latest price query on empty oracle)
- `EInvalidPCRs (3)`: The enclave's PCR values don't match the oracle's expected values
- `EPcrsNotInitialized (4)`: The admin has not yet configured expected PCR values
- `EStalePrice (5)`: The price timestamp is too old (more than 1 hour) or in the future

## Events

### `OracleCreated`
Emitted when a new oracle is created:
```move
public struct OracleCreated has copy, drop {
    oracle_id: ID,
}
```

### `PriceUpdated`
Emitted when a price is successfully updated:
```move
public struct PriceUpdated has copy, drop {
    price: u64,
    timestamp: u64,
}
```

### `PcrsUpdated`
Emitted when the admin updates expected PCR values:
```move
public struct PcrsUpdated has copy, drop {
    oracle_id: ID,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    pcr16: vector<u8>,
}
```

## Resources

- [Oyster Documentation](https://docs.marlin.org/oyster/build-cvm/tutorials/)
- [AWS Nitro Enclaves](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
- [Sui Move Documentation](https://docs.sui.io/build/move)