// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbInfinityNftHookUpgradeable} from "../BnbInfinityNftHookUpgradeable.sol";
import {BnbInfinityGuardedHookUpgradeable} from "../BnbInfinityGuardedHookUpgradeable.sol";
import {BnbInfinityLaunchEngineUpgradeable} from "../BnbInfinityLaunchEngineUpgradeable.sol";
import {BnbInfinityLaunchFactoryUpgradeable} from "../BnbInfinityLaunchFactoryUpgradeable.sol";
import {BnbInfinityCreationDeployersUpgradeable} from "../BnbInfinityCreationDeployersUpgradeable.sol";
import {BnbInfinityVaultDeployerUpgradeable} from "../BnbInfinityVaultDeployerUpgradeable.sol";
import {BnbInfinityPoolBootstrapperUpgradeable} from "../BnbInfinityPoolBootstrapperUpgradeable.sol";
import {BnbInfinityNftLaunchModuleUpgradeable} from "../BnbInfinityNftLaunchModuleUpgradeable.sol";
import {BnbNFTProxyFactoryUpgradeable} from "../BnbNFTProxyFactoryUpgradeable.sol";
import {BnbNFTCollectionProxyDeployerUpgradeable} from "../BnbNFTCollectionProxyDeployerUpgradeable.sol";
import {BnbInfinitySwapAdapterUpgradeable} from "../BnbInfinitySwapAdapterUpgradeable.sol";
import {BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable} from "../BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable.sol";
import {BnbInfinityNftDirectQuoteCoordinatorUpgradeable} from "../BnbInfinityNftDirectQuoteCoordinatorUpgradeable.sol";
import {BnbInfinityNativeBuyExecutorUpgradeable} from "../BnbInfinityNativeBuyExecutorUpgradeable.sol";

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityGuardedHookUpgradeableV2 is BnbInfinityGuardedHookUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityLaunchEngineUpgradeableV2 is BnbInfinityLaunchEngineUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityLaunchFactoryUpgradeableV2 is BnbInfinityLaunchFactoryUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityCreationDeployersUpgradeableV2 is BnbInfinityCreationDeployersUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityVaultDeployerUpgradeableV2 is BnbInfinityVaultDeployerUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityPoolBootstrapperUpgradeableV2 is BnbInfinityPoolBootstrapperUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityNftLaunchModuleUpgradeableV2 is BnbInfinityNftLaunchModuleUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbNFTProxyFactoryUpgradeableV2 is BnbNFTProxyFactoryUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbNFTCollectionProxyDeployerUpgradeableV2 is BnbNFTCollectionProxyDeployerUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinitySwapAdapterUpgradeableV2 is BnbInfinitySwapAdapterUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeableV2 is BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityNftDirectQuoteCoordinatorUpgradeableV2 is BnbInfinityNftDirectQuoteCoordinatorUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @dev Test-only upgrade adds no state and needs no reinitializer.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityNativeBuyExecutorUpgradeableV2 is BnbInfinityNativeBuyExecutorUpgradeable {
    function candidateRevision() external pure returns (uint256) { return 2; }
}

/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract TestBnbInfinityNftHookUpgradeableV2 is BnbInfinityNftHookUpgradeable { function candidateRevision() external pure returns(uint256) { return 2; } }
