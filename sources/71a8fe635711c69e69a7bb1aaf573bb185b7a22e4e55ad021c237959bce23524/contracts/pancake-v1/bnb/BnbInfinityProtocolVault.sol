// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {PancakeV1ProtocolFeeVault} from "../PancakeV1ProtocolFeeVault.sol";

/// @notice Fresh BNB shared vault: standard and NFT hooks share custody.
/// Unlike the historical successor, there is no permissionless V2 reinitializer.
contract BnbInfinityProtocolVault is PancakeV1ProtocolFeeVault {
    mapping(address => bool) public additionalHook;
    function authorizeAdditionalHook(address candidate) external onlyOwner {
        if (candidate.code.length == 0 || candidate == hook || additionalHook[candidate])
            revert InvalidConfiguration();
        additionalHook[candidate] = true;
    }
    function recordFee(address asset, uint256 amount) external override {
        if (msg.sender != hook && !additionalHook[msg.sender]) revert OnlyHook();
        _recordFee(asset, amount);
    }
    function recordFeeFromAdditionalHook(address asset, uint256 amount) external {
        if (!additionalHook[msg.sender]) revert OnlyHook();
        _recordFee(asset, amount);
    }
}
