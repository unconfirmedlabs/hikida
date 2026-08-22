# Security Audit — `hikida`

**Revision:** `e88c6fa` (`main`; mainnet `0xda970ab9`) · **Date:** 2026-08-22 ·
**Toolchain:** sui 1.77.2

Audit of `hikida`, the receive/redeem helper used by the Miso vault plugins
to collect coins sent to object addresses and to withdraw object-accumulated
funds. Verdict: **safe to depend on as-is — no issues found.**

## What it is

Four thin wrappers (`sources/hikida.move`, 58 lines) over Sui's
transfer-to-object and funds-withdrawal primitives:

- `receive_balance` / `receive_coin` — batch-receive `Receiving<Coin>`
  tickets into a parent object (`&mut UID`), joined into one total; aborts
  `ENoCoinsToReceive` (0) on an empty vector.
- `redeem_balance` / `redeem_coin` — `redeem_funds(withdraw_funds_from_object(parent, value))`;
  aborts `ENoValueToRedeem` (1) on zero.

## Why it's safe

- **No privilege added or removed.** `public_receive` requires the parent's
  `&mut UID`, and the runtime additionally aborts unless the ticket's object
  is genuinely owned by that address. The wrappers are exactly as safe as
  calling the framework directly.
- **No forgery surface.** `Receiving` tickets are runtime-constructed and
  opaque; a single `Currency` type parameter per call prevents mixing.
- **No overdraw.** `withdraw_funds_from_object` only issues a
  `Withdrawal{owner, limit}` ticket; the debit happens in the `redeem_funds`
  native, which aborts if the limit exceeds the accumulated balance.
- **Gates are correct.** The empty-vector gate fires before `pop_back`
  (which would otherwise abort with a generic vector code); the zero-value
  gate is a UX/consistency guard.
- **Caller patterns verified downstream.** All four vault-plugin packages
  reach these wrappers through capability-gated `uid_mut(&cap)` inside
  vault-witness scopes; the permissionless crank paths route proceeds only
  into the canonical derived pool — funds cannot be redirected to a caller.

**Deployment note:** `redeem_*` depends on the `enable_object_funds_withdraw`
protocol flag; on a network with the flag off they abort with the framework's
error, not a hikida one. Downstream inherits this either way.

## Verification

- Line-by-line review against the pinned framework sources (`transfer.move`,
  `balance.move`, natives semantics).
- **9/9 tests passing** (previously zero — the repo shipped only the
  commented-out scaffold): both gate aborts, single/multi-coin receives with
  genuine `Receiving` tickets (10+20+30=60), partial and full redeems, and a
  redeem→transfer→receive round trip.
- `sui move build --lint --test` warning-clean.
- Org conventions: plain `u64` error constants mirrored in tests with
  `expected_failure(abort_code = …, location = hikida)`.

**Load-bearing assumptions:** framework `public_receive` ownership
re-authentication and the accumulator-native balance enforcement (verified at
the pinned rev; re-verify on framework change).
