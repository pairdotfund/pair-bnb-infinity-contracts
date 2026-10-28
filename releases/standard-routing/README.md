# PAIR BNB Infinity — standard-routing release

Active on BNB Chain (56), for **future launches only**. Existing pools retain their original hook/adapter/vault graphs.

- Standard immutable hook: [0x01d6f615032DC9fcF8531e0F9007C0C954b31b64](https://bscscan.com/address/0x01d6f615032DC9fcF8531e0F9007C0C954b31b64#code)
- NFT immutable hook: [0x902d4Af4615Ce00399a0Cda971482EB901F5dF3d](https://bscscan.com/address/0x902d4Af4615Ce00399a0Cda971482EB901F5dF3d#code)
- Shared launchpad proxy: 0xb7281262252a054e6B3c886F4c6B2353f9E7F742
- Current launchpad implementation: 0x9A308E7c71B0594226b5c4AC2FcD465960cCd0E8
- New credit-accounting protocol vault: 0x937AE9Ed602367C078bF966e86894f8bA476731A
- Official CLQuoter: 0xd0737C9762912dD34c3271197E362Aa736Df0926
- Official Universal Router: 0xd9C500DfF816a1Da21A48A732d3498Bf09dc9AEB

## Behavior and trust

Both hooks accept standard CLPoolManager swap callers, without a PAIR adapter allowlist or cooperative fee-settlement callback.
They return **nonzero callback deltas**. Quotes are fee-inclusive: do not add legacy gross-up again.
The PAIR funding helper is optional and executes through the official Universal Router.
Static 1% LP fees and fixed 30 bps protocol fees are separate from mode-specific policy fees.
The standard hook supports no-project-fee, creator, burn, sharing and holder modes; the separate NFT hook supports NFT rewards.
Accrual records recipient/holder/NFT rights at trade time. Public burn/distribution triggers cannot redirect fees or claim others' rewards.
Burns transfer to the dead address; they do not reduce ERC-20 totalSupply.
Claims automatically redeem pending custody credits. Permissionless actions still require a caller to submit and pay for a transaction.

The hooks are constructor-deployed and have no proxy/UUPS upgrade path. Their privileged owner policy controls remain.
Platform implementations, funding helpers and supporting vault/factory contracts remain upgradeable.
The owner/admin, not the token creator, holds the privileged policy controls.
See the complete source for policy restrictions and dependency authority.
This is **not** a completed independent audit or PancakeSwap/terminal whitelist approval.

## Exact compiler evidence and reproduction

The versioned sources directory is keyed by the SHA-256 of its unmodified standard-JSON compiler input.
Multiple compiler inputs can contain different historical contents for the same Solidity import path; do not flatten them.
Install Node.js, run `npm install --ignore-scripts`, then `npm run compile`.
The script uses pinned solc 0.8.26 and checks exact creation bytecode and runtime templates against the packaged artifacts.
Constructor arguments, runtime hashes and deployment transaction hashes are recorded per address in manifest.json.
Explorer and Sourcify results are separate reports; an automatic BscScan Similar Match is not an exact PAIR source listing.
