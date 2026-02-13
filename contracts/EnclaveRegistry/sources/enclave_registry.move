// SPDX-License-Identifier: Apache-2.0
// inspired from https://github.com/MystenLabs/nautilus/blob/f9615732335027bbb73b5624e164dd65bcf95bfa/move/enclave/sources/enclave.move

// A shared enclave key registry.
// Stores verified (public_key -> PCR values) pairs after attestation verification.
// Applications can query the registry to check if a public key is registered
// and retrieve its PCR values, then use that data however they see fit
// (e.g. verify signatures, check PCRs against expected values, etc.).
//
// NOTE: This registry supports secp256k1 and x25519 public keys.
// (purely key length checks, any other type of keys with same length will also be accepted)
// secp256k1 keys are stored in compressed format (33 bytes).
// x25519 keys are stored as raw 32-byte public keys.
//
// NOTE: No on-curve validation is performed on public keys. The registry only
// validates key length. If an invalid key is registered, signature verification
// against it will always fail, but the entry will persist in the registry.

module enclave_registry::enclave_registry;

use sui::event;
use sui::nitro_attestation::NitroAttestationDocument;
use sui::table::{Self, Table};

use fun to_pcrs as NitroAttestationDocument.to_pcrs;

const ENotRegistered: u64 = 0;
const EAlreadyRegistered: u64 = 1;
const EInvalidPublicKeyLength: u64 = 2;
const ENoPublicKey: u64 = 3;
const EInvalidUncompressedPrefix: u64 = 4;
const EInvalidCompressedPrefix: u64 = 5;

// Expected public key lengths for secp256k1
const SECP256K1_PK_LENGTH_COMPRESSED: u64 = 33;
const SECP256K1_PK_LENGTH_UNCOMPRESSED: u64 = 64;
const SECP256K1_PK_LENGTH_UNCOMPRESSED_WITH_PREFIX: u64 = 65;

// Expected public key length for x25519
const X25519_PK_LENGTH: u64 = 32;

// PCR0: Enclave image file
// PCR1: Enclave Kernel
// PCR2: Enclave application
// PCR16: Application image
public struct Pcrs(vector<u8>, vector<u8>, vector<u8>, vector<u8>) has copy, drop, store;

/// Event emitted when an enclave is registered.
public struct EnclaveRegistered has copy, drop {
    pk: vector<u8>,
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    pcr16: vector<u8>,
}

// One-time witness for module initialization
public struct ENCLAVE_REGISTRY has drop {}

// Shared registry mapping public keys to their PCR values.
// secp256k1 keys are stored compressed (33 bytes), x25519 keys raw (32 bytes).
// Entries are added only after attestation verification.
public struct Registry has key {
    id: UID,
    enclaves: Table<vector<u8>, Pcrs>,
}

/// Module initializer - creates the shared registry.
fun init(_: ENCLAVE_REGISTRY, ctx: &mut TxContext) {
    let registry = Registry {
        id: object::new(ctx),
        enclaves: table::new(ctx),
    };
    transfer::share_object(registry);
}

/// Construct a Pcrs value from individual PCR vectors.
public fun new_pcrs(
    pcr0: vector<u8>,
    pcr1: vector<u8>,
    pcr2: vector<u8>,
    pcr16: vector<u8>,
): Pcrs {
    Pcrs(pcr0, pcr1, pcr2, pcr16)
}

/// Register an enclave in the registry.
/// Verifies the NitroAttestationDocument, extracts the public key and PCR values,
/// and stores them in the shared registry table.
/// Anyone can call this, but the attestation must be valid.
public fun register_enclave(
    registry: &mut Registry,
    document: NitroAttestationDocument,
) {
    let pk = load_pk(&document);
    let pcrs = document.to_pcrs();

    // Redundant check as table::add will fail if key already exists, but this allows us to emit a cleaner error
    assert!(!table::contains(&registry.enclaves, pk), EAlreadyRegistered);
    table::add(&mut registry.enclaves, pk, pcrs);

    event::emit(EnclaveRegistered {
        pk,
        pcr0: *pcrs.pcr_0(),
        pcr1: *pcrs.pcr_1(),
        pcr2: *pcrs.pcr_2(),
        pcr16: *pcrs.pcr_16(),
    });
}

