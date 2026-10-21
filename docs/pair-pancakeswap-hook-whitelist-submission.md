# PancakeSwap hook review resubmission — PAIR Infinity Launch Hook

Updated 2026-10-21. **Copy-ready answers for sections 2–4; not submitted automatically.**

**Scope:** one submission for the standard immutable hook, `0xD8458aF604EBE341d69a871e98348E77F879c297`. Do not combine the NFT hook or its behavior with this form.

The hook bytecode is unchanged. This resubmission discloses the deployed H-01 repair to its upgradeable adapter dependency. On-chain checks at block **128915394** confirmed the hook owner, finalized registrar/adapters, registration bitmap, corrected adapter implementation attestation, and all three Pool IDs listed below.

## 2. Hook overview

**AMM type:** PancakeSwap Infinity CL.

**Chain(s):** BNB Chain only (mainnet, chain ID 56). Do not select Base.

**Hook name:** PAIR Infinity Launch Hook (Immutable).

**What the hook does:**

PAIR's non-proxy, immutable hook supports token-launch pools on PancakeSwap Infinity CL. It implements optional Creator Fees, project-token burns, Fee Sharing and Holder Rewards, plus permanent on-chain graduation tracking. Fees consist of a fixed 30 bps protocol fee and optional project-mode fees, separate from the pool's static LP fee.

Swap callbacks return zero custom swap deltas. Fees are settled through pre-enrolled PAIR adapters authenticated by both proxy-runtime and implementation hashes. The current hook does not initiate nested swaps or change liquidity. Post-launch project-fee policy changes are controlled by the protocol admin, not token creators merely by virtue of being creators.

The hook itself is immutable, but supporting adapters and other platform dependencies include upgradeable contracts. The deployed adapter repair requires the caller to be the payer before spending tokens. Hook whitelisting alone does not authorize arbitrary third-party routers or establish GMGN/Axiom compatibility.

**Hook address:**

`0xD8458aF604EBE341d69a871e98348E77F879c297`

**Existing Pool ID(s), comma separated:**

```text
0x18084a4bbffc86b21bc9ed64091b58c16b9e0935b3864739041692c74a2b37f4, 0xf6ad742dd74704aabb8cfc913ba24708f1f40d35a935ede3182ef43882665d3b, 0x4d048bd5a4c9df6eb334d41ca1ee832b0f8ec9aab7f8caf742c3b81b7867c809
```

CAKE, USDC and U pools for project `0x3dedba3ee25c50cefb3464e24edfa92831ae5555`, respectively. These are live mainnet pools, not rehearsal/fork IDs.

**Is the hook verified on a block explorer?** Yes.

**Explorer link to verified hook source:**

https://bscscan.com/address/0xD8458aF604EBE341d69a871e98348E77F879c297#code

**Link to source:**

https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/bnb/immutable/BnbInfinityImmutableHook.sol

The inherited `PancakeV1InfinityHook.sol`, dependencies, compiler input and constructor evidence are included in the same public repository. BscScan source readback matches the public compiler-input sources. This pinned hook-source revision remains correct because the hook was not redeployed or modified by the adapter repair.

### Material dependency change since the previous review — H-01

The reported arbitrary-payer allowance-spending finding was corrected in `BnbInfinitySwapAdapterUpgradeable`. Both `executeExactInput` and `executeExactOutput` now reach `if (payer != msg.sender) revert UnauthorizedPayer();` at the start of their shared execution path, before token transfers.

