// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BnbInfinityHookUpgradeable} from "./BnbInfinityHookUpgradeable.sol";

interface IBnbUpgradeableAdapter {
    function hook() external view returns (address);
    function poolManager() external view returns (address);
    function owner() external view returns (address);
    function platformImplementation() external view returns (address);
}

/// @notice Approved proxy runtime AND implementation identity, not proxy bytecode alone.
contract BnbInfinityGuardedHookUpgradeable is BnbInfinityHookUpgradeable {
    mapping(address => bytes32) public adapterHash;
    mapping(address => bytes32) public adapterImplementationHash;
    bool public adaptersFrozen;
    event AdapterImplementationApproved(address indexed adapter, bytes32 implementationHash);

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

    /// @notice Owner must explicitly re-attest an upgraded adapter before it can trade.
    function approveAdapterImplementation(address adapter) external onlyOwner {
        if (!adaptersFrozen || adapterHash[adapter] == bytes32(0)
            || adapter.codehash != adapterHash[adapter]) revert InvalidPolicy();
        _approveImplementation(adapter);
    }

    function _approveImplementation(address adapter) private {
        if (adapter.code.length == 0) revert InvalidPolicy();
        IBnbUpgradeableAdapter a = IBnbUpgradeableAdapter(adapter);
        address implementation = a.platformImplementation();
        if (a.hook() != address(this) || a.poolManager() != address(poolManager)
            || a.owner() != owner() || implementation.code.length == 0) revert InvalidPolicy();
        adapterImplementationHash[adapter] = implementation.codehash;
        emit AdapterImplementationApproved(adapter, implementation.codehash);
    }

    function _authorizeAdapter(address adapter) internal view override {
        if (!adaptersFrozen || adapterHash[adapter] == bytes32(0)
            || adapter.codehash != adapterHash[adapter]
            || IBnbUpgradeableAdapter(adapter).platformImplementation().codehash != adapterImplementationHash[adapter])
            revert InvalidPolicy();
    }
}
