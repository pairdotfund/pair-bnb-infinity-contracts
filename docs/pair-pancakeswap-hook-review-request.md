# PAIR — immutable BNB Infinity hooks: review request

Updated: **2026-10-15**. BNB Chain mainnet, chain ID **56**. AMM: **PancakeSwap Infinity CL**, not Bin.

## Request

PAIR is an Infinity-only token launchpad. Trading works through PAIR's adapters, but users report no quotes on GMGN and reverted trades on Axiom. We request a **security audit and hook-whitelisting / router-compatibility review**, or an independent-auditor referral, before requesting terminal integrations.

Those terminal reports motivated this work; they are not a newly reproduced terminal simulation against the immutable-hook pools below.

This is a review request, **not an audit report or a claim of PancakeSwap approval**. Hook immutability does not establish safety or standard-router compatibility. We deliberately preserved the existing settlement design rather than redesigning it during this release.

## Current hooks and source

| Hook | Current deployed address | Verified source |
| --- | --- | --- |
| Standard — `BnbInfinityImmutableHook` | `0xD8458aF604EBE341d69a871e98348E77F879c297` | [BscScan](https://bscscan.com/address/0xD8458aF604EBE341d69a871e98348E77F879c297#code) |
| NFT Rewards — `BnbInfinityImmutableNftHook` | `0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd` | [BscScan](https://bscscan.com/address/0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd#code) |

Both are constructor-deployed, **non-proxy immutable hook contracts** with no hook upgrade entrypoint. Both have finalized release bindings. The surrounding platform and dependencies remain upgradeable.

- Public MIT source: https://github.com/pairdotfund/pair-bnb-infinity-contracts
- Reviewed source revision: `5945857388e30a16a3c436cee1733381e8e3800b`.
- [Standard hook source](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/bnb/immutable/BnbInfinityImmutableHook.sol).
- [Inherited standard-hook core](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/PancakeV1InfinityHook.sol).
- [NFT hook source](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/bnb/immutable/BnbInfinityImmutableNftHook.sol).
- Solidity **0.8.26**; full compiler inputs, artifacts and constructor evidence are public. BscScan source readback for both hooks matches the public compiler-input sources.
- [Full deployed graph](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/main/deployments/bnb-mainnet.json), [constructor evidence](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/main/deployments/constructor-evidence.json) and [explorer verification evidence](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/main/deployments/bscscan.json). The root build manifest retains its original pre-deployment provenance; use these deployment records for activated addresses.

## Supporting contracts in audit scope

**H-01 repair:** all four current/historical adapter proxies now use the corrected payer-authorized implementation and have been re-attested. See [remediation and second-review request](pair-pancakeswap-adapter-security-remediation.md). Hook bytecode is unchanged.

| Component | Current address | Current implementation, where upgradeable |
| --- | --- | --- |
| Shared launchpad | `0xb7281262252a054e6B3c886F4c6B2353f9E7F742` | `0xbe9135eC8f41E0d26154d26b921351b4F7C27647` |
| Standard engine | `0xC7839B4513a23F577c6A5Dbe0A87c56635D70e63` | `0x3E1D32f3214E13b4077b9D8b659eD4494ab880F6` |
| Standard swap adapter | `0x538b5a6c0a3F0c28B8B17A2c758daE9A3d669B4C` | `0x64668B2924B06F0c4F53028316eB89Dec7a17091` |
| NFT swap adapter | `0x54699a220C0c7E05b6319E2339dA457A6d1A3d5C` | `0x64668B2924B06F0c4F53028316eB89Dec7a17091` |
| NFT launch module | `0x19B339577b265DA19125b72C6e4C8111d9fd9d71` | `0x04438EFb4979695995E778aA738D5B69dA45a812` |
| Standard factory | `0x98b6315c2c2645A8B43D7fF1224A0D8C89c6e278` | `0xf1246F707026652b9778A22Fb4A2DD9e2535c20A` |
| NFT factory | `0xAc4B750B54649706F8AD75120F0B74e2f5E6779F` | `0xd9Aa0be7f1A663E1d5B149225c8Afb767bEddf2b` |
| Shared protocol fee vault | `0x36A99DB009fEfc5CcE748560D00A6D7e15E9B5f2` | `0xF4cF8AE5D433E4eaaF36f18eC0bC1A915F250D1c` |

Some supporting proxies have BscScan **Similar Match** listings. Those are not a claim of exact PAIR proxy-source verification. Review their actual implementations and the full public constructor/compiler evidence.

The new hooks apply to **future launches only**. Historical hooks `0x78FB0daCbC41bf75F2c87431A0941F0c61442dc2` and `0xfcAff667D7841aD66138e495A21391b9b57E4b03` remain attached to old pools; they are **not** the immutable addresses submitted here.

## Live pool evidence

The successful `imtest` launch at block **127801793** created these standard-hook pools:

| Quote | Pool ID |
| --- | --- |
| CAKE | `0x18084a4bbffc86b21bc9ed64091b58c16b9e0935b3864739041692c74a2b37f4` |
| USDC | `0xf6ad742dd74704aabb8cfc913ba24708f1f40d35a935ede3182ef43882665d3b` |
| U | `0x4d048bd5a4c9df6eb334d41ca1ee832b0f8ec9aab7f8caf742c3b81b7867c809` |

[Launch receipt](https://bscscan.com/tx/0x26023fbe5058399c00995c94f3e61858311e101a703da04f372cf1eb6349dc1e). Pool-registration emitters and CLPoolManager PoolKeys were checked against the immutable standard hook.

**NFT submission is pending a real NFT-mode pool.** No `PoolRegistered` events were found at the immutable NFT hook from deployment block **127768836** through **127803826**. Do not reuse the standard-hook IDs for an NFT-hook submission.

## Behavior, privileges and compatibility

- Registered bitmap **3264 / 0x0cc0**: before/after swap and return-delta permissions. Despite those permissions, both callbacks currently return **zero custom deltas**.
- Current launch pools use static **1% LP fees**, not dynamic LP fees. Separate hook fees include **30 bps protocol fees** and optional project-mode fees.
- Standard modes: no project-mode fee, Creator Fees, Burn, Fee Sharing and Holder Rewards. Standard project-mode rates are 1–10% in 1% increments; burns charge project tokens, other mode fees charge quote tokens.
- **Post-launch standard-hook fee-policy amendments are a protocol-admin control, not a token-creator privilege.** Creators select an initial supported policy at launch; being a creator or fee recipient does not grant permission to amend it later. The protocol-admin wallet owns the hook. The hook also authorizes its finalized registrar, but the current launch engine uses that authority only to initialize policies for newly created tokens and exposes no creator-controlled post-launch policy-editing endpoint.
- Administrative amendments may be used for approved community takeovers (CTO), but the contract does **not** enforce CTO-only use. Amendments may take effect immediately; **there is no enforced timelock**. Holder/non-holder transitions are constrained and fee destinations require the relevant validation.
- Both hooks retain owner controls, including re-attestation of existing adapter implementations. Initial adapter enrollment and registrar/factory bindings are finalized; immutable code does not remove these remaining privileges. Owner: `0x7F269a0e5dC86Cd7101D94F86602E947528D05dB`.
- NFT policy is registered once by its finalized registrar. The NFT fee's applicability depends on the reward collection's `rewardsActive()` state. Include upgradeable collection/vault/adapter dependencies in review.
- Empty `hookData` is accepted. The current callback implementations do not initiate nested swaps or modify liquidity. Callbacks do make external settlement/accounting calls, update graduation/pending-fee state and, for applicable modes, update reward accounting or transfer burn fees.
- **Only pre-attested PAIR adapters are accepted**, with pinned proxy-runtime and implementation hashes. Arbitrary routers and quoters may be rejected. The cooperative flow is `Vault.lock → CLPoolManager.swap → settleUnspecifiedFee`, with gross funding, fee settlement from adapter credit and settlement of outstanding deltas before unlock.
- Making these hooks immutable did **not** remove adapter restrictions or prove GMGN/Axiom compatibility. We are not requesting unconditional whitelisting or representing this as a standard-router-compatible hook.

Infinity Vault: `0x238a358808379702088667322f80aC48bAd5e6c4`. CLPoolManager: `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b`. [Official deployment reference](https://developer.pancakeswap.finance/contracts/infinity/resources/addresses).

Please review settlement, authorization, fee-policy/upgrade trust, quote simulation and integration requirements before advising whether terminals can support the approved PAIR adapters.

See [copy-ready whitelist answers](pair-pancakeswap-hook-whitelist-submission.md).

## Short message to PancakeSwap

Hi PancakeSwap team — PAIR is a BNB Chain Infinity CL launchpad. We have deployed and publicly verified immutable standard and NFT-rewards hooks, with MIT source, reproducible compiler inputs and deployment evidence on GitHub. The standard hook now has three verified live pools. Users can trade through PAIR, but GMGN cannot obtain quotes and Axiom trades have reverted, so we would like a security and hook-listing/compatibility review before approaching those terminals. The hooks still enforce approved adapters and retain disclosed privileged controls and upgradeable dependencies; immutability has not been presented as proof of router compatibility. Could you review the attached contracts, advise on hook-whitelisting requirements, and provide or recommend an independent audit? We will submit the NFT hook separately once it has a real pool.
