// SPDX-License-Identifier: Apache-2.0
// inspired from https://github.com/MystenLabs/nautilus/blob/f9615732335027bbb73b5624e164dd65bcf95bfa/move/enclave/sources/enclave.move

// A shared enclave key registry.
// Stores verified (public_key -> PCR values) pairs after attestation verification.
// Applications can query the registry to check if a public key is registered
// and retrieve its PCR values, then use that data however they see fit
// (e.g. verify signatures, check PCRs against expected values, etc.).

module enclave_registry::enclave_registry;

use sui::nitro_attestation::NitroAttestationDocument;
use sui::table::{Self, Table};

use fun to_pcrs as NitroAttestationDocument.to_pcrs;

const ENotRegistered: u64 = 0;
const EAlreadyRegistered: u64 = 1;
const EInvalidPublicKeyLength: u64 = 2;

// Expected public key lengths for secp256k1
const SECP256K1_PK_LENGTH_COMPRESSED: u64 = 33;
const SECP256K1_PK_LENGTH_UNCOMPRESSED: u64 = 64;

// PCR0: Enclave image file
// PCR1: Enclave Kernel
// PCR2: Enclave application
// PCR16: Application image
public struct Pcrs(vector<u8>, vector<u8>, vector<u8>, vector<u8>) has copy, drop, store;

// One-time witness for module initialization
public struct ENCLAVE_REGISTRY has drop {}

// Shared registry mapping compressed secp256k1 public keys to their PCR values.
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

    assert!(!table::contains(&registry.enclaves, pk), EAlreadyRegistered);
    table::add(&mut registry.enclaves, pk, pcrs);
}

/// Check if a public key is registered in the registry.
public fun is_registered(registry: &Registry, pk: &vector<u8>): bool {
    table::contains(&registry.enclaves, *pk)
}

/// Get the PCR values for a registered public key.
public fun get_pcrs(registry: &Registry, pk: &vector<u8>): &Pcrs {
    assert!(table::contains(&registry.enclaves, *pk), ENotRegistered);
    table::borrow(&registry.enclaves, *pk)
}

// PCR accessors
public fun pcr_0(pcrs: &Pcrs): &vector<u8> { &pcrs.0 }
public fun pcr_1(pcrs: &Pcrs): &vector<u8> { &pcrs.1 }
public fun pcr_2(pcrs: &Pcrs): &vector<u8> { &pcrs.2 }
public fun pcr_16(pcrs: &Pcrs): &vector<u8> { &pcrs.3 }

fun load_pk(document: &NitroAttestationDocument): vector<u8> {
    let mut pk = (*document.public_key()).destroy_some();

    // If uncompressed, convert to compressed format
    if (pk.length() == SECP256K1_PK_LENGTH_UNCOMPRESSED) {
        pk = compress_secp256k1_pubkey(&pk);
    };

    // Validate compressed secp256k1 public key length
    assert!(
        pk.length() == SECP256K1_PK_LENGTH_COMPRESSED,
        EInvalidPublicKeyLength
    );

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
