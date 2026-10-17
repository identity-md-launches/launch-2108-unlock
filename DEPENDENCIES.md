# Vendored dependencies

All required Solidity dependencies are ordinary source files under `lib/`; no package install, submodule, network connection, or external checkout is needed to build or test.

- [OpenZeppelin/openzeppelin-contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2): 6 files, unmodified. Release archive SHA-256: `18c7b7e949b9a82dcd8cd394426c9c2636dfc263aa2317d4749dbfa0c7b3925a`.
- [foundry-rs/forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7): 30 files, unmodified. Release archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`.

OpenZeppelin contains only ERC20 and its transitive dependencies, under MIT (`lib/openzeppelin-contracts/LICENSE`). forge-std includes its Solidity source tree for tests, under MIT/Apache-2.0 (`lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE`).

`lib/SHA256SUMS` records each vendored file. Check with `sha256sum -c lib/SHA256SUMS` from the repository root.
