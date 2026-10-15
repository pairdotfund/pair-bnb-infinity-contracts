# PAIR BNB Infinity — immutable-hook candidate

**Not deployed. Not audited. Not approved or whitelisted by PancakeSwap.**

This contracts-only package contains constructor-deployed standard and NFT hooks,
their dependencies, a future-launch-only launchpad cutover implementation, exact
Solidity standard-JSON compiler inputs, ABIs, storage layouts and bytecode templates.
The two new hooks have no proxy, initializer, delegatecall upgrade path or UUPS
entrypoint. The other platform contracts remain upgradeable.

## Preserved behavior and limitations

- BNB Chain (56), PancakeSwap Infinity concentrated-liquidity pools.
- Existing fee callback/settlement bodies are preserved, not redesigned.
- Static 1% LP fees, plus the existing separately settled protocol/mode fees.
- Only pre-attested PAIR adapters are accepted. Their proxy runtime and current
  implementation code hashes must match. This is **not** standard-router or
  terminal compatibility.
- Owner policy controls and adapter implementation re-attestation remain.
- Engines, adapters, vaults and NFT collections include upgradeable dependencies.
- Old pools retain their original hooks, adapters and vaults.
- Immutability alone does not guarantee PancakeSwap acceptance.

## Reproduce the build

Install Node.js and run `npm install --ignore-scripts`, then `npm run compile`.
The sole build dependency is pinned to solc 0.8.26. Compilation preserves every
source and bytecode-affecting setting in the original standard-JSON inputs and
requests outputs only for the listed contracts, avoiding compilation of unused
compatibility entrypoints. Original input files remain intact. The script checks
every published creation/runtime bytecode template.
Constructor arguments and immutable reference values must additionally be matched
against the eventual deployment receipts. Runtime templates alone are not proof
that a particular mainnet address is this contract.

`sources/<compiler-input-hash>/` contains the exact Solidity files from each
compiler input, including dependency licenses. Historical builds can contain
different versions of the same source path; they are intentionally not merged.
Some full compiler inputs include retained compatibility
contracts; the candidate entrypoints are named explicitly in `manifest.json`.
This package does not contain the app, private RPC configuration, wallet keys or
environment files.

See RELEASE-PLAN.md for activation checks, verification, Pool IDs and submission
requirements. Mainnet addresses, constructor arguments, receipt evidence and BscScan
links must be added after a separately approved deployment.
