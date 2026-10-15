// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PancakeV1InfinityHook} from "../../PancakeV1InfinityHook.sol";
import {IPancakeV1CLPoolManager} from "../../PancakeV1InfinityHookTypes.sol";

interface IBnbImmutableHookAdapter {
    function hook() external view returns (address);
    function poolManager() external view returns (address);
    function owner() external view returns (address);
    function platformImplementation() external view returns (address);
}

/// @notice Constructor-deployed, non-proxy successor of the BNB guarded hook.
/// @dev Fee callbacks are inherited unchanged from the same immutable core that
/// the deployed BNB upgradeable core mirrors. Owner policy and adapter controls
/// remain privileged controls; immutable bytecode does not make them immutable.
contract BnbInfinityImmutableHook is PancakeV1InfinityHook {
    mapping(address => bytes32) public adapterHash;
    mapping(address => bytes32) public adapterImplementationHash;
    bool public adaptersFrozen;
    event AdapterImplementationApproved(address indexed adapter, bytes32 implementationHash);

    constructor(IPancakeV1CLPoolManager manager, address admin, address protocol)
        PancakeV1InfinityHook(manager, address(0), admin, protocol) {
        require(block.chainid == 56, "BNB_ONLY");
        require(address(manager) == 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b, "BNB_MANAGER");
    }

    function attestAdapters(address[] calldata adapters, bytes32[] calldata hashes) external onlyOwner {
        if (adaptersFrozen || adapters.length == 0 || adapters.length > 8
            || adapters.length != hashes.length) revert InvalidPolicy();
        for (uint256 i; i < adapters.length; ++i) {
            address a = adapters[i];
            if (a.codehash != hashes[i] || adapterHash[a] != bytes32(0)) revert InvalidPolicy();
            _approveImplementation(a);
            adapterHash[a] = hashes[i];
        }
        adaptersFrozen = true;
    }

    function approveAdapterImplementation(address adapter) external onlyOwner {
        if (!adaptersFrozen || adapterHash[adapter] == bytes32(0)
            || adapter.codehash != adapterHash[adapter]) revert InvalidPolicy();
        _approveImplementation(adapter);
    }

    function _approveImplementation(address adapter) private {
        if (adapter.code.length == 0) revert InvalidPolicy();
        IBnbImmutableHookAdapter a = IBnbImmutableHookAdapter(adapter);
        address implementation = a.platformImplementation();
        if (a.hook() != address(this) || a.poolManager() != address(poolManager)
            || a.owner() != owner() || implementation.code.length == 0) revert InvalidPolicy();
        adapterImplementationHash[adapter] = implementation.codehash;
        emit AdapterImplementationApproved(adapter, implementation.codehash);
    }

    function _authorizeAdapter(address adapter) internal view override {
        if (!adaptersFrozen || adapterHash[adapter] == bytes32(0)
            || adapter.codehash != adapterHash[adapter]
            || IBnbImmutableHookAdapter(adapter).platformImplementation().codehash != adapterImplementationHash[adapter])
            revert InvalidPolicy();
    }
}
