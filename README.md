# PAIR BNB Infinity — immutable hooks

**Deployed on BNB Chain mainnet. Not independently audited. Not approved or whitelisted by PancakeSwap.**

## Mainnet deployment

- Standard hook: [`0xD8458aF604EBE341d69a871e98348E77F879c297`](https://bscscan.com/address/0xD8458aF604EBE341d69a871e98348E77F879c297#code)
- NFT rewards hook: [`0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd`](https://bscscan.com/address/0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd#code)
- Retained upgradeable launchpad: [`0xb7281262252a054e6B3c886F4c6B2353f9E7F742`](https://bscscan.com/address/0xb7281262252a054e6B3c886F4c6B2353f9E7F742#code)
- Cutover implementation: [`0xbe9135eC8f41E0d26154d26b921351b4F7C27647`](https://bscscan.com/address/0xbe9135eC8f41E0d26154d26b921351b4F7C27647#code)
- Activation transaction: [`0xa48f32a5325e3280492325609db765fa4beb31c52c5b996b237d4d6539b2a05b`](https://bscscan.com/tx/0xa48f32a5325e3280492325609db765fa4beb31c52c5b996b237d4d6539b2a05b)

The cutover applies to **future launches only**. Existing pools keep their old
hooks, adapters and fee vaults. The deployment itself created no test tokens or
trades. A subsequent user launch has now supplied three verified standard-hook
Pool IDs, listed below. The NFT hook still needs its first real pool; old or
fork-only Pool IDs must not be submitted.

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

## PancakeSwap review and live standard-hook pools

- [Updated audit / compatibility review request](docs/pair-pancakeswap-hook-review-request.md)
- [Copy-ready hook-whitelist form answers](docs/pair-pancakeswap-hook-whitelist-submission.md)

Successful standard-hook launch: [imtest](https://bscscan.com/tx/0x26023fbe5058399c00995c94f3e61858311e101a703da04f372cf1eb6349dc1e), block 127801793.
The CLPoolManager PoolKeys identify the immutable standard hook and static 1% LP fees:

| Quote | Pool ID |
| --- | --- |
| CAKE | `0x18084a4bbffc86b21bc9ed64091b58c16b9e0935b3864739041692c74a2b37f4` |
| USDC | `0xf6ad742dd74704aabb8cfc913ba24708f1f40d35a935ede3182ef43882665d3b` |
| U | `0x4d048bd5a4c9df6eb334d41ca1ee832b0f8ec9aab7f8caf742c3b81b7867c809` |

No registration events were found for the immutable NFT hook from deployment block
127768836 through 127803826. Do not reuse standard-hook IDs for the NFT submission.

The root `manifest.json` is the original **source-build snapshot** and retains its
pre-deployment status for provenance. Activated identities and receipts are in
`deployments/bnb-mainnet.json`; the review documents above describe the current
release. Source/artifact/compiler-input files are unchanged by this documentation update.

## Preserved behavior and limitations

- BNB Chain (56), PancakeSwap Infinity concentrated-liquidity pools.
- Existing fee callback/settlement bodies are preserved, not redesigned.
- Static 1% LP fees, plus the existing separately settled protocol/mode fees.
- Only pre-attested PAIR adapters are accepted. Their proxy runtime and current
  implementation code hashes must match. This is **not** standard-router or
  terminal compatibility.
- Post-launch fee-policy changes are a protocol-admin control, not a token-creator
  privilege. The registrar initializes new-launch policies; the current engine
  exposes no creator-controlled post-launch policy-editing endpoint. Administrative
  amendments may support approved CTOs, but the contract does not enforce CTO-only
  use or a timelock. Adapter implementation re-attestation remains an owner control.
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
