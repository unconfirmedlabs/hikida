// Copyright (c) Unconfirmed Labs, LLC
// SPDX-License-Identifier: MIT

/// Thin helpers for moving value between an object's address and Move
/// values. The verb names the source: `receive_*` takes `Coin` objects sent
/// to the object, `redeem_*` takes funds accumulated on its address.
///
/// Every function is total. Receiving no coins yields a zero balance or zero
/// coin; redeeming zero yields a zero balance or zero coin without touching
/// the accumulator; forwarding nothing forwards nothing and returns 0. A
/// caller that wants strictness asserts on the returned value. This follows
/// the framework's own value-returning primitives (`balance::withdraw_all`,
/// `pay::join_vec` over an empty vector, `balance::zero`, `coin::zero`),
/// which are total, and reserves aborts for malformed arguments, of which
/// this module has none.
module hikida::hikida;

use sui::balance::{Self, Balance, redeem_funds, withdraw_funds_from_object};
use sui::coin::{Self, Coin};
use sui::transfer::{Receiving, public_receive};

//=== Public Functions ===

/// Receive every `Coin<Currency>` in `coins` into `parent` and return their
/// combined value as one coin. Empty `coins` returns a zero coin.
public fun receive_coins<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
    ctx: &mut TxContext,
): Coin<Currency> {
    receive_balance_impl(parent, coins).into_coin(ctx)
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

/// Receive every coin in `coins` into `parent`, merge them into one `Coin`,
/// and transfer that coin object to `recipient`. Returns the value
/// transferred. Empty `coins` creates and transfers nothing and returns 0.
public fun receive_coins_and_transfer<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
    recipient: address,
    ctx: &mut TxContext,
): u64 {
    let received = receive_balance_impl(parent, coins);
    let value = received.value();
    if (value == 0) {
        received.destroy_zero();
        return 0
    };
    transfer::public_transfer(received.into_coin(ctx), recipient);
    value
}

/// Withdraw `value` of `Currency` accumulated on `parent`'s address. Zero
/// returns a zero balance without touching the accumulator.
public fun redeem_balance<Currency>(parent: &mut UID, value: u64): Balance<Currency> {
    redeem_balance_impl<Currency>(parent, value)
}

/// Same as `redeem_balance`, returned as a `Coin`. Zero returns a zero coin.
public fun redeem_coin<Currency>(
    parent: &mut UID,
    value: u64,
    ctx: &mut TxContext,
): Coin<Currency> {
    redeem_balance_impl<Currency>(parent, value).into_coin(ctx)
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
