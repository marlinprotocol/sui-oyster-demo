#[test_only]
module enclave_registry::enclave_registry_tests;

use sui::test_scenario::{Self as ts};
use enclave_registry::enclave_registry;

const ADMIN: address = @0x1;

// ════════════════════════════════════════════════════════════════════
// Registry lifecycle
// ════════════════════════════════════════════════════════════════════

#[test]
fun test_registry_creation() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
fun test_empty_registry_not_registered() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk = x"020000000000000000000000000000000000000000000000000000000000000000";
        assert!(!enclave_registry::is_registered(&registry, &pk));
        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 0, location = enclave_registry)] // ENotRegistered
fun test_get_pcrs_unregistered_aborts() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk = x"020000000000000000000000000000000000000000000000000000000000000000";
        let _ = enclave_registry::get_pcrs(&registry, &pk);
        ts::return_shared(registry);
    };
    ts::end(scenario);
}

// ════════════════════════════════════════════════════════════════════
// PCR construction + accessors
// ════════════════════════════════════════════════════════════════════

#[test]
fun test_pcrs_construction_and_accessors() {
    let pcrs = enclave_registry::new_pcrs(x"aabbccdd", x"11223344", x"55667788", x"99aabbcc");
    assert!(*enclave_registry::pcr_0(&pcrs) == x"aabbccdd");
    assert!(*enclave_registry::pcr_1(&pcrs) == x"11223344");
    assert!(*enclave_registry::pcr_2(&pcrs) == x"55667788");
    assert!(*enclave_registry::pcr_16(&pcrs) == x"99aabbcc");
}

#[test]
fun test_pcrs_with_48_byte_values() {
    let pcr0 = x"000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    let pcr1 = x"111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111";
    let pcr2 = x"222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222";
    let pcr16 = x"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef01234567";
    let pcrs = enclave_registry::new_pcrs(pcr0, pcr1, pcr2, pcr16);
    assert!(*enclave_registry::pcr_0(&pcrs) == pcr0);
    assert!(*enclave_registry::pcr_1(&pcrs) == pcr1);
    assert!(*enclave_registry::pcr_2(&pcrs) == pcr2);
    assert!(*enclave_registry::pcr_16(&pcrs) == pcr16);
}

#[test]
fun test_pcrs_with_empty_vectors() {
    let pcrs = enclave_registry::new_pcrs(
        vector::empty(), vector::empty(), vector::empty(), vector::empty(),
    );
    assert!(enclave_registry::pcr_0(&pcrs).is_empty());
    assert!(enclave_registry::pcr_1(&pcrs).is_empty());
    assert!(enclave_registry::pcr_2(&pcrs).is_empty());
    assert!(enclave_registry::pcr_16(&pcrs).is_empty());
}

// ════════════════════════════════════════════════════════════════════
// PCR equality / inequality (structural)
// ════════════════════════════════════════════════════════════════════

#[test]
fun test_pcrs_equality() {
    let a = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    let b = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    assert!(a == b);
}

#[test]
fun test_pcrs_inequality_pcr0() {
    let a = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    let b = enclave_registry::new_pcrs(x"ff", x"bb", x"cc", x"dd");
    assert!(a != b);
}

#[test]
fun test_pcrs_inequality_pcr1() {
    let a = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    let b = enclave_registry::new_pcrs(x"aa", x"ff", x"cc", x"dd");
    assert!(a != b);
}

#[test]
fun test_pcrs_inequality_pcr2() {
    let a = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    let b = enclave_registry::new_pcrs(x"aa", x"bb", x"ff", x"dd");
    assert!(a != b);
}

#[test]
fun test_pcrs_inequality_pcr16() {
    let a = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    let b = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"ff");
    assert!(a != b);
}

#[test]
fun test_pcrs_inequality_different_lengths() {
    let a = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
    let b = enclave_registry::new_pcrs(x"aabb", x"bb", x"cc", x"dd");
    assert!(a != b);
}

// ════════════════════════════════════════════════════════════════════
// compress_secp256k1_pubkey (64 → 33)
// ════════════════════════════════════════════════════════════════════

#[test]
fun test_compress_even_y() {
    // X = 32 x 0x01, Y last byte = 0x04 (even)
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { key.push_back(0x01); i = i + 1; };
    i = 0;
    while (i < 31) { key.push_back(0x02); i = i + 1; };
    key.push_back(0x04);

    let c = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
    assert!(c.length() == 33);
    assert!(c[0] == 0x02);
    i = 0;
    while (i < 32) { assert!(c[i + 1] == 0x01); i = i + 1; };
}

