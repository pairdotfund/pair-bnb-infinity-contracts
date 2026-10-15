# PAIR BNB Infinity — immutable hooks

**Deployed on BNB Chain mainnet. Not independently audited. Not approved or whitelisted by PancakeSwap.**

## Mainnet deployment

- Standard hook: [`0xD8458aF604EBE341d69a871e98348E77F879c297`](https://bscscan.com/address/0xD8458aF604EBE341d69a871e98348E77F879c297#code)
- NFT rewards hook: [`0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd`](https://bscscan.com/address/0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd#code)
- Retained upgradeable launchpad: [`0xb7281262252a054e6B3c886F4c6B2353f9E7F742`](https://bscscan.com/address/0xb7281262252a054e6B3c886F4c6B2353f9E7F742#code)
- Cutover implementation: [`0xbe9135eC8f41E0d26154d26b921351b4F7C27647`](https://bscscan.com/address/0xbe9135eC8f41E0d26154d26b921351b4F7C27647#code)
- Activation transaction: [`0xa48f32a5325e3280492325609db765fa4beb31c52c5b996b237d4d6539b2a05b`](https://bscscan.com/tx/0xa48f32a5325e3280492325609db765fa4beb31c52c5b996b237d4d6539b2a05b)

The cutover applies to **future launches only**. Existing pools keep their old
hooks, adapters and fee vaults. No mainnet test tokens or trades were created by
this deployment. A new mainnet launch is required before submitting Pool IDs for
these hook addresses; old or fork-only Pool IDs must not be submitted.

`deployments/bnb-mainnet.json` records the address graph and 35 checked receipts.
`deployments/constructor-evidence.json` provides exact deployed creation input,
constructor argument tails and contract identifiers. `deployments/bscscan.json`
records source listing readback. The source templates in this manifest are
unchanged from commit `fe026a75dfc40f107dc36913ac156b497f53c78f`.

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
Constructor arguments and immutable reference values were additionally matched
against the deployment receipts. Runtime templates alone are not proof that a
particular mainnet address is this contract.

`sources/<compiler-input-hash>/` contains the exact Solidity files from each
compiler input, including dependency licenses. Historical builds can contain
different versions of the same source path; they are intentionally not merged.
Some full compiler inputs include retained compatibility
contracts; the candidate entrypoints are named explicitly in `manifest.json`.
This package does not contain the app, private RPC configuration, wallet keys or
environment files.

See RELEASE-PLAN.md for the original release procedure and submission requirements,
and deployments/ for the completed mainnet evidence. Nine functional tests on an
exact production-graph mainnet fork covered all six modes, buys, sells, fee
settlement, legacy-pool trading and NFT rewards. These are engineering tests,
not an independent security audit.
