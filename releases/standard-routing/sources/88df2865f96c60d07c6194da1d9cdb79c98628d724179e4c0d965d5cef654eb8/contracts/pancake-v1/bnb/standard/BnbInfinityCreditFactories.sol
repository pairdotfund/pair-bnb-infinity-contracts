// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BnbInfinityVaultDeployerUpgradeable} from "../upgradeable/BnbInfinityVaultDeployerUpgradeable.sol";
import {BnbInfinityLaunchFactoryUpgradeable} from "../upgradeable/BnbInfinityLaunchFactoryUpgradeable.sol";
import {PancakeV1FeeSharingVault} from "../../PancakeV1FeeSharingVault.sol";
import {
    BnbInfinityCreditCreatorVault, BnbInfinityCreditSharingVault, BnbInfinityCreditHolderVault
} from "./BnbInfinityCreditVaults.sol";

/// @notice New-graph implementations only; no migration of existing vaults.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityCreditVaultDeployer is BnbInfinityVaultDeployerUpgradeable {
    function creator(address project, address recipient, uint16 bps) external override returns (address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new BnbInfinityCreditCreatorVault(project, hook, engine, recipient, bps));
    }
    function sharing(address project, PancakeV1FeeSharingVault.Recipient[] calldata recipients,
        address verifier, uint16 bps) external override returns (address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new BnbInfinityCreditSharingVault(project, hook, engine, verifier, recipients, bps));
    }
}

/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityCreditLaunchFactory is BnbInfinityLaunchFactoryUpgradeable {
    function _newHolderVault(address token, address[] memory excluded_) internal override returns (address) {
        return address(new BnbInfinityCreditHolderVault(token, hook, address(this), excluded_));
    }
}