#[test]
fun test_compress_odd_y() {
    // X = 32 x 0xAA, Y last byte = 0x03 (odd)
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { key.push_back(0xAA); i = i + 1; };
    i = 0;
    while (i < 31) { key.push_back(0x00); i = i + 1; };
    key.push_back(0x03);

    let c = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
    assert!(c.length() == 33);
    assert!(c[0] == 0x03);
    i = 0;
    while (i < 32) { assert!(c[i + 1] == 0xAA); i = i + 1; };
}

#[test]
fun test_compress_y_zero_is_even() {
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { key.push_back(0xFF); i = i + 1; };
    i = 0;
    while (i < 32) { key.push_back(0x00); i = i + 1; };
    let c = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
    assert!(c[0] == 0x02);
}

#[test]
fun test_compress_y_one_is_odd() {
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { key.push_back(0xFF); i = i + 1; };
    i = 0;
    while (i < 31) { key.push_back(0x00); i = i + 1; };
    key.push_back(0x01);
    let c = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
    assert!(c[0] == 0x03);
}

#[test]
fun test_compress_y_ff_is_odd() {
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { key.push_back(0x00); i = i + 1; };
    i = 0;
    while (i < 32) { key.push_back(0xFF); i = i + 1; };
    let c = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
    assert!(c[0] == 0x03);
}

#[test]
fun test_compress_preserves_distinct_x_bytes() {
    // X = 0x00..0x1F (32 distinct bytes), Y = all zeros
    let mut key = vector::empty<u8>();
    let mut i: u8 = 0;
    while ((i as u64) < 32) { key.push_back(i); i = i + 1; };
    i = 0;
    while ((i as u64) < 32) { key.push_back(0x00); i = i + 1; };

    let c = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
    assert!(c[0] == 0x02);
    i = 0;
    while ((i as u64) < 32) {
        assert!(c[(i as u64) + 1] == i);
        i = i + 1;
    };
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_compress_empty_aborts() {
    let _ = enclave_registry::compress_secp256k1_pubkey_for_testing(&vector::empty());
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_compress_5_bytes_aborts() {
    let _ = enclave_registry::compress_secp256k1_pubkey_for_testing(&x"0102030405");
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_compress_33_bytes_aborts() {
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 33) { key.push_back(0x02); i = i + 1; };
    let _ = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_compress_65_bytes_aborts() {
    let mut key = vector::empty<u8>();
    let mut i = 0;
    while (i < 65) { key.push_back(0x04); i = i + 1; };
    let _ = enclave_registry::compress_secp256k1_pubkey_for_testing(&key);
}

// ════════════════════════════════════════════════════════════════════
// normalize_pk — every branch of load_pk's key processing
// ════════════════════════════════════════════════════════════════════

// --- 33-byte compressed secp256k1 (passthrough) ---

#[test]
fun test_normalize_33_byte_prefix_02() {
    // 0x02 + 32 zero bytes → returned as-is
    let mut pk = vector::empty<u8>();
    pk.push_back(0x02);
    let mut i = 0;
    while (i < 32) { pk.push_back(0x00); i = i + 1; };

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 33);
    assert!(result[0] == 0x02);
}

#[test]
fun test_normalize_33_byte_prefix_03() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x03);
    let mut i = 0;
    while (i < 32) { pk.push_back(0xFF); i = i + 1; };

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 33);
    assert!(result[0] == 0x03);
    // X coordinate preserved
    i = 0;
    while (i < 32) { assert!(result[i + 1] == 0xFF); i = i + 1; };
}

#[test]
#[expected_failure(abort_code = 5, location = enclave_registry)] // EInvalidCompressedPrefix
fun test_normalize_33_byte_prefix_00_aborts() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x00);
    let mut i = 0;
    while (i < 32) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 5, location = enclave_registry)] // EInvalidCompressedPrefix
fun test_normalize_33_byte_prefix_01_aborts() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x01);
    let mut i = 0;
    while (i < 32) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 5, location = enclave_registry)] // EInvalidCompressedPrefix
fun test_normalize_33_byte_prefix_04_aborts() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x04);
    let mut i = 0;
    while (i < 32) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 5, location = enclave_registry)] // EInvalidCompressedPrefix
fun test_normalize_33_byte_prefix_ff_aborts() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0xFF);
    let mut i = 0;
    while (i < 32) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

// --- 32-byte x25519 (passthrough) ---

#[test]
fun test_normalize_32_byte_x25519() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { pk.push_back(0xBB); i = i + 1; };

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 32);
    i = 0;
    while (i < 32) { assert!(result[i] == 0xBB); i = i + 1; };
}

#[test]
fun test_normalize_32_byte_all_zeros() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { pk.push_back(0x00); i = i + 1; };

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 32);
}

// --- 64-byte uncompressed secp256k1 (compress) ---

