#[test_only]
module oyster_demo::oyster_demo_tests;

use sui::test_scenario::{Self as ts};
use enclave::enclave;
use oyster_demo::oyster_demo;

const ADMIN: address = @0x1;

#[test]
fun test_oracle_creation() {
    let mut scenario = ts::begin(ADMIN);

    // Publish creates the oracle and admin cap via init
    ts::next_tx(&mut scenario, ADMIN);
    {
        oyster_demo::init_for_testing(ts::ctx(&mut scenario));
    };

    // Verify the oracle was created and shared
    ts::next_tx(&mut scenario, ADMIN);
    {
        let oracle = ts::take_shared<oyster_demo::PriceOracle>(&scenario);
        assert!(oyster_demo::get_latest_timestamp(&oracle) == 0);
        ts::return_shared(oracle);
    };

    ts::end(scenario);
}

#[test]
fun test_registry_creation() {
    let mut scenario = ts::begin(ADMIN);

    // Create registry via enclave init
    ts::next_tx(&mut scenario, ADMIN);
    {
        enclave::init_for_testing(ts::ctx(&mut scenario));
    };

    // Verify the registry was created and shared
    ts::next_tx(&mut scenario, ADMIN);
    {
        let registry = ts::take_shared<enclave::EnclaveRegistry>(&scenario);
        // Registry should be empty initially
        let dummy_pk = x"020000000000000000000000000000000000000000000000000000000000000000";
        assert!(!enclave::is_registered(&registry, &dummy_pk));
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_pcrs_construction() {
    let pcr0 = x"aa";
    let pcr1 = x"bb";
    let pcr2 = x"cc";
    let pcr16 = x"dd";

    let pcrs = enclave::new_pcrs(pcr0, pcr1, pcr2, pcr16);

    assert!(*enclave::pcr_0(&pcrs) == x"aa");
    assert!(*enclave::pcr_1(&pcrs) == x"bb");
    assert!(*enclave::pcr_2(&pcrs) == x"cc");
    assert!(*enclave::pcr_16(&pcrs) == x"dd");
}
