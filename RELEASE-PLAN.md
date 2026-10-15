# PAIR BNB immutable-hook release plan

## Scope

Deploy constructor-based standard and NFT hooks for **future launches only**.
Preserve the current fee settlement, fee policies and guarded PAIR adapters.
Do not implement standard Infinity router settlement, remove the adapter guard,
change old pool identities, or move existing project fee balances.

This is an undeployed candidate, not an audit, mainnet release or PancakeSwap approval.
No new mainnet spending is authorized by this document.

## Contract changes

| Component | Treatment |
| --- | --- |
| Standard hook | New non-proxy `BnbInfinityImmutableHook`; unchanged core callbacks and proxy/implementation adapter checks |
| NFT hook | New non-proxy `BnbInfinityImmutableNftHook`; constructor initialization, unchanged fee and rewards callbacks |
| Existing launchpad proxy | Retain address, owner, fees, pool records and storage; install a reviewed one-shot graph-cutover implementation |
| Engines, factories, bootstrapper and creation helpers | Parallel hook-bound release, not mutation of old helper bindings |
| Native/direct quote coordinators and adapters | New hook-bound instances; preserve deployed routing fixes and implementation identity checks |
| Protocol fee vault | Retain current proxy and existing primary hook; authorize new hooks additionally |
| Existing NFT collections and project fee vaults | Preserve their old hook/admin bindings and claims |
| Existing pools and historical releases | Continue to resolve their original graph; never infer their adapter from only the latest release |

The hooks themselves lose upgradeability. Platform contracts and dependencies do
not. Hook ownership, policy controls and adapter implementation re-attestation must
still be disclosed. Hook immutability does not imply immutable fee recipients,
dependencies or all policy parameters.

## Validation before a mainnet spending request

1. Compile with the pinned optimizer, compiler and EVM settings.
2. Check unchanged callback/settlement bodies against the deployed-source baseline.
3. Test all six modes, buys/sells, protocol accounting, adapter hash guards and
   NFT rewards activation/claims. Test fee-bearing paths, not only pre-mint NFT trades.
4. Confirm direct deployment, absence of upgrade/initializer selectors, zero ERC1967
   implementation slot, and exact runtime matching using compiler-declared
   immutable reference ranges. Reject unverified proxy/delegatecall paths.
5. Compare the live deployed-old launchpad build/storage against the candidate;
   preserve existing pool records, owner, fees, treasury and social verifier.
6. Prepare an exact nonce-bound deployment/configuration sequence, simulate it on
   an anchored mainnet fork and calculate a conservative maximum BNB spend.
7. Rehearse the actual current production native-routing implementation and quote
   catalog, including direct-quote and BNB-funded developer buys, not just a newly
   constructed local fixture. Preserve current rounding/refund and slippage floors.
8. Verify an old standard pool and an old NFT pool still trade and claim after the
   proposed future-only cutover. Keep all old vault/hook bindings unchanged.

The fixture regression report is preliminary evidence. It does not replace the
exact production-address, nonce-bound rehearsal, live baseline attestation or
gas-budget approval.

## Deployment and activation order

1. Obtain a fresh, explicit mainnet spending limit.
2. Deploy both hooks directly, then deploy/configure the parallel helper graph.
3. Authorize the new hooks in the existing protocol vault without replacing its
   primary hook. Attest only the new hook-bound adapters, including implementation
   hashes. Freeze both new graphs and verify all reciprocal bindings.
4. Verify exact source on BscScan, publish matching source on GitHub and record
   deployment receipts, compiler inputs, constructor arguments and live code hashes.
5. Publish dual-release frontend/backend support **before activation** so existing
   pools retain their old trading paths, and new receipt registration, quoting,
   claims and vanity mining recognize the new graph.
6. Pause launches; atomically upgrade the existing launchpad implementation and
   activate its constructor-pinned new graph using `upgradeToAndCall`.
   The candidate deliberately remains paused afterward.
7. Check the complete old/new graph and app consumers, then explicitly unpause.
   Never remove the old protocol-vault authorizations or adapter attestations.
8. Obtain real new pool IDs from separately approved future launches. Old pool IDs
   belong to old hooks and cannot be submitted for the new addresses.

## PancakeSwap submission

Prepare a separate accurate submission for each new hook address if both standard
and NFT hooks require listing. Identify Infinity CL on BNB Chain; attach exact
verified BscScan source and public GitHub links, real matching pool IDs and any
actual independent audit reports. Do not describe local tests as an audit.

Declare the custom fees, state-changing callbacks, liquidity/graduation behavior,
adapter restrictions, privileged controls and upgradeable dependencies. The
callbacks' zero returned deltas do **not** mean there are no additional fees: the
current custom adapter settles them separately. Do not imply compatibility with
unmodified GMGN, Axiom or the universal router.

Only the person authorized to make the change-notice commitment should confirm
their name, date and agreement on the final form. PancakeSwap decides acceptance;
making the hook immutable is not a guarantee.
