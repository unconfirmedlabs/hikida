# hikida

Thin, audited helpers for receiving coins sent to Sui object addresses and
withdrawing object-accumulated funds — batch `Receiving<Coin>` handling,
forwarding received value onward, and
`redeem_funds(withdraw_funds_from_object(...))` in four small wrappers. The
verb names the source: `receive_*` takes `Coin` objects sent to the object,
`redeem_*` takes funds accumulated on its address. Outgoing value always
leaves as accumulator funds (`balance::send_funds`), never as a coin object.

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
| `receive_coins<Currency>(parent, coins, ctx): Coin<Currency>` | Batch-receive a vector of `Receiving<Coin<Currency>>` tickets into `parent`, merged into one `Coin` (call `.into_balance()` for a `Balance`). |
| `receive_coins_and_send_funds<Currency>(parent, coins, recipient): u64` | Receive the tickets and forward the combined value to `recipient`'s funds accumulator (`balance::send_funds`). Returns the value forwarded. |
| `redeem_balance<Currency>(parent, value): Balance<Currency>` | Withdraw `value` of `Currency` accumulated on the object's address (`withdraw_funds_from_object` + `redeem_funds`). |
| `redeem_coin<Currency>(parent, value, ctx): Coin<Currency>` | Same, returned as a `Coin`. |

### Every function is total

There are no error codes. Receiving no coins returns a zero coin; redeeming
zero returns a zero balance or zero coin without touching the accumulator;
forwarding nothing forwards nothing and returns 0. Callers that
want strictness assert on the returned value. This matches the framework's own
value-returning primitives (`balance::withdraw_all`, `pay::join_vec` over an
empty vector, `balance::zero`, `coin::zero`), which are total and reserve
aborts for malformed arguments. The only aborts you can hit come from the
framework itself: a `Receiving` ticket for an object the parent does not own,
or a withdrawal larger than the accumulated balance.

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
let coin = hikida::receive_coins<SUI>(object.uid_mut(), receiving_tickets, ctx);

// Withdraw funds accumulated on the object's address:
let coin = hikida::redeem_coin<SUI>(object.uid_mut(), amount, ctx);

// Convert coins stuck at an object's address into accumulator funds at that
// same address, so canonical accumulator logic can take over:
let forwarded = hikida::receive_coins_and_send_funds<SUI>(
    object.uid_mut(), receiving_tickets, object.uid().to_address(),
);
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
**no issues found.** See [AUDIT.md](AUDIT.md) for the full report and the
2026-09-09 addendum covering the total API and the two forwarding functions.
The wrappers add no privilege beyond what the framework's `public_receive`,
`send_funds`, and funds-withdrawal natives already enforce.

## Development

```sh
sui move build          # build
sui move test           # run the test suite (15 tests)
sui move build --lint   # lint
```

## License

MIT — see [LICENSE](LICENSE). © Unconfirmed Labs, LLC.
