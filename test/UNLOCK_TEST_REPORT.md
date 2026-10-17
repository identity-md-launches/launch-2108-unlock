# UNLOCK test additions

The existing implementation and tests are unchanged. The added suites use only the
already vendored dependencies and do not require a network, fork, credentials, FFI,
environment mutation, or files from `test/scratch/`.

The contract's permission and fund-flow model is simple: the constructor assigns
all `10^27` base units to its immediate deployer; holders transfer their balances;
spenders need allowances from the particular holder. No runtime mint, burn, or
administrative operation is exposed. Transfers have no external callback. The
existing suite covers metadata, constructor minting, factory distribution, events,
and the absence of administrative entry points.

`UnlockToken.adversarial.t.sol` adds 11 deterministic tests and five fuzz properties
(1,000 runs each). They cover one-base-unit accounting, self-spending authorization,
isolation between owners and spenders, allowance exhaustion, revocation of infinite
approval, finite `uint256.max - 1` approval, maximum-value rejection, approval before
funding, invalid zero addresses, and failed-call rollback. Algebraic properties
check exact transfer round trips and equivalence of split versus single delegated
spends. Tests require the expected custom errors, not just any revert.

`UnlockToken.accounting.invariant.t.sol` adds a four-actor handler with ten targeted
actions. It mixes successful transfers and approvals with insufficient-balance,
insufficient-allowance, invalid-address, and post-revocation attempts. Expected
balances are derived from recorded credits and debits; expected allowances are
derived from grants and successful spends. Neither oracle reads the corresponding
token getter to obtain its expected values. The invariants check:

- Every actor's balance equals its authorized net flows, including self-transfers.
- All balances sum to the specified supply, which stays fixed at `10^27`.
- Every owner/spender pair retains exactly its expected allowance.
- Rejected operations preserve the accounting and authorization state.
- Metadata stays `UNLOCK`, `UNLK`, and 18 decimals.

Inputs use `bound` without discarded assumptions. Zero, one, full-balance,
unlimited, and maximum-minus-one cases are deliberately exercised. A deterministic
handler test also pins a sequence with nonzero direct and delegated transfers and
eight expected failures. Unexpected handler reverts fail the campaign.

Verification used Forge 1.8.3 and Solidity 0.8.26. Build artifacts and analyzer
output were directed into disposable scratch paths to keep writes inside the
assignment's scope.

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x6c9df8dd0fdec166a4304c6a32df367731bd944554bab7e1d5f3ad2c4ab8e752 forge test --out test/scratch/out --cache-path test/scratch/cache

FOUNDRY_FUZZ_SEED=0x6c9df8dd0fdec166a4304c6a32df367731bd944554bab7e1d5f3ad2c4ab8e752 forge test --out test/scratch/out --cache-path test/scratch/cache --match-contract 'UnlockToken(Adversarial|AccountingInvariant)Test' -vv

forge fmt test/UnlockToken.adversarial.t.sol test/UnlockToken.accounting.invariant.t.sol
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x6c9df8dd0fdec166a4304c6a32df367731bd944554bab7e1d5f3ad2c4ab8e752 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

| Check | Result |
| --- | --- |
| Baseline build and tests | Passed; 30 tests before additions |
| Targeted added suites | Passed; 18 reported tests |
| Final offline build and full suite | Passed; 48 reported tests, zero failed or skipped |
| Stateless fuzzing across the full suite | Ten properties, 1,000 runs each |
| Added stateful campaign | 256 runs × 128 calls = 32,768 calls; zero unexpected reverts or discards |
| Original stateful campaign | 128 runs × 64 calls = 8,192 calls; zero unexpected reverts or discards |

Forge 1.8.3 groups the new suite's two invariant functions into one reported test;
both properties passed. Expected token reverts are checked inside the handler and
do not appear as unexpected handler reverts in the campaign statistics.

Static analysis commands:

```sh
forge build --out test/scratch/slither-out --cache-path test/scratch/slither-cache --build-info --build-info-path test/scratch/slither-out/build-info --skip test
slither . --foundry-ignore-compile --foundry-out-directory test/scratch/slither-out --foundry-build-info-directory test/scratch/slither-out/build-info --json test/scratch/slither.json
```

Slither 0.11.6 completed 102 detectors over eight contracts and returned exit 255
because it emitted two informational results: mixed pragma constraints and the
broad `^0.8.20` dependency version range. The actual build uses the pinned compiler
0.8.26; these advisories do not demonstrate a runtime defect in the tested token.
No concrete implementation defect was found, so no defect report was created.
These checks are not a proof of security.

Aderyn was not available on PATH and was not run. The supplied protected launch
checks were read but were not executable as standalone tests here: their external
factory/pool infrastructure and launch inputs are not part of this repository.
Actual Uniswap seeding and swaps remain checks for that external harness.
