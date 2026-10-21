# PAIR — H-01 adapter remediation and second-review request

BNB Chain mainnet, chain ID **56**. Upgrade completed at block **128884986**.

## Finding and correction

PancakeSwap reported **H-01: attested adapter lets any caller spend another account's approval**. The previous implementation accepted arbitrary `payer` and `recipient` arguments without authenticating the payer.

Both `executeExactInput` and `executeExactOutput` now reach this check at the start of their shared `_execute` function, before token balance checks, transfers or Infinity Vault calls:

```solidity
if (payer != msg.sender) revert UnauthorizedPayer();
```

`UnauthorizedPayer()` is a new custom error. No storage fields, existing function signatures, fee calculations, settlement logic or hook callbacks were changed.

**Integrator requirement:** the account calling the adapter must be its payer. A contract-funded router/executor must hold the input tokens and pass its own address. A payer may intentionally select a different output recipient. This release does not add signed third-party-payer support, Permit2 witness authorization or `tx.origin` authorization.

## Deployed implementation and unchanged proxies

- Previous implementation: `0x8d5D8Ba002641c44EC4a659b25b3D6D02AD8F165`.
- Corrected shared implementation: **`0x64668B2924B06F0c4F53028316eB89Dec7a17091`**.
- [Verified MIT source on BscScan](https://bscscan.com/address/0x64668B2924B06F0c4F53028316eB89Dec7a17091#code).
- [Implementation deployment](https://bscscan.com/tx/0x0ff58a5c66c7b792fb16f5238284d3ae89171ab0f9b9d753186fc03c40ce4029).
- Actual deployed implementation runtime hash: `0x98c6e47049a34d4cb259359a8ae46236bf7eca300b20797e5f777168078c2b05`.

| Retained adapter proxy | Pool family | Associated hook |
| --- | --- | --- |
| `0x538b5a6c0a3F0c28B8B17A2c758daE9A3d669B4C` | Current standard | `0xD8458aF604EBE341d69a871e98348E77F879c297` — immutable |
| `0x54699a220C0c7E05b6319E2339dA457A6d1A3d5C` | Current NFT | `0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd` — immutable |
| `0x6E1d0f2f669C7D80D123e1e7D06CCB1628AB54a6` | Historical standard | `0x78FB0daCbC41bf75F2c87431A0941F0c61442dc2` — retained historical hook |
| `0x17b7B67a14A4877C5bF13F501a494bA6A8f374F6` | Historical NFT | `0xfcAff667D7841aD66138e495A21391b9b57E4b03` — retained historical hook |

All four proxies were upgraded, rather than leaving older adapters vulnerable. Their corresponding hook owners re-attested the corrected implementation. Hooks correctly rejected the changed adapter implementation until re-attestation.

Adapter addresses, owners, manager/vault/hook bindings, tokens, liquidity, pools and existing ERC-20 allowance records were preserved. Both current immutable hooks retain their original code. Historical hook contracts were not upgraded.

## Reproducible source and evidence

Public repository: https://github.com/pairdotfund/pair-bnb-infinity-contracts

The repository's `deployments/adapter-payer-auth.json` records the implementation, all nine successful transaction receipts and attestation changes. This release's exact source is isolated under:

- `sources/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd/contracts/pancake-v1/bnb/upgradeable/BnbInfinitySwapAdapterUpgradeable.sol`
- `compiler-inputs/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd.json`
- `artifacts/BnbInfinitySwapAdapterPayerAuth.json`
- `deployments/adapter-payer-auth-verification.json`
- `deployments/adapter-payer-auth-rehearsal.json`
- `deployments/adapter-payer-auth-postflight.json`

Compiler: **Solidity 0.8.26+commit.8a97fa7a**, using the published standard-JSON settings. BscScan source readback matches every source in that input and contains the new authorization error. Historical build inputs and source namespaces remain available separately; do not confuse the old vulnerable artifact with the corrected implementation.

## Validation performed

Pinned mainnet-fork regression: **13 tests passed**, containing 18 recorded checks:

- Reproduced unauthorized spending with both selectors on the old standard and NFT adapters.
- Rejected both unauthorized-payer selectors on all four upgraded proxies; victim balances and allowances remained unchanged.
- Verified owner-only re-attestation, hook fail-closed behavior before re-attestation, and unchanged owner/manager/vault/hook bindings.
- Exercised legitimate buys and sells across all six current fee modes, including activated NFT rewards and zero outstanding Vault deltas.
- Preserved intentional third-party recipients when the caller funds the trade.
- Preserved contract-funded native developer buys in standard and NFT modes.
- Preserved native buys and sells on a historical pool through its retained adapter.

Storage layouts were compared recursively against compiler evidence authenticated to the old deployed runtime. Existing ABI entries were preserved. Mainnet postflight also confirmed the four implementation slots, unchanged hook code hashes and **eight read-only calls reverting with `UnauthorizedPayer()`**.

Gas spent for deployment, four upgrades and four attestations: **0.00010651525 BNB**. No mainnet test pools or test trades were created by this repair.

## Remaining review scope and message to PancakeSwap

This is our remediation evidence, not an independent audit sign-off. It does not establish absence of historical exploitation, prove that all other findings are resolved, remove privileged controls, or provide arbitrary-terminal/router compatibility. The application trust configuration has been updated for the corrected implementation while preserving pre-upgrade receipt-block verification; a separately published application must use the updated build.

> Hi PancakeSwap team — we have remediated H-01 by requiring `payer == msg.sender` in the shared adapter execution path before any token transfer. We deployed the corrected implementation at `0x64668B2924B06F0c4F53028316eB89Dec7a17091`, upgraded all four current/historical adapter proxies, and re-attested them with their existing hooks. No hooks, pools or tokens were redeployed, and current immutable-hook code is unchanged. The exact MIT source, compiler input, receipts and regression evidence are public in our repository. Our pinned mainnet-fork suite passed, and live read-only checks confirm both selectors reject unauthorized payers on all four proxies. Please re-audit the payer authorization, legitimate executor compatibility and upgrade/attestation evidence, and continue reviewing the remaining hook and dependency behavior. We are not representing this repair as a completed audit or terminal-compatibility approval.
