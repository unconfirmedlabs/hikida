// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: MIT

#[test_only]
module hikida::hikida_tests;

use hikida::hikida;
use std::unit_test::assert_eq;
use sui::accumulator::{Self, AccumulatorRoot};
use sui::balance;
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};
use sui::transfer::Receiving;

//=== Constants ===

const OWNER: address = @0x0;
const RECIPIENT: address = @0xBEEF;

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
fun receive_coins_as_balance_single_coin() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    scenario.next_tx(OWNER);
    let coin_id = send_coin(&mut scenario, vault_addr, 100);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(coin_id);
    let balance = hikida::receive_coins_as_balance(&mut vault.id, vector[ticket]);
    assert_eq!(balance.value(), 100);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun receive_coins_as_balance_multiple_coins() {
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
    let balance = hikida::receive_coins_as_balance(&mut vault.id, tickets);
    assert_eq!(balance.value(), 60);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun receive_coins_as_balance_into_coin() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    scenario.next_tx(OWNER);
    let coin_id = send_coin(&mut scenario, vault_addr, 42);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(coin_id);
    let coin = hikida::receive_coins_as_balance(&mut vault.id, vector[ticket]).into_coin(scenario.ctx());
    assert_eq!(coin.value(), 42);
    coin.burn_for_testing();
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun receive_coins_as_balance_empty_vector_is_zero() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let tickets: vector<Receiving<Coin<SUI>>> = vector[];
    let balance = hikida::receive_coins_as_balance(&mut vault.id, tickets);
    assert_eq!(balance.value(), 0);
    balance.destroy_zero();
    scenario.return_to_sender(vault);
    scenario.end();
}

/// Coins sent to the vault are received and forwarded to the vault's own
/// accumulator; the next transaction can redeem them.
#[test]
fun receive_coins_and_send_funds_to_self_round_trip() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    scenario.next_tx(OWNER);
    let id1 = send_coin(&mut scenario, vault_addr, 15);
    let id2 = send_coin(&mut scenario, vault_addr, 25);

    scenario.next_tx(OWNER);
    {
        let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
        let tickets = vector[
            test_scenario::receiving_ticket_by_id<Coin<SUI>>(id1),
            test_scenario::receiving_ticket_by_id<Coin<SUI>>(id2),
        ];
        let forwarded = hikida::receive_coins_and_send_funds(&mut vault.id, tickets, vault_addr);
        assert_eq!(forwarded, 40);
        scenario.return_to_sender(vault);
    };

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let balance = hikida::redeem_balance<SUI>(&mut vault.id, 40);
    assert_eq!(balance.value(), 40);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun receive_coins_and_send_funds_empty_is_noop() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let tickets: vector<Receiving<Coin<SUI>>> = vector[];
    assert_eq!(hikida::receive_coins_and_send_funds(&mut vault.id, tickets, RECIPIENT), 0);
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

/// Zero is answered without touching the accumulator: the vault has no
/// funds at all, and the call still succeeds with a zero balance.
#[test]
fun redeem_balance_zero_value_is_zero() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let balance = hikida::redeem_balance<SUI>(&mut vault.id, 0);
    assert_eq!(balance.value(), 0);
    balance.destroy_zero();
    scenario.return_to_sender(vault);
    scenario.end();
}

/// Funds accumulated on the vault are redeemed and forwarded to another
/// object's address; that object can then redeem them.
#[test]
fun redeem_balance_and_send_funds_forwards() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    let vault_addr = vault_id.to_address();

    // A second vault, whose address stands in for the recipient.
    let sink = Vault { id: object::new(scenario.ctx()) };
    let sink_id = object::id(&sink);
    let sink_addr = sink_id.to_address();
    transfer::public_transfer(sink, OWNER);

    balance::send_funds(balance::create_for_testing<SUI>(100), vault_addr);

    scenario.next_tx(OWNER);
    {
        let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
        assert_eq!(hikida::redeem_balance_and_send_funds<SUI>(&mut vault.id, 60, sink_addr), 60);
        scenario.return_to_sender(vault);
    };

    scenario.next_tx(OWNER);
    let mut sink = scenario.take_from_sender_by_id<Vault>(sink_id);
    let balance = hikida::redeem_balance<SUI>(&mut sink.id, 60);
    assert_eq!(balance.value(), 60);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(sink);
    scenario.end();
}

#[test]
fun redeem_balance_and_send_funds_zero_is_noop() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    assert_eq!(hikida::redeem_balance_and_send_funds<SUI>(&mut vault.id, 0, RECIPIENT), 0);
    scenario.return_to_sender(vault);
    scenario.end();
}

/// Redeem accumulated funds from the vault address, turn them into a coin,
/// send the coin to the vault address, then receive it back through
/// `receive_coins_as_balance`.
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
        let coin = hikida::redeem_balance<SUI>(&mut vault.id, 100).into_coin(scenario.ctx());
        coin_id = object::id(&coin);
        transfer::public_transfer(coin, vault_addr);
        scenario.return_to_sender(vault);
    };

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let ticket = test_scenario::receiving_ticket_by_id<Coin<SUI>>(coin_id);
    let balance = hikida::receive_coins_as_balance(&mut vault.id, vector[ticket]);
    assert_eq!(balance.value(), 100);
    balance::destroy_for_testing(balance);
    scenario.return_to_sender(vault);
    scenario.end();
}

//=== Settled funds ===
//
// The settled snapshot is written only by the system at consensus
// settlement, which the unit VM never runs, so `settled_funds_value` always
// reads zero here. These tests pin the zero path of all three settled
// functions; the positive path is exercised on a network (see AUDIT.md).

#[test]
fun settled_balance_value_reads_zero_before_any_settlement() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    accumulator::create_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);
    let vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let root = scenario.take_shared<AccumulatorRoot>();
    assert_eq!(hikida::settled_balance_value<SUI>(&vault.id, &root), 0);
    test_scenario::return_shared(root);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun redeem_settled_balance_with_nothing_settled_is_zero() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    accumulator::create_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let root = scenario.take_shared<AccumulatorRoot>();
    let balance = hikida::redeem_settled_balance<SUI>(&mut vault.id, &root);
    assert_eq!(balance.value(), 0);
    balance.destroy_zero();
    test_scenario::return_shared(root);
    scenario.return_to_sender(vault);
    scenario.end();
}

#[test]
fun redeem_settled_balance_and_send_funds_with_nothing_settled_is_noop() {
    let mut scenario = test_scenario::begin(OWNER);
    let vault_id = setup(&mut scenario);
    accumulator::create_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);
    let mut vault = scenario.take_from_sender_by_id<Vault>(vault_id);
    let root = scenario.take_shared<AccumulatorRoot>();
    assert_eq!(hikida::redeem_settled_balance_and_send_funds<SUI>(&mut vault.id, &root, RECIPIENT), 0);
    test_scenario::return_shared(root);
    scenario.return_to_sender(vault);
    scenario.end();
}
