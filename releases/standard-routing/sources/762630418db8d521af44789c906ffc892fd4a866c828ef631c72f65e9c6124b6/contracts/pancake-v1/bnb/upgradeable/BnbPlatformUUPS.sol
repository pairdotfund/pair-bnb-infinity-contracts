// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @notice Fresh BNB platform storage, never an upgrade of an old immutable deployment.
/// @dev Every proxy must be created with its initialization calldata in the same
/// transaction. Per-project ERC20s, LP locks and fee vaults do not inherit this.
abstract contract BnbPlatformUUPS is OwnableUpgradeable, UUPSUpgradeable {
    error WrongPlatformChain();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function _initializePlatform(address authority) internal onlyInitializing {
        if (block.chainid != 56) revert WrongPlatformChain();
        __Ownable_init(authority);
    }

    function platformImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
