# UNLOCK (UNLK)

UNLOCK is a fixed-supply ERC-20. `src/UnlockToken.sol` mints **1,000,000,000 UNLK with 18 decimals** once, entirely to the immediate deployer in its constructor.

## Contract and assumptions

| Parameter | Value |
| --- | --- |
| Solidity contract | `UnlockToken` |
| Name | `UNLOCK` |
| Symbol | `UNLK` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0` |
| Intended launch chain | Ethereum, chain ID `1` |

The brief specifies no special transfer rules, so the implementation uses the unmodified OpenZeppelin Contracts v5.0.2 ERC-20 behavior:

- Transfers deliver the exact amount. There are no taxes, fees, rebases, or token callbacks.
- Zero-value transfers and self-transfers are supported. Transfers to the zero address revert.
- `approve` replaces the caller's allowance and emits `Approval`. `transferFrom` spends that allowance; `type(uint256).max` is treated as unlimited and is not decremented. Allowance consumption does not emit an additional `Approval` event in this implementation; read `allowance` for current state.
- Successful transfers return `true` and emit `Transfer`. Invalid recipients, insufficient balances, and insufficient allowances revert with OpenZeppelin custom errors. A revert also restores any allowance change.
- There is no owner, administrator, public mint/burn function, pause, blacklist, seizure, upgrade mechanism, or initializer. Metadata and supply cannot be changed after deployment.

Only the constructor calls `_mint`. The inherited mint/burn helpers are internal and have no callable runtime entry point in `UnlockToken`. Sending to the token contract itself is a normal transfer; the contract has no recovery function.

## Build and test

Run from the repository root with Foundry and Solidity 0.8.26 available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x6c9df8dd0fdec166a4304c6a32df367731bd944554bab7e1d5f3ad2c4ab8e752 forge test
forge fmt --check
```

`foundry.toml` pins Solidity **0.8.26**, the Cancun EVM target, optimizer enabled with 200 runs, and `bytecode_hash = "none"`. There is no FFI or filesystem permission requirement. All Solidity dependencies and their licenses are vendored as ordinary files in `lib/`; no network install or submodule is needed. See [DEPENDENCIES.md](DEPENDENCIES.md) for versions and integrity checks. The Solidity compiler and Foundry are build tools supplied by the execution environment, not repository dependencies.

The tests do not read or set environment variables, use RPC forks, or require credentials. The seed above configures Foundry's runner. The suite includes:

- Metadata, exact supply, a single constructor mint event, and CREATE2 factory deployment with an independent transaction origin.
- Transfers, full-balance and zero-value transfers, self-transfers, allowance replacement/revocation, finite and unlimited approvals, and standard events.
- Reverts for insufficient balance/allowance and zero addresses, with state rollback assertions.
- Unavailable mint, burn, admin, and upgrade entry points; executable-bytecode checks for forbidden delegation and destruction opcodes.
- Exact factory/distributor/recipient transfers and token movement in both pool-facing directions.
- Five fuzz tests with 1,000 cases each, plus 128 stateful invariant runs of 64 calls each checking supply conservation across transfers, approvals, and delegated transfers.

The local launch-flow test checks token accounting with test actors. It does not simulate Uniswap v4 pricing, liquidity, or swaps. The supplied protected tests require the network's separate factory/pool infrastructure and launch configuration; they are inputs to the later verifier, not standalone tests in this project.

## Deployment and operational responsibilities

Deploy the creation bytecode from `out/UnlockToken.sol/UnlockToken.json` with no appended constructor arguments and zero ETH. No initialization or configuration call follows deployment. The constructor neither calls external contracts nor requires any external address to have code.

**The immediate creator receives all tokens.** With `CREATE` or `CREATE2` through the launch factory, `msg.sender` is that factory, and it receives all `10^27` units. The transaction origin, requester, and token contract receive nothing in the constructor. A direct wallet deployment instead assigns the entire supply to that wallet. Deploy the contract itself, not a proxy or an intermediate helper that cannot distribute its balance.

For the specified launch, the external factory handles the 10% swarm allocation, 80% pool allocation, and remaining 10% requester allocation. Distribution, liquidity setup, and the opening market capitalization are launch responsibilities, not token parameters. No recipient, pool, distributor, router, or oracle address is needed by this token. The separate manifest stage supplies the launch configuration; this repository does not contain a launch manifest or a broadcasting script.

After deployment, the launch operator should verify the deployed source/settings, metadata, total supply, initial factory balance, and completed distribution. Holders control transfers and allowances thereafter. There are **no after-launch settings, privileged keys, keepers, or maintenance transactions** for the token.

Holders are responsible for custody and approval management. Use bounded approvals where possible; when replacing an existing allowance, revoke it and wait for confirmation before granting a new amount to reduce the standard approval-ordering risk. Transfers to an incorrect address or a contract without a withdrawal path cannot be recovered by an administrator.

## Security review scope

The implementation was reviewed against the supplied security reference for decimal scaling, authorization, exact transfer accounting, unchecked arithmetic assumptions, external calls, and upgrade/admin exposure. Production code adds only a supply constant and constructor to the vendored ERC-20. It has no external interaction or callback path, oracle, signature verification, value-bearing randomness, or custom financial arithmetic.

Local verification uses `forge build`, deterministic unit/fuzz/invariant tests, and `forge fmt --check`. Slither and Mythril were not run. These checks are not an independent audit; independent review and the protected launch checks remain part of the network's release process. No transactions were broadcast.
