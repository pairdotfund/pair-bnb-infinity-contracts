// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PancakeV1ProtocolFeeVault} from "./PancakeV1ProtocolFeeVault.sol";

/// @notice Additive successor for the existing V2 protocol vault proxy.
/// @dev The deployed V2 (archived Blockscout compiler build) already has the
/// additionalHooks mapping in slot 5. Its initializer, administration and
/// recordFee authorization MUST remain callable after this upgrade.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
/// @dev The live proxy has already run the inherited initializers.
contract PancakeV1ProtocolFeeVaultNftUpgradeable is PancakeV1ProtocolFeeVault {
    mapping(address => bool) public additionalHooks;

    event AdditionalHookUpdated(address indexed hook, bool enabled);
    event AdditionalHookAuthorized(address indexed hook);

    error InvalidAdditionalHook();

    /// @notice Exact deployed V2 API, retained for existing integrations.
    /// @dev Already consumed by the live V2 proxy; never rerun it on upgrade.
    function initializeV2(address hook_) external reinitializer(2) {
        if (hook_ == address(0)) revert InvalidConfiguration();
        additionalHooks[hook_] = true;
        emit AdditionalHookUpdated(hook_, true);
    }

    /// @notice Exact deployed V2 owner authorization semantics.
    function setAdditionalHook(address hook_, bool enabled) external onlyOwner {
        if (hook_ == address(0) || (hook_ == hook && !enabled)) revert InvalidConfiguration();
        additionalHooks[hook_] = enabled;
        emit AdditionalHookUpdated(hook_, enabled);
    }

    /// @notice Existing V2 hooks and the original hook retain recordFee.
    function recordFee(address asset, uint256 amount) external override {
        if (msg.sender != hook && !additionalHooks[msg.sender]) revert OnlyHook();
        _recordFee(asset, amount);
    }

    /// @notice Optional singular alias for clients written for NFT mode 5.
    function additionalHook(address hook_) external view returns (bool) {
        return additionalHooks[hook_];
    }

    /// @notice Adds an NFT hook without rebinding the existing historical hook.
    /// The owner must attest the candidate runtime and graph before this call.
    function authorizeAdditionalHook(address hook_) external onlyOwner {
        if (hook_ == address(0) || hook_ == hook || hook_.code.length == 0
            || additionalHooks[hook_]) revert InvalidAdditionalHook();
        additionalHooks[hook_] = true;
        emit AdditionalHookUpdated(hook_, true);
        emit AdditionalHookAuthorized(hook_);
    }

    /// @notice Record fees already transferred by an attested additional hook.
    /// No admin sweep or alternative withdrawal surface is added.
    function recordFeeFromAdditionalHook(address asset, uint256 amount) external {
        if (!additionalHooks[msg.sender]) revert OnlyHook();
        _recordFee(asset, amount);
    }
}