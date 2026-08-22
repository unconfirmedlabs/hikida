// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: MIT

#[test_only]
module hikida::hikida_tests;

use hikida::hikida;
use std::unit_test::assert_eq;
use sui::balance;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::transfer::Receiving;

//=== Constants ===

// Mirrored from hikida::hikida (private there).
const ENoCoinsToReceive: u64 = 0;
const ENoValueToRedeem: u64 = 1;

const OWNER: address = @0x0;

//=== Structs ===

public struct Vault has key, store {
    id: UID,
}

//=== Helpers ===

/// Create a `Vault` owned by `OWNER` and return its object ID.
fun setup(scenario: &mut Scenario): ID {
    let vault = Vault { id: object::new(scenario.ctx()) };
    let id = object::id(&vault);
    transfer::public_transfer(vault, OWNER);
    id
}

/// Mint a `Coin<SUI>` of `value` and transfer it to `recipient`, returning
/// the new coin's object ID.
fun send_coin(scenario: &mut Scenario, recipient: address, value: u64): ID {
    let coin = coin::mint_for_testing<SUI>(value, scenario.ctx());
    let id = object::id(&coin);
    transfer::public_transfer(coin, recipient);
    id
}

//=== Tests ===

#[test]
fun receive_balance_single_coin() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    scenario.next_tx(OWNER);
    let coin_id = send_coin(&mut scenario, vault_addr, 100);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(coin_id);
    let balance = hikida::receive_balance(&mut vault.id, vector[ticket]);
    assert_eq!(balance.value(), 100);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun receive_balance_multiple_coins() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    scenario.next_tx(OWNER);
    let id1 = send_coin(&mut scenario, vault_addr, 10);
    let id2 = send_coin(&mut scenario, vault_addr, 20);
    let id3 = send_coin(&mut scenario, vault_addr, 30);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let tickets = vector[
        test_scenario::receiving_ticket_by_id<Coin<SUI>>(id1),
        test_scenario::receiving_ticket_by_id<Coin<SUI>>(id2),
        test_scenario::receiving_ticket_by_id<Coin<SUI>>(id3),
    ];
    let balance = hikida::receive_balance(&mut vault.id, tickets);
    assert_eq!(balance.value(), 60);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun receive_coin_single_coin() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    scenario.next_tx(OWNER);
    let coin_id = send_coin(&mut scenario, vault_addr, 42);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(coin_id);
    let coin = hikida::receive_coin(&mut vault.id, vector[ticket], scenario.ctx());
    assert_eq!(coin.value(), 42);
    coin.burn_for_testing();
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test, expected_failure(abort_code = ENoCoinsToReceive, location = hikida)]
fun receive_balance_empty_vector_aborts() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let tickets: vector<Receiving<Coin<SUI>>> = vector[];
    let balance = hikida::receive_balance(&mut vault.id, tickets);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun redeem_balance_partial() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    // Fund the vault address's accumulator with 100.
    balance::send_funds(balance::create_for_testing<SUI>(100), vault_addr);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let balance = hikida::redeem_balance<SUI>(&mut vault.id, 40);
    assert_eq!(balance.value(), 40);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun redeem_balance_full() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    balance::send_funds(balance::create_for_testing<SUI>(100), vault_addr);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let balance = hikida::redeem_balance<SUI>(&mut vault.id, 100);
    assert_eq!(balance.value(), 100);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun redeem_coin_partial() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    balance::send_funds(balance::create_for_testing<SUI>(100), vault_addr);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let coin = hikida::redeem_coin<SUI>(&mut vault.id, 25, scenario.ctx());
    assert_eq!(coin.value(), 25);
    coin.burn_for_testing();
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test, expected_failure(abort_code = ENoValueToRedeem, location = hikida)]
fun redeem_balance_zero_value_aborts() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let balance = hikida::redeem_balance<SUI>(&mut vault.id, 0);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

/// Redeem accumulated funds from the vault address, turn them into a coin,
/// send the coin to the vault address, then receive it back through
/// `receive_balance`.
#[test]
fun redeem_then_receive_round_trip() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    balance::send_funds(balance::create_for_testing<SUI>(100), vault_addr);

    scenario.next_tx(OWNER);
    let coin_id;
    {
        let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
        let coin = hikida::redeem_coin<SUI>(&mut vault.id, 100, scenario.ctx());
        coin_id = object::id(&coin);
        transfer::public_transfer(coin, vault_addr);
        scenario.return_to_sender(vault);
    };

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(coin_id);
    let balance = hikida::receive_balance(&mut vault.id, vector[ticket]);
    assert_eq!(balance.value(), 100);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}
