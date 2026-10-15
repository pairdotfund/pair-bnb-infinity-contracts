# PancakeSwap hook submission — PAIR immutable standard hook

Prepared 2026-10-15. **Ready to copy into the form; not submitted automatically.**
This submission is for the standard hook only. See the NFT addendum before preparing a separate NFT-hook submission.

## 2. Hook overview

**AMM type:** PancakeSwap Infinity CL.

**Chain(s):** BNB Chain only (mainnet, chain ID 56). Do not select Base.

**Hook name:** PAIR Infinity Launch Hook (Immutable).

**What the hook does:**

PAIR's constructor-deployed, non-proxy hook supports Infinity CL token-launch pools with optional Creator Fees, project-token burns, Fee Sharing and Holder Rewards, plus on-chain graduation tracking. It collects a fixed 30 bps protocol fee and optional project-mode fees separately from the static LP fee. Swap callbacks return zero custom deltas; settlement requires pre-attested PAIR adapters with pinned runtime and implementation hashes. The hook does not modify liquidity or initiate nested swaps in the current release. It retains privileged fee-policy and adapter-implementation approval controls and has upgradeable external dependencies; arbitrary third-party routers/quoters are not currently supported merely by whitelisting the hook.

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

The inherited `PancakeV1InfinityHook.sol`, dependencies, compiler input and constructor evidence are included in the same public repository. BscScan source readback matches the public compiler-input sources.

## 3. Behavior declarations

### 3.1 Does the hook return deltas from callbacks?

**No — no nonzero custom deltas.** `beforeSwap` returns `BeforeSwapDelta(0,0)` and `afterSwap` returns zero. Return-delta permission bits are registered in bitmap 3264/0x0cc0, but the callback return values are zero. Hook fees are settled separately through the authenticated adapter, not returned as hook deltas.

### 3.2 Does the hook use dynamic LP fees?

**No.** Current PAIR launch pools use a static 1% LP fee. The hook returns a zero LP-fee override and does not update dynamic LP fees. Additional protocol/project-mode fees are hook fees, not dynamic LP fees.

### 3.3 Does the hook charge additional hook fees?

**Yes.** A fixed 30 bps protocol fee in quote tokens, plus optional project-mode fees of 1–10% in 1% increments. No-project-fee mode has no additional project-mode fee. Burn-mode fees use project tokens; other project-mode fees use quote tokens. These fees are separate from LP fees and require PAIR's cooperative adapter settlement.

### 3.4 Can an admin change LP fees or hook fees?

**Yes — project-mode hook fee policies.** The hook owner or finalized registrar can append new policies affecting project-mode fee rates, permitted modes and validated destinations, subject to the encoded restrictions. Activation may be immediate; there is no enforced timelock. The hook does not change the PoolKey's static LP fee, and the 30 bps protocol-fee constant is not an admin-settable hook parameter.

### 3.5 Does the hook require nonempty hookData?

**No.** Swap callbacks accept empty `hookData` and do not decode it. Separately, the sender must be an approved adapter and satisfy runtime/implementation attestations; empty hookData does not make arbitrary routers authorized.

### 3.6 Can a callback trigger nested swaps?

**No in the current released implementation.** Callbacks do not initiate nested swaps. They do make external calls to approved adapters for fee settlement and to fee/reward vaults for accounting. Those external dependencies and their upgradeability must be included in review; this is not a claim about every possible future dependency implementation.

### 3.7 Can a callback add, remove or reposition liquidity?

**No.** Liquidity initialization occurs outside these callbacks through launch/bootstrap contracts. The graduation check records a permanent status; it does not migrate, remove or reposition LP liquidity.

### 3.8 Does a callback make other state changes that affect the current swap or later quotes?

**Yes.** `afterSwap` can record graduation, collect protocol/project fees, write pending fee-settlement state and invoke fee/reward-vault accounting. Burn mode transfers applicable project-token fees to the burn address. Separate settlement clears pending fees. Policy state and these fees affect execution eligibility and net user amounts even though custom callback deltas are zero.

## 4. Upgradeability and privileged control

**Is the hook upgradeable? No.** It is constructor-deployed and non-proxy, with no hook-code upgrade entrypoint or UUPS/delegatecall upgrade path. Immutability applies to this hook, not the entire surrounding platform.

**Does the hook have privileged controls? Yes.**

Owner: `0x7F269a0e5dC86Cd7101D94F86602E947528D05dB`.

The owner/finalized registrar retain the fee-policy controls described above. The owner can re-attest the implementation of already-enrolled adapters and transfer/renounce ownership. Initial adapter enrollment and registrar/factory bindings are finalized. Launchpad, engines, adapters and vault/collection dependencies include upgradeable contracts under their respective authorities; adapter implementation changes fail hook authorization until re-attested. The standard fee-policy controls have no enforced timelock. These privileges do not permit upgrading the immutable hook's code.

## Audit and acceptance status

No completed independent audit report is being claimed. Public source verification is not a security audit. This request seeks PancakeSwap's review/referral and listing guidance; neither PancakeSwap acceptance nor GMGN/Axiom compatibility is guaranteed.

## Separate NFT-hook submission — not ready for the Pool ID field

Do not put two hook addresses into the standard-hook form. The immutable NFT hook requires its own submission.

- AMM/chain: Infinity CL; BNB Chain only.
- Name: **PAIR Infinity NFT Rewards Hook (Immutable)**.
- Hook: `0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd`.
- Verified: **Yes**.
- Explorer: https://bscscan.com/address/0x56c0E6C4b569F62c5bf2539A386dec4db2b256Cd#code
- Source: https://github.com/pairdotfund/pair-bnb-infinity-contracts/blob/5945857388e30a16a3c436cee1733381e8e3800b/sources/9001b9323197463d219982f9f001379f7ec278ebe77ee5064f2d9fed5c597ca5/contracts/pancake-v1/bnb/immutable/BnbInfinityImmutableNftHook.sol
- Overview: non-proxy immutable NFT-rewards hook with 30 bps protocol fees, NFT-mode quote fees that depend on rewards activation, approved-adapter settlement, and permanent on-chain graduation tracking.
- **Pool IDs: none found** in this hook's registration history from block 127768836 through 127803826. Do not submit standard-hook Pool IDs here. Launch and authenticate a real NFT-mode pool first; do not spend funds or create a test pool without separate approval.
- 3.1 **No** nonzero callback deltas; 3.2 **No** dynamic LP fees; 3.3 **Yes** additional protocol/NFT-mode fees; 3.5 **No** required nonempty hookData; 3.6 **No** nested swaps in current callback/settlement code, with the same dependency caveat; 3.7 **No** callback liquidity changes; 3.8 **Yes** graduation, fee-settlement state and NFT-reward accounting.
- **3.4 differs:** the hook exposes no admin setter for an existing pool's LP fee or already-registered NFT fee rate. Its finalized registrar initializes each NFT fee policy once. The effective NFT fee can nevertheless turn on/off through the external collection's `rewardsActive()` state, and that collection is an upgradeable dependency. Disclose this distinction and obtain PancakeSwap's interpretation before finalizing the Yes/No selection for the NFT submission.
- Hook upgradeable: **No**. Privileged controls: **Yes** — ownership, re-attestation of existing adapter implementations, registrar/factory authority and upgradeable dependencies remain. Standard-mode owner-editable fee-policy behavior must not be attributed to this NFT hook.