#[test]
fun test_normalize_64_byte_even_y() {
    // 64 bytes → should compress to 33 bytes with 0x02 prefix
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { pk.push_back(0x11); i = i + 1; };  // X
    i = 0;
    while (i < 31) { pk.push_back(0x00); i = i + 1; };
    pk.push_back(0x02); // even Y

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 33);
    assert!(result[0] == 0x02);
    i = 0;
    while (i < 32) { assert!(result[i + 1] == 0x11); i = i + 1; };
}

#[test]
fun test_normalize_64_byte_odd_y() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 32) { pk.push_back(0x22); i = i + 1; };  // X
    i = 0;
    while (i < 31) { pk.push_back(0x00); i = i + 1; };
    pk.push_back(0x01); // odd Y

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 33);
    assert!(result[0] == 0x03);
    i = 0;
    while (i < 32) { assert!(result[i + 1] == 0x22); i = i + 1; };
}

// --- 65-byte uncompressed with 0x04 prefix (strip + compress) ---

#[test]
fun test_normalize_65_byte_valid_prefix() {
    // 0x04 + 32-byte X + 32-byte Y → strip prefix → compress
    let mut pk = vector::empty<u8>();
    pk.push_back(0x04);
    let mut i = 0;
    while (i < 32) { pk.push_back(0x33); i = i + 1; };  // X
    i = 0;
    while (i < 31) { pk.push_back(0x00); i = i + 1; };
    pk.push_back(0x06); // even Y

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 33);
    assert!(result[0] == 0x02); // even Y
    i = 0;
    while (i < 32) { assert!(result[i + 1] == 0x33); i = i + 1; };
}

#[test]
fun test_normalize_65_byte_odd_y() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x04);
    let mut i = 0;
    while (i < 32) { pk.push_back(0x44); i = i + 1; };  // X
    i = 0;
    while (i < 31) { pk.push_back(0x00); i = i + 1; };
    pk.push_back(0x07); // odd Y

    let result = enclave_registry::normalize_pk_for_testing(pk);
    assert!(result.length() == 33);
    assert!(result[0] == 0x03); // odd Y
}

#[test]
#[expected_failure(abort_code = 4, location = enclave_registry)] // EInvalidUncompressedPrefix
fun test_normalize_65_byte_wrong_prefix_00() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x00); // wrong prefix
    let mut i = 0;
    while (i < 64) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 4, location = enclave_registry)] // EInvalidUncompressedPrefix
fun test_normalize_65_byte_wrong_prefix_02() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x02); // compressed prefix, not uncompressed
    let mut i = 0;
    while (i < 64) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 4, location = enclave_registry)] // EInvalidUncompressedPrefix
fun test_normalize_65_byte_wrong_prefix_03() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0x03);
    let mut i = 0;
    while (i < 64) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 4, location = enclave_registry)] // EInvalidUncompressedPrefix
fun test_normalize_65_byte_wrong_prefix_ff() {
    let mut pk = vector::empty<u8>();
    pk.push_back(0xFF);
    let mut i = 0;
    while (i < 64) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

// --- Invalid lengths ---

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_0_bytes_aborts() {
    let _ = enclave_registry::normalize_pk_for_testing(vector::empty());
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_1_byte_aborts() {
    let _ = enclave_registry::normalize_pk_for_testing(x"02");
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_31_bytes_aborts() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 31) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_34_bytes_aborts() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 34) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_63_bytes_aborts() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 63) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_66_bytes_aborts() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 66) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

#[test]
#[expected_failure(abort_code = 2, location = enclave_registry)] // EInvalidPublicKeyLength
fun test_normalize_128_bytes_aborts() {
    let mut pk = vector::empty<u8>();
    let mut i = 0;
    while (i < 128) { pk.push_back(0xAA); i = i + 1; };
    let _ = enclave_registry::normalize_pk_for_testing(pk);
}

// ════════════════════════════════════════════════════════════════════
// register_for_testing + is_registered + get_pcrs
// ════════════════════════════════════════════════════════════════════

#[test]
fun test_register_and_lookup() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk = x"020000000000000000000000000000000000000000000000000000000000000001";
        let pcrs = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");

        assert!(!enclave_registry::is_registered(&registry, &pk));
        enclave_registry::register_for_testing(&mut registry, pk, pcrs);
        assert!(enclave_registry::is_registered(&registry, &pk));

        let stored = enclave_registry::get_pcrs(&registry, &pk);
        assert!(*stored == pcrs);

        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
fun test_register_secp256k1_02_prefix() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        // 33-byte key with 0x02 prefix
        let pk = x"020000000000000000000000000000000000000000000000000000000000000001";
        let pcrs = enclave_registry::new_pcrs(x"a1", x"b1", x"c1", x"d1");
        enclave_registry::register_for_testing(&mut registry, pk, pcrs);
        assert!(enclave_registry::is_registered(&registry, &pk));
        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
