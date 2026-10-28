// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PancakeV1InfinityHook} from "../PancakeV1InfinityHook.sol";
import {IPancakeV1CLPoolManager} from "../PancakeV1InfinityHookTypes.sol";

interface IBnbAdapterBinding {
    function hook() external view returns (address);
    function poolManager() external view returns (address);
}

/// @notice BNB candidate. Arbitrary lockers cannot evade deferred output fees.
/// Frozen adapter hashes must be obtained from the reviewed compiler build,
/// never from an untrusted adapter's self-reported identity.
contract BnbInfinityHook is PancakeV1InfinityHook {
    mapping(address => bytes32) public adapterHash;
    bool public adaptersFrozen;

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
            if (a.code.length == 0 || a.codehash != hashes[i] || adapterHash[a] != bytes32(0)
                || IBnbAdapterBinding(a).hook() != address(this)
                || IBnbAdapterBinding(a).poolManager() != address(poolManager)) revert InvalidPolicy();
            adapterHash[a] = hashes[i];
        }
        adaptersFrozen = true;
    }

    function _authorizeAdapter(address adapter) internal view override {
        if (!adaptersFrozen || adapterHash[adapter] == bytes32(0)
            || adapter.codehash != adapterHash[adapter]) revert InvalidPolicy();
    }
}
