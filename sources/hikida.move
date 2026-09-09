// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: MIT

/// Thin helpers for moving value between an object's address and Move
/// values. The verb names the source: `receive_*` takes `Coin` objects sent
/// to the object, `redeem_*` takes funds accumulated on its address.
/// Outgoing value always leaves as accumulator funds (`send_funds`), never
/// as a coin object.
///
/// Every function is total. Receiving no coins yields a zero balance;
/// redeeming zero yields a zero balance without touching the accumulator;
/// forwarding nothing forwards nothing and returns 0. A caller that wants
/// strictness asserts on the returned value. This follows the framework's
/// own value-returning primitives (`balance::withdraw_all`, `pay::join_vec`
/// over an empty vector, `balance::zero`), which are total, and reserves
/// aborts for malformed arguments, of which this module has none.
module hikida::hikida;

use sui::balance::{Self, Balance, redeem_funds, withdraw_funds_from_object};
use sui::coin::Coin;
use sui::transfer::{Receiving, public_receive};

//=== Public Functions ===

/// Receive every `Coin<Currency>` in `coins` into `parent` and return their
/// combined value as one balance. Empty `coins` returns a zero balance.
public fun receive_coins_as_balance<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    receive_balance_impl(parent, coins)
}

/// Receive every coin in `coins` into `parent` and forward the combined
/// value to `recipient`'s funds accumulator (`balance::send_funds`). Returns
/// the value forwarded. Empty `coins` forwards nothing and returns 0.
public fun receive_coins_and_send_funds<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
    recipient: address,
): u64 {
    let received = receive_balance_impl(parent, coins);
    let value = received.value();
    if (value == 0) {
        received.destroy_zero();
        return 0
    };
    received.send_funds(recipient);
    value
}

/// Withdraw `value` of `Currency` accumulated on `parent`'s address. Zero
/// returns a zero balance without touching the accumulator.
public fun redeem_balance<Currency>(parent: &mut UID, value: u64): Balance<Currency> {
    redeem_balance_impl<Currency>(parent, value)
}

/// Withdraw `value` of `Currency` accumulated on `parent`'s address and
/// forward it to `recipient`'s funds accumulator. Returns the value
/// forwarded. Zero forwards nothing and returns 0.
public fun redeem_balance_and_send_funds<Currency>(
    parent: &mut UID,
    value: u64,
    recipient: address,
): u64 {
    if (value == 0) return 0;
    redeem_balance_impl<Currency>(parent, value).send_funds(recipient);
    value
}

//=== Private Functions ===

fun receive_balance_impl<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    let mut total = balance::zero<Currency>();
    coins.destroy!(|ticket| {
        total.join(public_receive(parent, ticket).into_balance());
    });
    total
}

fun redeem_balance_impl<Currency>(parent: &mut UID, value: u64): Balance<Currency> {
    if (value == 0) return balance::zero();
    redeem_funds(withdraw_funds_from_object(parent, value))
}