fun test_register_secp256k1_03_prefix() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        // 33-byte key with 0x03 prefix
        let pk = x"030000000000000000000000000000000000000000000000000000000000000001";
        let pcrs = enclave_registry::new_pcrs(x"a2", x"b2", x"c2", x"d2");
        enclave_registry::register_for_testing(&mut registry, pk, pcrs);
        assert!(enclave_registry::is_registered(&registry, &pk));
        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
fun test_register_x25519_key() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        // 32-byte x25519 key
        let pk = x"0000000000000000000000000000000000000000000000000000000000000003";
        let pcrs = enclave_registry::new_pcrs(x"a3", x"b3", x"c3", x"d3");
        enclave_registry::register_for_testing(&mut registry, pk, pcrs);
        assert!(enclave_registry::is_registered(&registry, &pk));

        let stored = enclave_registry::get_pcrs(&registry, &pk);
        assert!(*enclave_registry::pcr_0(stored) == x"a3");
        assert!(*enclave_registry::pcr_16(stored) == x"d3");

        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
fun test_register_multiple_keys_isolation() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk1 = x"020000000000000000000000000000000000000000000000000000000000000001";
        let pk2 = x"030000000000000000000000000000000000000000000000000000000000000002";
        let pk3 = x"0000000000000000000000000000000000000000000000000000000000000003";

        let pcrs1 = enclave_registry::new_pcrs(x"a1", x"b1", x"c1", x"d1");
        let pcrs2 = enclave_registry::new_pcrs(x"a2", x"b2", x"c2", x"d2");
        let pcrs3 = enclave_registry::new_pcrs(x"a3", x"b3", x"c3", x"d3");

        enclave_registry::register_for_testing(&mut registry, pk1, pcrs1);
        enclave_registry::register_for_testing(&mut registry, pk2, pcrs2);
        enclave_registry::register_for_testing(&mut registry, pk3, pcrs3);

        // Each key maps to its own PCRs — no cross-contamination
        assert!(*enclave_registry::get_pcrs(&registry, &pk1) == pcrs1);
        assert!(*enclave_registry::get_pcrs(&registry, &pk2) == pcrs2);
        assert!(*enclave_registry::get_pcrs(&registry, &pk3) == pcrs3);

        // Unregistered key still not found
        let pk_unknown = x"020000000000000000000000000000000000000000000000000000000000000099";
        assert!(!enclave_registry::is_registered(&registry, &pk_unknown));

        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1, location = enclave_registry)] // EAlreadyRegistered
fun test_register_duplicate_aborts() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk = x"020000000000000000000000000000000000000000000000000000000000000001";
        let pcrs = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");

        enclave_registry::register_for_testing(&mut registry, pk, pcrs);
        enclave_registry::register_for_testing(&mut registry, pk, pcrs);

        ts::return_shared(registry);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 1, location = enclave_registry)] // EAlreadyRegistered
fun test_register_duplicate_different_pcrs_aborts() {
    // Same key with different PCRs should still abort
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk = x"020000000000000000000000000000000000000000000000000000000000000001";
        let pcrs1 = enclave_registry::new_pcrs(x"aa", x"bb", x"cc", x"dd");
        let pcrs2 = enclave_registry::new_pcrs(x"11", x"22", x"33", x"44");

        enclave_registry::register_for_testing(&mut registry, pk, pcrs1);
        enclave_registry::register_for_testing(&mut registry, pk, pcrs2);

        ts::return_shared(registry);
    };
    ts::end(scenario);
}

// ════════════════════════════════════════════════════════════════════
// get_pcrs accessor field correctness after registration
// ════════════════════════════════════════════════════════════════════

#[test]
fun test_get_pcrs_returns_correct_per_field_values() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    { enclave_registry::init_for_testing(ts::ctx(&mut scenario)); };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        let pk = x"020000000000000000000000000000000000000000000000000000000000000001";
        let pcr0 = x"aabbccdd11223344";
        let pcr1 = x"55667788";
        let pcr2 = x"99aabbcc";
        let pcr16 = x"ddeeff00";
        let pcrs = enclave_registry::new_pcrs(pcr0, pcr1, pcr2, pcr16);
        enclave_registry::register_for_testing(&mut registry, pk, pcrs);

        let stored = enclave_registry::get_pcrs(&registry, &pk);
        assert!(*enclave_registry::pcr_0(stored) == pcr0);
        assert!(*enclave_registry::pcr_1(stored) == pcr1);
        assert!(*enclave_registry::pcr_2(stored) == pcr2);
        assert!(*enclave_registry::pcr_16(stored) == pcr16);

        ts::return_shared(registry);
    };
    ts::end(scenario);
}
