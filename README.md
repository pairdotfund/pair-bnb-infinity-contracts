<!-- PAIR-STANDARD-ROUTING -->
# PAIR BNB Infinity contracts

## Current active release: standard Infinity routing

New launches use immutable hooks compatible with PancakeSwap's official CLQuoter and Universal Router.
The old adapter-restricted pools retain their original contracts and source evidence.

- [Current release: contracts, behavior and reproduction](releases/standard-routing/README.md)
- [Deployment manifest and exact constructor/compiler bindings](releases/standard-routing/manifest.json)
- [BscScan source-readback results](releases/standard-routing/reports/bscscan-verification.json)
- [Sourcify: exact creation and runtime matches for all 34 deployed targets](releases/standard-routing/reports/sourcify-verification.json)
- [Reproducible build: all 21 packaged contracts](releases/standard-routing/reports/build-reproducibility.json)

| Hook | BNB mainnet explorer |
| --- | --- |
| Standard modes | [0x01d6f615032DC9fcF8531e0F9007C0C954b31b64](https://bscscan.com/address/0x01d6f615032DC9fcF8531e0F9007C0C954b31b64#code) |
| NFT rewards | [0x902d4Af4615Ce00399a0Cda971482EB901F5dF3d](https://bscscan.com/address/0x902d4Af4615Ce00399a0Cda971482EB901F5dF3d#code) |

Both hooks are immutable; privileged owner policy controls and upgradeable platform dependencies remain.
Permissionless fee settlement cannot redirect accrued rewards. Native funding helpers are optional, not required swap senders.
All 34 deployed targets have exact creation/runtime matches on Sourcify.
BscScan verification is a separate process: consult its report for pending jobs and similar matches; do not assume source readback is complete.
Source verification is **not** an independent audit or whitelist/terminal-integration approval.

## Retained releases

The following source and remediation history describes retained, earlier pools, not the current standard-routing hooks:

# PAIR BNB Infinity — immutable hooks

**Deployed on BNB Chain mainnet. Not independently audited. Not approved or whitelisted by PancakeSwap.**

## H-01 security repair — current adapter implementation

All four current/historical adapter proxies now use corrected implementation
[`0x64668B2924B06F0c4F53028316eB89Dec7a17091`](https://bscscan.com/address/0x64668B2924B06F0c4F53028316eB89Dec7a17091#code).
Both swap entrypoints require the caller to be the payer before spending tokens.
The four associated hooks have re-attested the new implementation. No hook or pool was redeployed.

- [Quick contract inventory and direct source links for re-audit](docs/pair-pancakeswap-reaudit-contracts.md)
- [Remediation summary and second-audit request](docs/pair-pancakeswap-adapter-security-remediation.md)
- [Current upgrade/attestation receipts](deployments/adapter-payer-auth.json)
- [BscScan exact-source verification](deployments/adapter-payer-auth-verification.json)
- [Fork regression evidence](deployments/adapter-payer-auth-rehearsal.json) and [live read-only postflight](deployments/adapter-payer-auth-postflight.json)
- Corrected artifact: `artifacts/BnbInfinitySwapAdapterPayerAuth.json`; full compiler output: `compiler-outputs/BnbInfinitySwapAdapterPayerAuth.json`.
- Exact compiler input and complete source namespace: `compiler-inputs/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd.json` and `sources/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd/`.

**Historical provenance:** `deployments/bnb-mainnet.json` and the original adapter artifact
record the earlier deployment; use `deployments/adapter-payer-auth.json` for the later
adapter upgrades. Do not deploy the old adapter artifact as the repaired implementation.
The immutable hook source files themselves are unchanged. No independent audit sign-off
or terminal-compatibility approval is claimed by this repair.

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
