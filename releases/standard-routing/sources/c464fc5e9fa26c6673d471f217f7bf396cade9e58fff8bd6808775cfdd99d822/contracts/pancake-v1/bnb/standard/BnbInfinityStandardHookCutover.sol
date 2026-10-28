// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbInfinityImmutableHookCutover, IImmutableCutoverGraph, IImmutableCutoverHook}
    from "../immutable/BnbInfinityImmutableHookCutover.sol";
import {IInfinityNftModule} from "../../PancakeV1LaunchpadInfinityNftUpgradeable.sol";

interface IStandardCreditGraph {
    function creditHook(address hook) external view returns(bool);
}
interface IStandardHookVersion {
    function feeAccountingVersion() external view returns(uint8);
}

/// @notice Future-launch cutover after the already-used immutable-hook
/// reinitializer(2). Appends no storage. Old pools/vaults remain untouched.
contract BnbInfinityStandardHookCutover is BnbInfinityImmutableHookCutover {
    constructor(address launchpad_, address protocol_, Graph memory previous, Graph memory next)
        BnbInfinityImmutableHookCutover(launchpad_, protocol_, previous, next) {}

    function activateStandardRouting() external onlyOwner reinitializer(3) {
        Graph memory previous = this.previousHookGraph();
        Graph memory next = this.nextHookGraph();
        if (address(this) != cutoverLaunchpad || !paused || !graphFrozen
            || infinityEngine != previous.engine || address(nftModule) != previous.module
            || directQuoteCoordinator != previous.direct || nftDirectQuoteCoordinator != previous.nftDirect)
            revert InvalidConfiguration();
        IImmutableCutoverGraph standard = IImmutableCutoverGraph(next.engine);
        IImmutableCutoverGraph nft = IImmutableCutoverGraph(next.module);
        if (standard.launchpad() != address(this) || !standard.validateLaunchpad(address(this))
            || nft.launchpad() != address(this)
            || IImmutableCutoverGraph(next.direct).launchpad() != address(this)
            || IImmutableCutoverGraph(next.nftDirect).launchpad() != address(this)
            || IImmutableCutoverGraph(next.nftDirect).engine() != next.module)
            revert InvalidConfiguration();
        address standardHook = standard.hook();
        address nftHook = nft.hook();
        if (standardHook == IImmutableCutoverGraph(previous.engine).hook()
            || nftHook == IImmutableCutoverGraph(previous.module).hook() || standardHook == nftHook)
            revert InvalidConfiguration();
        _validateStandardHook(standardHook, next.engine, standard.factory());
        _validateStandardHook(nftHook, next.module, nft.factory());
        infinityEngine = next.engine;
        nftModule = IInfinityNftModule(next.module);
        directQuoteCoordinator = next.direct;
        nftDirectQuoteCoordinator = next.nftDirect;
        emit ImmutableHookGraphActivated(previous.engine, next.engine, standardHook, nftHook);
        // Deliberately remains paused until dual-release app consumers verify.
    }
    function _validateStandardHook(address hook_, address engine_, address factory_) private view {
        IImmutableCutoverHook candidate = IImmutableCutoverHook(hook_);
        if (!candidate.frozen() || candidate.owner() != owner()
            || candidate.registrar() != engine_ || candidate.attestor() != factory_
            || candidate.protocolVault() != cutoverProtocolVault
            || IStandardHookVersion(hook_).feeAccountingVersion() != 2
            || !IStandardCreditGraph(cutoverProtocolVault).creditHook(hook_)
            || IImmutableCutoverGraph(factory_).hook() != hook_
            || IImmutableCutoverGraph(factory_).engine() != engine_) revert InvalidConfiguration();
    }
}
