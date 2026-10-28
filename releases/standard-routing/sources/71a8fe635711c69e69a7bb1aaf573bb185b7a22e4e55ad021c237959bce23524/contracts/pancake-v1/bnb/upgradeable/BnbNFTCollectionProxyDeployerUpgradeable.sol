// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PancakeV1NFTCollectionUpgradeable} from "../../PancakeV1NFTCollectionUpgradeable.sol";

/// @notice Creates independent collection proxies, all initialized atomically.
/// @dev A replacement implementation affects future creations only.
contract BnbNFTCollectionProxyDeployerUpgradeable  is BnbPlatformUUPS {
    address public  factory;
    address public  implementation;
    address public  upgradeOwner;
    address public  hook;
    error Unauthorized();

    function initializeProxy(address upgradeAuthority, address factory_, address implementation_, address upgradeOwner_, address hook_) external initializer {
_initializePlatform(upgradeAuthority);

        if (factory_ == address(0) || implementation_.code.length == 0
            || upgradeOwner_ == address(0) || hook_.code.length == 0) revert Unauthorized();
        factory = factory_;
        implementation = implementation_;
        upgradeOwner = upgradeOwner_;
        hook = hook_;
    
    }

    function deploy(address project, string calldata name, string calldata symbol,
        uint256 maxSupply, uint256 tokenCost, string calldata baseURI, address[] calldata assets)
        external returns (address collection)
    {
        if (msg.sender != factory) revert Unauthorized();
        bytes memory data = abi.encodeCall(PancakeV1NFTCollectionUpgradeable.initialize,
            (project, hook, name, symbol, maxSupply, tokenCost, baseURI, assets, upgradeOwner));
        collection = address(new ERC1967Proxy(implementation, data));
    }
}