- **Corrected implementation:** `0x64668B2924B06F0c4F53028316eB89Dec7a17091`.
- **Adapter proxy used by this standard hook:** `0x538b5a6c0a3F0c28B8B17A2c758daE9A3d669B4C`.
- [Verified adapter implementation source on BscScan](https://bscscan.com/address/0x64668B2924B06F0c4F53028316eB89Dec7a17091#code).
- [Corrected adapter source on GitHub — pinned release](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/sources/f3fb54b003b3d06a3b07bc18a5faf0357b5818c46c4d37c3a373ba4d392d07fd/contracts/pancake-v1/bnb/upgradeable/BnbInfinitySwapAdapterUpgradeable.sol).
- [Deployment, four proxy upgrades and four hook re-attestations](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/deployments/adapter-payer-auth.json).
- [Fork regression evidence](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/deployments/adapter-payer-auth-rehearsal.json) and [live read-only rejection checks](https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/4808672a27d341082c2048271e7e3aa300930afe/deployments/adapter-payer-auth-postflight.json).

All four current/historical adapter proxies were repaired and re-attested, not only the standard adapter above. The hook's approved implementation hash is now `0x98c6e47049a34d4cb259359a8ae46236bf7eca300b20797e5f777168078c2b05`. No hook, pool or token was redeployed. The repair did not change hook callback behavior, storage layouts, existing function signatures, fee formulas or settlement design.

Contract-funded executors must hold the input tokens and pass themselves as payer; an authorized payer may still select a different output recipient. This is not a signed third-party-payer authorization feature.

## 3. Behavior declarations

| Question | Selection |
| --- | --- |
| 3.1 Return custom deltas | **No — all custom swap delta values are zero; see permission-bit disclosure below** |
| 3.2 Dynamic LP fees | **No** |
| 3.3 Additional hook fees | **Yes** |
| 3.4 Admin can change LP fees or hook fees | **Yes — project-mode hook policies, not the static LP fee** |
| 3.5 Nonempty hookData required | **No** |
| 3.6 Callback-triggered nested swaps | **No in the current reviewed implementation; external dependencies disclosed below** |
| 3.7 Callback liquidity changes | **No** |
| 3.8 Other state changes affecting swaps or quotes | **Yes** |

Paste the explanations below with the corresponding answers; do not omit the adapter restrictions or privileged controls.

### 3.1 Does the hook return deltas from callbacks?

**No — no nonzero custom swap deltas.** `beforeSwap` returns `BeforeSwapDelta(0,0)` and `afterSwap` returns zero. For completeness, both return-delta permission bits are enabled in the registered bitmap **3264 / 0x0cc0**, despite the actual returned delta values being zero. Fees are settled separately through the authenticated adapter, not charged through returned custom deltas. This answer describes the returned values, not an absence of return-delta permission bits.

### 3.2 Does the hook use dynamic LP fees?

**No.** Current PAIR launch pools use a static 1% LP fee. The hook returns a zero LP-fee override and does not update dynamic LP fees. Additional protocol/project-mode fees are hook fees, not dynamic LP fees.

### 3.3 Does the hook charge additional hook fees?

**Yes.** A fixed 30 bps protocol fee in quote tokens, plus optional project-mode fees of 1–10% in 1% increments. No-project-fee mode has no additional project-mode fee. Burn-mode fees use project tokens; other project-mode fees use quote tokens. These fees are separate from LP fees and require PAIR's cooperative adapter settlement.

### 3.4 Can an admin change LP fees or hook fees?

**Yes — project-mode hook fee-policy changes are an admin-only product control, not a token-creator privilege.** Creators select an initial supported mode/rate when launching. Being a token creator or fee recipient does not authorize post-launch amendments. The protocol-admin hook owner can append policy epochs changing supported project-mode rates, permitted modes and validated destinations, subject to contract restrictions, including holder-mode transition restrictions and vault attestation.

At contract level, the finalized registrar is also authorized. In the current release, that registrar is the launch engine: it initializes policies for newly created tokens and exposes no creator-controlled post-launch policy-editing endpoint.

This administrative authority may be used for approved community takeovers (CTO), but the contract does not enforce CTO-only use. Activation may be immediate; there is no enforced timelock. The hook does not change the PoolKey's static LP fee, and the 30 bps protocol-fee constant is not an admin-settable hook parameter.

### 3.5 Does the hook require nonempty hookData?

**No.** Swap callbacks accept empty `hookData` and do not decode it. Separately, the sender must be an approved adapter and satisfy runtime/implementation attestations; empty hookData does not make arbitrary routers authorized.

### 3.6 Can a callback trigger nested swaps?

**No in the current released implementation.** Callbacks do not initiate nested swaps. They do make external calls to approved adapters for fee settlement and to fee/reward vaults for accounting. Those external dependencies and their upgradeability must be included in review; this is not a claim about every possible future dependency implementation.

### 3.7 Can a callback add, remove or reposition liquidity?

**No.** Liquidity initialization occurs outside these callbacks through launch/bootstrap contracts. The graduation check records a permanent status; it does not migrate, remove or reposition LP liquidity.

### 3.8 Does a callback make other state changes that affect the current swap or later quotes?

**Yes.** `afterSwap` can permanently record graduation, invoke protocol/project fee settlement and vault accounting, and write pending output-fee settlement state. Burn-mode settlement transfers applicable project-token fees to the burn address. The adapter subsequently calls `settleUnspecifiedFee()` to consume pending output fees after the callback returns. These operations change balances, accounting and net user amounts. The active admin/registrar-set policy also affects quotes and execution even though the returned custom swap deltas are zero.

## 4. Upgradeability and privileged control

### Is the hook upgradeable?

**No.** `BnbInfinityImmutableHook` is constructor-deployed and non-proxy, with no hook-code upgrade entrypoint or UUPS/delegatecall upgrade path. The H-01 repair upgraded an external adapter implementation, not this hook. Immutability applies to hook code, not to the entire surrounding platform or its mutable policy state.

### Does the hook have any privileged controls?

**Yes.**

Owner: `0x7F269a0e5dC86Cd7101D94F86602E947528D05dB`.

The protocol-admin hook owner retains the post-launch fee-policy controls described above; token-creator or fee-recipient status alone grants no such authority. The finalized registrar is also authorized at hook level, with its current launch-engine implementation using that authority for initial policy registration, not creator-controlled amendments to existing tokens. The owner can re-attest the implementation of already-enrolled adapters and transfer/renounce ownership. Initial adapter enrollment and registrar/factory bindings are finalized. Launchpad, engines, adapters and vault/collection dependencies include upgradeable contracts under their respective authorities; adapter implementation changes fail hook authorization until re-attested. The standard fee-policy controls have no enforced timelock and are not contractually limited to CTO cases. These privileges do not permit upgrading the immutable hook's code.

## Review evidence and acceptance status

The published fork regression contains 13 passing tests / 18 recorded checks, including exploit reproduction before the repair, rejection afterward, fee modes, native developer buys and retained-pool trading. The published mainnet postflight contains eight read-only unauthorized-payer rejection checks across four adapters.

No completed independent audit report or closure of every finding is being claimed. Public source verification is not a security audit. This submission requests review of the H-01 repair and current hook/dependency behavior, as well as hook-listing guidance. It does not claim PancakeSwap acceptance or GMGN/Axiom compatibility.

## Separate NFT-hook scope

The immutable NFT hook at `0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd` needs its own form, authenticated NFT-hook Pool IDs and NFT-specific fee-control explanations. Do not reuse the standard-hook Pool IDs or its post-launch fee-policy answer. This document does not assert that there are currently no NFT pools; earlier historical scans are not a current absence-of-pools proof.
