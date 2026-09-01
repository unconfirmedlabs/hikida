# hikida

Thin, audited helpers for receiving coins sent to Sui object addresses and
withdrawing object-accumulated funds — batch `Receiving<Coin>` handling and
`redeem_funds(withdraw_funds_from_object(...))` in four one-liner wrappers.

## Why

Objects on Sui can own coins via transfer-to-object, and can accumulate funds
directly on their address (e.g. from withdrawals or sponsored flows). Working
with these primitives from Move is verbose: you must `public_receive` each
`Receiving` ticket one at a time, and combine `withdraw_funds_from_object`
with `redeem_funds`. `hikida` packages both patterns into small, safe
functions you can call from your own modules — used in production by the Miso
vault plugins.

## API

All functions take the parent object's `&mut UID`, so only code that already
has mutable access to the object can pull funds into or out of it.

| Function | Description |
| --- | --- |
| `receive_balance<Currency>(parent, coins): Balance<Currency>` | Batch-receive a vector of `Receiving<Coin<Currency>>` tickets into `parent`, joined into a single balance. |
| `receive_coin<Currency>(parent, coins, ctx): Coin<Currency>` | Same, returned as a `Coin`. |
| `redeem_balance<Currency>(parent, value): Balance<Currency>` | Withdraw `value` of `Currency` accumulated on the object's address (`withdraw_funds_from_object` + `redeem_funds`). |
| `redeem_coin<Currency>(parent, value, ctx): Coin<Currency>` | Same, returned as a `Coin`. |

### Errors

| Code | Constant | Condition |
| --- | --- | --- |
| 0 | `ENoCoinsToReceive` | `coins` vector is empty. |
| 1 | `ENoValueToRedeem` | `value` is zero. |

## Usage

Add the dependency to your `Move.toml`:

```toml
[dependencies]
hikida = { git = "https://github.com/unconfirmedlabs/hikida.git", rev = "main" }
```

Then call it from your module:

```move
use hikida::hikida;

// Collect coins transferred to an object address:
let balance = hikida::receive_balance<SUI>(object.uid_mut(), receiving_tickets);

// Withdraw funds accumulated on the object's address:
let coin = hikida::redeem_coin<SUI>(object.uid_mut(), amount, ctx);
```

## Published packages

Both deployments are immutable.

| Network | Package ID | Transaction digest |
| --- | --- | --- |
| Mainnet | `0x59b4ffcd0d3d3563cafa66f54f8de2f481d5186e1505bd44aff195fd72995d64` | `8MWTjJUaTCRvHosLjmVMRcMMCsxkLiGCNp1eaShbhwZx` |
| Testnet | `0xd15783a6a4c6928f4381551c700e99838c4064aa9e32ee46f5065845ecc721eb` | `9ZWaKTf3ofEBcszNqoVbRcC81ahivuEAzQvAd1poed7P` |

**Note:** `redeem_*` depends on the `enable_object_funds_withdraw` protocol
flag; on networks where it is disabled they abort with the framework's error.

## Security

Independently audited 2026-08-22 (revision `e88c6fa`, toolchain sui 1.77.2):
**no issues found.** See [AUDIT.md](AUDIT.md) for the full report. The
wrappers add no privilege beyond what the framework's `public_receive` and
funds-withdrawal natives already enforce.

## Development

```sh
sui move build          # build
sui move test           # run the test suite (9 tests)
sui move build --lint   # lint
```

## License

MIT — see [LICENSE](LICENSE). © Unconfirmed Labs, LLC.
