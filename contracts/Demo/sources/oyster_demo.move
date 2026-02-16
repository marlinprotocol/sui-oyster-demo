/// Module: oyster_demo
/// A price oracle that uses the enclave registry to look up registered public keys
/// and their PCR values. Demonstrates how applications can consume the enclave
/// registry and implement their own signature verification and trust logic.
///
/// The enclave registry is a pre-deployed on-chain package. This module links to it
/// at publish time via `published-at` in `EnclaveRegistry/Move.toml` — the Sui type
/// system guarantees that only the correct `Registry` object can be passed at runtime.
///
/// NOTE: This demo application uses secp256k1 signatures only. While the enclave
/// registry supports both secp256k1 and x25519 keys, signature scheme selection is
/// an application-level concern.

module oyster_demo::oyster_demo;

use std::bcs;
use sui::ecdsa_k1;
use sui::table::{Self, Table};
use sui::event;
use sui::clock::{Self, Clock};
use enclave_registry::enclave_registry::{Self, Registry, Pcrs};

// Error codes
const EInvalidSignature: u64 = 0;
const ENoPriceAtTimestamp: u64 = 1;
const ENoPriceAvailable: u64 = 2;
const EInvalidPCRs: u64 = 3;
const EPcrsNotInitialized: u64 = 4;
const EStalePrice: u64 = 5;

/// Maximum allowed age for a price update (1 hour in milliseconds)
const MAX_PRICE_AGE_MS: u64 = 3_600_000;

/// Capability for the oracle deployer to update expected PCRs
public struct AdminCap has key, store {
    id: UID,
}

/// Stores all price data with timestamp mapping and expected PCR values
public struct PriceOracle has key {
    id: UID,
    /// Mapping from timestamp to price
    prices: Table<u64, u64>,
    /// Latest price and its timestamp
    latest_price: u64,
    latest_timestamp: u64,
    /// Expected PCR values - only enclaves with matching PCRs can update prices
    expected_pcrs: Pcrs,
    /// Whether the admin has explicitly configured PCR values
    pcrs_initialized: bool,
}

/// An intent message wrapper for enclave-signed payloads.
/// Applications define their own payload types and wrap them in this
/// structure before BCS-serializing for signature verification.
public struct IntentMessage<T: drop> has copy, drop {
    intent: u8,
    timestamp_ms: u64,
    payload: T,
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

public struct PcrsUpdated has copy, drop {
    oracle_id: ID,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    pcr16: vector<u8>,
}

/// Module initializer - creates the oracle and admin capability.
/// The admin must call update_expected_pcrs before the oracle can accept
/// price updates.
fun init(ctx: &mut TxContext) {
    let oracle = PriceOracle {
        id: object::new(ctx),
        prices: table::new(ctx),
        latest_price: 0,
        latest_timestamp: 0,
        // Placeholder PCR values - admin must call update_expected_pcrs before use
        expected_pcrs: enclave_registry::new_pcrs(
            x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
        ),
        pcrs_initialized: false,
    };

    event::emit(OracleCreated {
        oracle_id: object::id(&oracle),
    });

    transfer::share_object(oracle);

    let cap = AdminCap { id: object::new(ctx) };
    transfer::transfer(cap, ctx.sender());
}

/// Update the expected PCR values for the oracle.
/// Only the admin (holder of AdminCap) can call this.
/// Must be called before prices can be updated.
entry fun update_expected_pcrs(
    oracle: &mut PriceOracle,
    _cap: &AdminCap,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    pcr16: vector<u8>,
) {
    oracle.expected_pcrs = enclave_registry::new_pcrs(pcr0, pcr1, pcr2, pcr16);
    oracle.pcrs_initialized = true;
    event::emit(PcrsUpdated {
        oracle_id: object::id(oracle),
        pcr0, pcr1, pcr2, pcr16,
    });
}

/// Update SUI price.
/// Looks up the enclave's PCRs from the registry, verifies they match the
/// oracle's expected values, checks freshness via the on-chain clock, then verifies
/// the secp256k1 signature over the price payload.
/// Public (not entry) to allow composability with other Move modules.
public fun update_sui_price(
    oracle: &mut PriceOracle,
    registry: &Registry,
    clock: &Clock,
    enclave_pk: vector<u8>,
    price: u64,
    timestamp_ms: u64,
    signature: vector<u8>,
) {
    // Ensure oracle is fully configured
    assert!(oracle.pcrs_initialized, EPcrsNotInitialized);

    // Staleness check: price must not be older than MAX_PRICE_AGE_MS
    let current_time = clock::timestamp_ms(clock);
    assert!(timestamp_ms <= current_time && current_time - timestamp_ms <= MAX_PRICE_AGE_MS, EStalePrice);

    // Look up the enclave's PCRs from the registry and check they match
    let pcrs = enclave_registry::get_pcrs(registry, &enclave_pk);
    assert!(*pcrs == oracle.expected_pcrs, EInvalidPCRs);

    // Verify secp256k1 signature over the intent message
    let intent_message = IntentMessage {
        intent: 0,
        timestamp_ms,
        payload: PriceUpdatePayload { price },
    };
    let msg_bytes = bcs::to_bytes(&intent_message);
    let is_valid = ecdsa_k1::secp256k1_verify(&signature, &enclave_pk, &msg_bytes, 1);
    assert!(is_valid, EInvalidSignature);

    // Store the price at the timestamp (table::add aborts on duplicate — implicit replay guard)
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
public fun get_latest_price(oracle: &PriceOracle): (u64, u64) {
    assert!(oracle.latest_timestamp > 0, ENoPriceAvailable);
    (oracle.latest_price, oracle.latest_timestamp)
}

/// Get the SUI token price at a specific timestamp
public fun get_price_at_timestamp(oracle: &PriceOracle, timestamp: u64): u64 {
    assert!(table::contains(&oracle.prices, timestamp), ENoPriceAtTimestamp);
    *table::borrow(&oracle.prices, timestamp)
}

/// Check if a price exists at a specific timestamp
public fun has_price_at_timestamp(oracle: &PriceOracle, timestamp: u64): bool {
    table::contains(&oracle.prices, timestamp)
}

/// Get the timestamp of the latest price
public fun get_latest_timestamp(oracle: &PriceOracle): u64 {
    assert!(oracle.latest_timestamp > 0, ENoPriceAvailable);
    oracle.latest_timestamp
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun update_expected_pcrs_for_testing(
    oracle: &mut PriceOracle,
    cap: &AdminCap,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    pcr16: vector<u8>,
) {
    update_expected_pcrs(oracle, cap, pcr0, pcr1, pcr2, pcr16);
}

#[test_only]
public fun destroy_oracle_for_testing(oracle: PriceOracle) {
    let PriceOracle {
        id,
        prices,
        latest_price: _,
        latest_timestamp: _,
        expected_pcrs: _,
        pcrs_initialized: _,
    } = oracle;
    table::drop(prices);
    object::delete(id);
}
