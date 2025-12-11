/// Module: oyster_demo
/// A price oracle that verifies attestations and stores SUI token prices
module oyster_demo::oyster_demo;

use std::bcs;
use sui::table::{Self, Table};
use sui::event;
use sui::ecdsa_k1;
use enclave::enclave::{Self, Enclave};

// Error codes
const EInvalidSignature: u64 = 0;
const ENoPriceAtTimestamp: u64 = 1;
const ENoPriceAvailable: u64 = 2;

/// One-time witness for module initialization
public struct OYSTER_DEMO has drop {}

/// IntentMessage wrapper (must match Rust IntentMessage structure)
public struct IntentMessage<T: copy + drop> has copy, drop {
    intent: u8,
    timestamp_ms: u64,
    data: T,
}

/// Stores all price data with timestamp mapping
public struct PriceOracle<phantom T> has key {
    id: UID,
    /// Mapping from timestamp to price
    prices: Table<u64, u64>,
    /// Latest price and its timestamp
    latest_price: u64,
    latest_timestamp: u64,
}

/// Payload for price update messages signed by enclave
public struct PriceUpdatePayload has copy, drop {
    price: u64,
}

// Events
public struct PriceUpdated has copy, drop {
    price: u64,
    timestamp: u64,
}

public struct OracleCreated has copy, drop {
    oracle_id: ID,
}

/// Initialize the price oracle
fun create_oracle<T>(ctx: &mut TxContext): PriceOracle<T> {
    let oracle = PriceOracle<T> {
        id: object::new(ctx),
        prices: table::new(ctx),
        latest_price: 0,
        latest_timestamp: 0,
    };
    
    event::emit(OracleCreated {
        oracle_id: object::id(&oracle),
    });
    
    oracle
}

/// Share the oracle to make it publicly accessible
fun share_oracle<T>(oracle: PriceOracle<T>) {
    transfer::share_object(oracle);
}

/// Update price with attestation verification
/// Anyone can call this, but the signature must be valid from a registered enclave with correct PCRs
fun update_price<T: drop>(
    oracle: &mut PriceOracle<T>,
    enclave: &Enclave<T>,
    price: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
) {
    // Create the payload that should have been signed
    let payload = PriceUpdatePayload {
        price,
    };
    
    // Verify secp256k1 signature
    // Sui's secp256k1_verify will hash the message using the specified hash function
    // We use SHA256 (hash flag = 1) to match what the enclave uses
    
    // Serialize the IntentMessage structure: { intent: u8, timestamp_ms: u64, data: payload }
    let intent_message = IntentMessage {
        intent: 0u8,
        timestamp_ms,
        data: payload,
    };
    let message_bytes = bcs::to_bytes(&intent_message);
    
    let enclave_pk = enclave.pk();
    
    // Verify secp256k1 signature with SHA256 hash (flag = 1)
    // The function will hash message_bytes with SHA256 before verifying
    let is_valid = ecdsa_k1::secp256k1_verify(
        &signature,
        enclave_pk,
        &message_bytes,
        1 // SHA256 hash function
    );
    
    assert!(is_valid, EInvalidSignature);
    
    // Store the price at the timestamp
    table::add(&mut oracle.prices, timestamp_ms, price);
    
    // Update latest if this is newer
    if (timestamp_ms > oracle.latest_timestamp) {
        oracle.latest_price = price;
        oracle.latest_timestamp = timestamp_ms;
    };
    
    event::emit(PriceUpdated {
        price,
        timestamp: timestamp_ms,
    });
}

/// Get the latest SUI token price
public fun get_latest_price<T>(oracle: &PriceOracle<T>): (u64, u64) {
    assert!(oracle.latest_timestamp > 0, ENoPriceAvailable);
    (oracle.latest_price, oracle.latest_timestamp)
}

/// Get the SUI token price at a specific timestamp
public fun get_price_at_timestamp<T>(oracle: &PriceOracle<T>, timestamp: u64): u64 {
    assert!(table::contains(&oracle.prices, timestamp), ENoPriceAtTimestamp);
    *table::borrow(&oracle.prices, timestamp)
}

/// Check if a price exists at a specific timestamp
public fun has_price_at_timestamp<T>(oracle: &PriceOracle<T>, timestamp: u64): bool {
    table::contains(&oracle.prices, timestamp)
}

/// Get the timestamp of the latest price
public fun get_latest_timestamp<T>(oracle: &PriceOracle<T>): u64 {
    oracle.latest_timestamp
}

/// Module initializer - sets up enclave config
/// The oracle will be created after enclave registration
fun init(witness: OYSTER_DEMO, ctx: &mut TxContext) {
    // Create the enclave capability
    let cap = enclave::new_cap(witness, ctx);
    
    // Create the enclave configuration with PCR values
    cap.create_enclave_config(
        b"SUI Price Oracle Enclave".to_string(),
        // PCR0: Enclave image file hash - update after building your enclave
        x"3aa0e6e6ed7d8301655fced7e6ddcc443a3e57bf62f070caa6becf337069e859c0f03d68136440ff1cab8adefd20634c",
        // PCR1: Enclave kernel hash - update after building your enclave
        x"b0d319fa64f9c2c9d7e9187bc21001ddacfab4077e737957fa1b8b97cc993bed43a79019aebfd40ee5f6f213147909f8",
        // PCR2: Enclave application hash - update after building your enclave
        x"fdb2295dc5d9b67a653ed5f3ead5fc8166ec3cae1de1c7c6f31c3b43b2eb26ab5d063f414f3d2b93163426805dfe057e",
        // PCR16: Application image hash - update after building your application
        x"94a33ba1298c64a16a1f4c9cc716525c86497017e09dd976afcaf812b0e2a3e8ba04ff6954167ad69a6413a1e6e44621",
        ctx,
    );
    
    // Transfer the capability to the deployer for future PCR updates
    transfer::public_transfer(cap, ctx.sender());
}

/// Entry function to create and share the oracle after enclave registration
/// Call this once your enclave is registered on-chain
entry fun initialize_oracle(ctx: &mut TxContext) {
    let oracle = create_oracle<OYSTER_DEMO>(ctx);
    share_oracle(oracle);
}

/// Entry function to update SUI price
/// Anyone can call this with a valid signature from the authorized enclave
entry fun update_sui_price(
    oracle: &mut PriceOracle<OYSTER_DEMO>,
    enclave: &Enclave<OYSTER_DEMO>,
    price: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
) {
    update_price(
        oracle,
        enclave,
        price,
        timestamp_ms,
        signature,
    );
}

#[test_only]
public fun destroy_oracle_for_testing<T>(oracle: PriceOracle<T>) {
    let PriceOracle { id, prices, latest_price: _, latest_timestamp: _ } = oracle;
    table::drop(prices);
    object::delete(id);
}

