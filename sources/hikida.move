module hikida::hikida;

use sui::balance::{Balance, redeem_funds, withdraw_funds_from_object};
use sui::coin::Coin;
use sui::transfer::{Receiving, public_receive};

//=== Constants ===

const ENoCoinsToReceive: u64 = 0;
const ENoValueToRedeem: u64 = 1;

//=== Public Functions ===

public fun receive_balance<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    receive_balance_impl(parent, coins)
}

public fun receive_coin<Currency>(
    parent: &mut UID,
    coins: vector<Receiving<Coin<Currency>>>,
    ctx: &mut TxContext,
): Coin<Currency> {
    receive_balance_impl(parent, coins).into_coin(ctx)
}

public fun redeem_balance<Currency>(parent: &mut UID, value: u64): Balance<Currency> {
    redeem_balance_impl<Currency>(parent, value)
}

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
    mut coins: vector<Receiving<Coin<Currency>>>,
): Balance<Currency> {
    assert!(!coins.is_empty(), ENoCoinsToReceive);
    let mut balance = public_receive(parent, coins.pop_back()).into_balance();
    coins.destroy!(|c| {
        balance.join(public_receive(parent, c).into_balance());
    });
    balance
}

fun redeem_balance_impl<Currency>(parent: &mut UID, value: u64): Balance<Currency> {
    assert!(value > 0, ENoValueToRedeem);
    redeem_funds(withdraw_funds_from_object(parent, value))
}