/// Check if a public key is registered in the registry.
public fun is_registered(registry: &Registry, pk: &vector<u8>): bool {
    table::contains(&registry.enclaves, *pk)
}

/// Get the PCR values for a registered public key.
public fun get_pcrs(registry: &Registry, pk: &vector<u8>): &Pcrs {
    // Assert the key is registered to provide a clearer error message, otherwise table::borrow will fail with a less descriptive error
    assert!(table::contains(&registry.enclaves, *pk), ENotRegistered);
    table::borrow(&registry.enclaves, *pk)
}

// PCR accessors
public fun pcr_0(pcrs: &Pcrs): &vector<u8> { &pcrs.0 }
public fun pcr_1(pcrs: &Pcrs): &vector<u8> { &pcrs.1 }
public fun pcr_2(pcrs: &Pcrs): &vector<u8> { &pcrs.2 }
public fun pcr_16(pcrs: &Pcrs): &vector<u8> { &pcrs.3 }

fun load_pk(document: &NitroAttestationDocument): vector<u8> {
    assert!(document.public_key().is_some(), ENoPublicKey);
    let mut pk = (*document.public_key()).destroy_some();

    // If 65-byte uncompressed (0x04 prefix + 64 bytes), strip the prefix
    if (pk.length() == SECP256K1_PK_LENGTH_UNCOMPRESSED_WITH_PREFIX) {
        assert!(pk[0] == 0x04, EInvalidUncompressedPrefix);
        let mut stripped = vector::empty<u8>();
        let mut i = 1;
        while (i < 65) {
            stripped.push_back(pk[i]);
            i = i + 1;
        };
        pk = stripped;
    };

    // If uncompressed secp256k1 (64 bytes), convert to compressed format
    if (pk.length() == SECP256K1_PK_LENGTH_UNCOMPRESSED) {
        pk = compress_secp256k1_pubkey(&pk);
    };

    // Validate key length: 33 (secp256k1 compressed) or 32 (x25519)
    if (pk.length() == SECP256K1_PK_LENGTH_COMPRESSED) {
        // Validate compressed secp256k1 key prefix is 0x02 or 0x03
        assert!(pk[0] == 0x02 || pk[0] == 0x03, EInvalidCompressedPrefix);
    } else {
        assert!(pk.length() == X25519_PK_LENGTH, EInvalidPublicKeyLength);
    };

    pk
}

/// Compress an uncompressed secp256k1 public key (64 bytes) to compressed format (33 bytes)
/// Input: 64 bytes (X coordinate 32 bytes + Y coordinate 32 bytes)
/// Output: 33 bytes (0x02/0x03 prefix + X coordinate 32 bytes)
fun compress_secp256k1_pubkey(uncompressed: &vector<u8>): vector<u8> {
    assert!(uncompressed.length() == 64, EInvalidPublicKeyLength);

    let mut compressed = vector::empty<u8>();

    // Get the last byte of Y coordinate to determine parity
    let y_last_byte = uncompressed[63];

    // Prefix: 0x02 if Y is even, 0x03 if Y is odd
    let prefix = if (y_last_byte % 2 == 0) { 0x02 } else { 0x03 };
    compressed.push_back(prefix);

    // Append X coordinate (first 32 bytes)
    let mut i = 0;
    while (i < 32) {
        compressed.push_back(uncompressed[i]);
        i = i + 1;
    };

    compressed
}

fun to_pcrs(document: &NitroAttestationDocument): Pcrs {
    let pcrs = document.pcrs();

    let mut pcr0 = vector::empty<u8>();
    let mut pcr1 = vector::empty<u8>();
    let mut pcr2 = vector::empty<u8>();
    let mut pcr16 = vector::empty<u8>();

    let mut i = 0;
    while (i < pcrs.length()) {
        let entry = &pcrs[i];
        let idx = entry.index();
        if (idx == 0) {
            pcr0 = *entry.value();
        } else if (idx == 1) {
            pcr1 = *entry.value();
        } else if (idx == 2) {
            pcr2 = *entry.value();
        } else if (idx == 16) {
            pcr16 = *entry.value();
        };
        i = i + 1;
    };

    Pcrs(pcr0, pcr1, pcr2, pcr16)
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ENCLAVE_REGISTRY {}, ctx);
}