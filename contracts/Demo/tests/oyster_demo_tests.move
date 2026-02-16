#[test_only]
module oyster_demo::oyster_demo_tests;

use sui::test_scenario::{Self as ts};
use enclave_registry::enclave_registry;
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
        // Oracle exists as shared object - creation successful
        ts::return_shared(oracle);

        // AdminCap transferred to deployer
        let cap = ts::take_from_sender<oyster_demo::AdminCap>(&scenario);
        ts::return_to_sender(&scenario, cap);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_get_latest_timestamp_reverts_when_empty() {
    let mut scenario = ts::begin(ADMIN);

    ts::next_tx(&mut scenario, ADMIN);
    {
        oyster_demo::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let oracle = ts::take_shared<oyster_demo::PriceOracle>(&scenario);
        // Should revert with ENoPriceAvailable since no prices have been submitted
        let _ = oyster_demo::get_latest_timestamp(&oracle);
        ts::return_shared(oracle);
    };

    ts::end(scenario);
}

#[test]
#[expected_failure]
fun test_get_latest_price_reverts_when_empty() {
    let mut scenario = ts::begin(ADMIN);

    ts::next_tx(&mut scenario, ADMIN);
    {
        oyster_demo::init_for_testing(ts::ctx(&mut scenario));
    };

    ts::next_tx(&mut scenario, ADMIN);
    {
        let oracle = ts::take_shared<oyster_demo::PriceOracle>(&scenario);
        // Should revert with ENoPriceAvailable
        let (_, _) = oyster_demo::get_latest_price(&oracle);
        ts::return_shared(oracle);
    };

    ts::end(scenario);
}

#[test]
fun test_set_registry() {
    let mut scenario = ts::begin(ADMIN);

    ts::next_tx(&mut scenario, ADMIN);
    {
        oyster_demo::init_for_testing(ts::ctx(&mut scenario));
        enclave_registry::init_for_testing(ts::ctx(&mut scenario));
    };

    // Admin sets the registry
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut oracle = ts::take_shared<oyster_demo::PriceOracle>(&scenario);
        let cap = ts::take_from_sender<oyster_demo::AdminCap>(&scenario);
        let registry = ts::take_shared<enclave_registry::Registry>(&scenario);

        oyster_demo::set_registry_for_testing(&mut oracle, &cap, &registry);

        ts::return_shared(oracle);
        ts::return_to_sender(&scenario, cap);
        ts::return_shared(registry);
    };

    ts::end(scenario);
}

#[test]
fun test_update_expected_pcrs() {
    let mut scenario = ts::begin(ADMIN);

    ts::next_tx(&mut scenario, ADMIN);
    {
        oyster_demo::init_for_testing(ts::ctx(&mut scenario));
    };

    // Admin updates PCRs
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut oracle = ts::take_shared<oyster_demo::PriceOracle>(&scenario);
        let cap = ts::take_from_sender<oyster_demo::AdminCap>(&scenario);

        oyster_demo::update_expected_pcrs_for_testing(
            &mut oracle,
            &cap,
            x"aa", x"bb", x"cc", x"dd",
        );

        ts::return_shared(oracle);
        ts::return_to_sender(&scenario, cap);
    };

    ts::end(scenario);
}

#[test]
fun test_registry_creation() {
    let mut scenario = ts::begin(ADMIN);

    // Create registry via enclave init
    ts::next_tx(&mut scenario, ADMIN);
    {
        enclave_registry::init_for_testing(ts::ctx(&mut scenario));
    };

    // Verify the registry was created and shared
    ts::next_tx(&mut scenario, ADMIN);
    {
        let registry = ts::take_shared<enclave_registry::Registry>(&scenario);
        // Registry should be empty initially
        let dummy_pk = x"020000000000000000000000000000000000000000000000000000000000000000";
        assert!(!enclave_registry::is_registered(&registry, &dummy_pk));
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

    let pcrs = enclave_registry::new_pcrs(pcr0, pcr1, pcr2, pcr16);

    assert!(*enclave_registry::pcr_0(&pcrs) == x"aa");
    assert!(*enclave_registry::pcr_1(&pcrs) == x"bb");
    assert!(*enclave_registry::pcr_2(&pcrs) == x"cc");
    assert!(*enclave_registry::pcr_16(&pcrs) == x"dd");
}
