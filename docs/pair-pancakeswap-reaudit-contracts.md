# PAIR BNB Infinity — contracts for PancakeSwap re-audit

**Chain:** BNB Chain mainnet (56). **Status:** H-01 adapter repair deployed; independent re-audit requested, not completed.

## New contract in this repair

**`BnbInfinitySwapAdapterUpgradeable` implementation:**  
`0x64668B2924B06F0c4F53028316eB89Dec7a17091`

- [Verified MIT source — BscScan](https://bscscan.com/address/0x64668B2924B06F0c4F53028316eB89Dec7a17091#code)
- [Exact corrected Solidity source — GitHub, pinned release](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/sources/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd/contracts/pancake-v1/bnb/upgradeable/BnbInfinitySwapAdapterUpgradeable.sol)
- [Complete compiler input](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/compiler-inputs/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd.json)
- [Implementation artifact](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/artifacts/BnbInfinitySwapAdapterPayerAuth.json)

**Change:** both swap entrypoints now require `payer == msg.sender` in their shared execution path, before token transfers. This prevents another caller from using a victim's adapter allowance. Existing storage, function signatures, fees and settlement logic are unchanged; `UnauthorizedPayer()` is the added custom error. Contract-funded executors pass themselves as payer; recipients may differ.

**No other new contracts were deployed for this repair.** The four existing adapter proxies below were upgraded to the one shared implementation, then re-attested with their associated hooks.

| Existing adapter proxy | Pool family |
| --- | --- |
| [`0x538b5a6c0a3F0c28B8B17A2c758daE9A3d669B4C`](https://bscscan.com/address/0x538b5a6c0a3F0c28B8B17A2c758daE9A3d669B4C#code) | Current standard |
| [`0x54699a220C0c7E05b6319E2339dA457A6d1A3d5C`](https://bscscan.com/address/0x54699a220C0c7E05b6319E2339dA457A6d1A3d5C#code) | Current NFT |
| [`0x6E1d0f2f669C7D80D123e1e7D06CCB1628AB54a6`](https://bscscan.com/address/0x6E1d0f2f669C7D80D123e1e7D06CCB1628AB54a6#code) | Historical standard |
| [`0x17b7B67a14A4877C5bF13F501a494bA6A8f374F6`](https://bscscan.com/address/0x17b7B67a14A4877C5bF13F501a494bA6A8f374F6#code) | Historical NFT |

## Current immutable hooks — unchanged, still in audit scope

| Hook | Address / explorer | Open-source Solidity |
| --- | --- | --- |
| Standard — `BnbInfinityImmutableHook` | [`0xD8458aF604EBE341d69a871e98348E77F879c297`](https://bscscan.com/address/0xD8458aF604EBE341d69a871e98348E77F879c297#code) | [GitHub source](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/bnb/immutable/BnbInfinityImmutableHook.sol) |
| NFT rewards — `BnbInfinityImmutableNftHook` | [`0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd`](https://bscscan.com/address/0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd#code) | [GitHub source](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/bnb/immutable/BnbInfinityImmutableNftHook.sol) |

## Evidence and review request

- [Nine deployment/upgrade/attestation transactions](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/deployments/adapter-payer-auth.json).
- [13 passing fork tests / 18 recorded checks](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/deployments/adapter-payer-auth-rehearsal.json): exploit reproduction, payer rejection, current fee modes, native developer buys and historical-pool trading.
- [Mainnet read-only postflight](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/deployments/adapter-payer-auth-postflight.json): both unauthorized-payer selectors rejected on all four proxies.
- [Full supporting-contract inventory](pair-pancakeswap-hook-review-request.md) and [detailed remediation report](pair-pancakeswap-adapter-security-remediation.md).

> Hi PancakeSwap team — H-01 is repaired on BNB mainnet. We deployed one corrected adapter implementation, upgraded all four current/historical adapter proxies, and re-attested them with their hooks. The fix enforces `payer == msg.sender` before spending tokens; immutable-hook code, pools and settlement logic are unchanged. Please review the linked source, upgrade evidence and regression results, then re-audit payer authorization and executor compatibility alongside the remaining hook/dependency findings. We are not claiming audit completion, whitelisting or terminal compatibility.
