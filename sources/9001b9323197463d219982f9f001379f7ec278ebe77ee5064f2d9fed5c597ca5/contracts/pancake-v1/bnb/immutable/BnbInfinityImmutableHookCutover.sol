// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BnbInfinityLaunchpad} from "../BnbInfinityLaunchpad.sol";
import {IInfinityNftModule} from "../../PancakeV1LaunchpadInfinityNftUpgradeable.sol";

interface IImmutableCutoverGraph {
    function launchpad() external view returns (address);
    function hook() external view returns (address);
    function factory() external view returns (address);
    function engine() external view returns (address);
    function owner() external view returns (address);
    function validateLaunchpad(address) external view returns (bool);
}
interface IImmutableCutoverHook {
    function registrar() external view returns (address);
    function attestor() external view returns (address);
    function owner() external view returns (address);
    function protocolVault() external view returns (address);
    function frozen() external view returns (bool);
}
interface IImmutableCutoverVault {
    function additionalHook(address) external view returns (bool);
}

/// @notice Deployment-specific launchpad implementation for a future-launch-only
/// cutover. All old launchpad storage and ABI remain inherited unchanged.
/// @dev Constructor pins one reviewed old/new graph, not arbitrary mutable setters.
/// Must be installed and activated atomically while paused. No hook, old adapter,
/// existing PoolKey, project policy, pool record or fee balance is rewritten.
contract BnbInfinityImmutableHookCutover is BnbInfinityLaunchpad {
    struct Graph { address engine; address module; address direct; address nftDirect; }
    address public immutable cutoverLaunchpad;
    address public immutable cutoverProtocolVault;
    address private immutable _oldEngine;
    address private immutable _oldModule;
    address private immutable _oldDirect;
    address private immutable _oldNftDirect;
    address private immutable _newEngine;
    address private immutable _newModule;
    address private immutable _newDirect;
    address private immutable _newNftDirect;

    event ImmutableHookGraphActivated(address indexed oldEngine, address indexed newEngine,
        address indexed hook, address nftHook);

    constructor(address launchpad_, address protocolVault_, Graph memory previous, Graph memory next) {
        if (block.chainid != 56 || launchpad_.code.length == 0 || protocolVault_.code.length == 0
            || previous.engine == next.engine || previous.module == next.module
            || previous.direct == next.direct || previous.nftDirect == next.nftDirect)
            revert InvalidConfiguration();
        _validateCode(previous);
        _validateCode(next);
        cutoverLaunchpad = launchpad_;
        cutoverProtocolVault = protocolVault_;
        _oldEngine = previous.engine; _oldModule = previous.module;
        _oldDirect = previous.direct; _oldNftDirect = previous.nftDirect;
        _newEngine = next.engine; _newModule = next.module;
        _newDirect = next.direct; _newNftDirect = next.nftDirect;
    }

    function previousHookGraph() external view returns (Graph memory) {
        return Graph(_oldEngine, _oldModule, _oldDirect, _oldNftDirect);
    }
    function nextHookGraph() external view returns (Graph memory) {
        return Graph(_newEngine, _newModule, _newDirect, _newNftDirect);
    }
    function activateImmutableHooks() external onlyOwner reinitializer(2) {
        if (address(this) != cutoverLaunchpad || !paused || !graphFrozen
            || infinityEngine != _oldEngine || address(nftModule) != _oldModule
            || directQuoteCoordinator != _oldDirect || nftDirectQuoteCoordinator != _oldNftDirect)
            revert InvalidConfiguration();

        IImmutableCutoverGraph standard = IImmutableCutoverGraph(_newEngine);
        IImmutableCutoverGraph nft = IImmutableCutoverGraph(_newModule);
        if (standard.launchpad() != address(this) || !standard.validateLaunchpad(address(this))
            || nft.launchpad() != address(this)
            || IImmutableCutoverGraph(_newDirect).launchpad() != address(this)
            || IImmutableCutoverGraph(_newNftDirect).launchpad() != address(this)
            || IImmutableCutoverGraph(_newNftDirect).engine() != _newModule)
            revert InvalidConfiguration();
        address hook = standard.hook();
        address nftHook = nft.hook();
        if (hook == IImmutableCutoverGraph(_oldEngine).hook()
            || nftHook == IImmutableCutoverGraph(_oldModule).hook() || hook == nftHook)
            revert InvalidConfiguration();
        _validateHook(hook, _newEngine, standard.factory());
        _validateHook(nftHook, _newModule, nft.factory());

        infinityEngine = _newEngine;
        nftModule = IInfinityNftModule(_newModule);
        directQuoteCoordinator = _newDirect;
        nftDirectQuoteCoordinator = _newNftDirect;
        // Preserve paused=true until the exact new/old consumer manifests are
        // published and checked. Unpause is a separately approved action.
        emit ImmutableHookGraphActivated(_oldEngine, _newEngine, hook, nftHook);
    }

    function _validateHook(address hook, address engine, address factory) private view {
        IImmutableCutoverHook candidate = IImmutableCutoverHook(hook);
        if (hook.code.length == 0 || !candidate.frozen() || candidate.owner() != owner()
            || candidate.registrar() != engine || candidate.attestor() != factory
            || candidate.protocolVault() != cutoverProtocolVault
            || !IImmutableCutoverVault(cutoverProtocolVault).additionalHook(hook)
            || IImmutableCutoverGraph(factory).hook() != hook
            || IImmutableCutoverGraph(factory).engine() != engine)
            revert InvalidConfiguration();
        // Exact immutable-hook bytecode/constructor matching is enforced by the
        // release preflight. A self-reported "immutable" flag is not evidence.
    }

    function _validateCode(Graph memory graph) private view {
        if (graph.engine.code.length == 0 || graph.module.code.length == 0
            || graph.direct.code.length == 0 || graph.nftDirect.code.length == 0)
            revert InvalidConfiguration();
    }
}
