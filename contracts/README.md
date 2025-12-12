# SUI Token Price Oracle with Attestation Verification

A Move smart contract that verifies attestations using the Oyster enclaves and stores SUI token prices with timestamp mapping. The oracle provides secure price updates verified through AWS Nitro Enclave attestations.

## Features

- ✅ **Attestation Verification**: Uses Oyster enclaves to generate signed price updates
- ✅ **Timestamp Mapping**: Stores historical prices mapped by timestamp
- ✅ **Latest Price Tracking**: Automatically tracks the most recent price update
- ✅ **Public Accessibility**: Anyone can read prices, but only verified enclaves can update
- ✅ **Event Emission**: Emits events for price updates and oracle creation

## Architecture

### Core Structures

#### `PriceOracle<phantom T>`
The main oracle object that stores all price data:
- `prices: Table<u64, u64>` - Maps timestamps to prices
- `latest_price: u64` - The most recent price
- `latest_timestamp: u64` - When the latest price was recorded

#### `PriceUpdatePayload`
The payload structure signed by the enclave:
```move
public struct PriceUpdatePayload has copy, drop {
    price: u64,  // Price in smallest unit (with 10^6 multiplier)
}
```

Note: The timestamp is part of the `IntentMessage` wrapper, not the payload itself.

### Key Functions

#### Initialization
```move
// Create a new price oracle
let oracle = create_oracle<PRICE_ORACLE>(ctx);

// Share it to make it publicly accessible
share_oracle(oracle);
```

#### Update Price (Requires Valid Enclave Signature)
```move
fun update_price<T: drop>(
    oracle: &mut PriceOracle<T>,
    enclave: &Enclave<T>,
    price: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
)
```

Note: The signature is secp256k1 (64 bytes) with SHA256 hashing.

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

1. **Oyster Enclave Setup**: Follow the [enclave deployment instructions](../enclave/README.md) to:
   - Deploy an Oyster Enclave
   - Configure it to fetch SUI prices
   - Build and get the PCR values

2. **Dependencies**: Already configured in `Move.toml`:
```toml
[dependencies]
enclave = { git = "https://github.com/MystenLabs/nautilus.git", subdir = "move/enclave", rev = "main" }
```

Uses the `enclave` module from nautilus repo to register enclaves.

### Deployment Steps

**Step 1: Publish the package**
```bash
sui move build
sui client publish --gas-budget 100000000 --with-unpublished-dependencies
```

This automatically:
- Creates the enclave configuration (via `init` function)
- Transfers the capability to the deployer
- Sets up the infrastructure

Save these IDs from the transaction output:
- **Package ID**: `0x...`
- **EnclaveConfig Object ID**: `0x...` (shared object)
- **Cap Object ID**: `0x...` (owned by deployer)

**Step 2: Update PCRs (after building your enclave)**
```bash
sui client call \
    --package <ENCLAVE_PACKAGE_ID> \
    --module enclave \
    --function update_pcrs \
    --args <ENCLAVE_CONFIG_ID> <CAP_ID> 0x<PCR0> 0x<PCR1> 0x<PCR2> 0x<PCR16>\
    --type-args "<PACKAGE_ID>::oyster_demo::OYSTER_DEMO" \
    --gas-budget 10000000
```

**Step 3: Register your enclave**
```bash
# Get attestation from your running enclave
curl http://<ENCLAVE_IP>:1301/attestation/hex

# Register it on-chain
sh script/register_enclave.sh \
    <ENCLAVE_PACKAGE_ID> \
    <APP_PACKAGE_ID> \
    <ENCLAVE_CONFIG_ID> \
    ENCLAVE_IP \
    oyster_demo \
    OYSTER_DEMO
```

Save the **Enclave Object ID**: `0x...` (shared object)

**Step 4: Initialize the oracle**
```bash
sh script/initialize_oracle.sh <PACKAGE_ID>
```

Save the **Oracle Object ID**: `0x...` (shared object) from the transaction output.

Look for the newly created `PriceOracle` shared object in the output

Done! Your oracle is now ready to accept price updates from the authorized enclave only.

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
  "signature": "a1b2c3..."  // 64 bytes hex-encoded secp256k1 signature
}
```

**Signature Format**: The enclave signs the BCS-serialized `IntentMessage<PriceUpdatePayload>` structure:
```rust
IntentMessage {
    intent: 0,
    timestamp_ms: 1700000000000,
    data: PriceUpdatePayload { price: 1250000 }
}
```
The signature is created using secp256k1 with SHA256 hashing (64 bytes: r + s).

### On-Chain: Update Price

Use the provided script to fetch the price from the enclave and submit it on-chain:

```bash
sh script/update_price.sh <ENCLAVE_IP> <PACKAGE_ID> <ORACLE_ID> <ENCLAVE_ID>
```

Example:
```bash
sh update_price.sh 192.168.1.100 0x123... 0x456... 0x789...
```

The script will:
1. Fetch the signed price from the enclave at `http://<ENCLAVE_IP>:3000/price`
2. Extract the price, timestamp, and signature
3. Convert the signature to the proper format
4. Submit the transaction on-chain

**Note**: The signature must be 64 bytes (128 hex characters) in secp256k1 compact format.

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

## Security Considerations

### Attestation Verification

The contract verifies that:
1. The secp256k1 signature (64 bytes) is valid for the given payload
2. The signature was created by a registered enclave
3. The enclave's public key matches the on-chain record (converted from 64-byte uncompressed to 33-byte compressed format)
4. The PCRs (Platform Configuration Registers) match the expected values
5. The signature uses SHA256 hashing (hash flag = 1)

TODO: Store enclave's public key in 33-byte compressed format while registering.

**Public Key Format**: 
- Enclave module stores: 64 bytes uncompressed secp256k1 (X + Y coordinates)
- Contract converts to: 33 bytes compressed (prefix + X coordinate)
- Prefix: 0x02 if Y is even, 0x03 if Y is odd

### Trust Model

- **Enclaves**: Only registered enclaves with valid attestations can update prices
- **Price Data**: Historical prices are immutable once stored
- **Latest Tracking**: Latest price can be tracked
- **Permissionless Reads**: Anyone can query price data

## Error Codes

- `EInvalidSignature (0)`: The provided signature is invalid or doesn't match the payload
- `ENoPriceAtTimestamp (1)`: No price exists at the requested timestamp
- `ENoPriceAvailable (2)`: The oracle has no prices yet (latest price query on empty oracle)

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

## Resources

- [Oyster Documentation](https://docs.marlin.org/oyster/build-cvm/tutorials/)
- [Nautilus Enclave Module](https://github.com/MystenLabs/nautilus/blob/main/move/enclave/sources/enclave.move)
- [AWS Nitro Enclaves](https://aws.amazon.com/ec2/nitro/nitro-enclaves/)
- [Sui Move Documentation](https://docs.sui.io/build/move)