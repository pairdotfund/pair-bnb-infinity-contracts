// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";

import {PancakeV1InfinityCreationDeployers} from "../../PancakeV1InfinityCreationDeployers.sol";
import {PancakeV1NFTCollectionProxyDeployer} from "../../PancakeV1NFTCollectionProxyDeployer.sol";

interface INFTProxyFactoryModule {
    function factory() external view returns (address);
    function hook() external view returns (address);
    function launchpad() external view returns (address);
}

/// @notice NFT factory for the EXISTING Infinity proxy entrypoint.
/// @dev Module != launchpad. Immutable collection deployer is bound to this factory.
contract BnbNFTProxyFactoryUpgradeable  is BnbPlatformUUPS {
    address public  admin;
    address public  hook;
    PancakeV1InfinityCreationDeployers public  creationDeployers;
    PancakeV1NFTCollectionProxyDeployer public  collectionDeployer;
    address public engine;
    mapping(address => address) public collectionOf;
    struct Identity { address creator; string name; string symbol; string metadataURI; bytes32 metadataHash; }
    event NFTCollectionCreated(address indexed projectToken, address indexed collection, address indexed creator);
    error InvalidConfiguration();

    function initializeProxy(address upgradeAuthority, address hook_, PancakeV1InfinityCreationDeployers deployers_,
        PancakeV1NFTCollectionProxyDeployer collectionDeployer_) external initializer {
_initializePlatform(upgradeAuthority);

        if (hook_.code.length == 0 || address(deployers_).code.length == 0
            || deployers_.admin() != msg.sender || address(collectionDeployer_).code.length == 0
            || collectionDeployer_.factory() != address(this) || collectionDeployer_.hook() != hook_)
            revert InvalidConfiguration();
        admin = msg.sender;
        hook = hook_;
        creationDeployers = deployers_;
        collectionDeployer = collectionDeployer_;
    
    }
    function bindEngine(address module) external {
        if (msg.sender != admin || engine != address(0) || module.code.length == 0
            || INFTProxyFactoryModule(module).factory() != address(this)
            || INFTProxyFactoryModule(module).hook() != hook
            || INFTProxyFactoryModule(module).launchpad() != creationDeployers.tokenLaunchpad()
            || creationDeployers.engine() != address(this)) revert InvalidConfiguration();
        engine = module;
    }
    function verifyVault(address project, uint8 mode, address destination) external view returns (bool) {
        return mode == 5 && destination != address(0) && collectionOf[project] == destination;
    }
    function tokenLaunchpad() external view returns (address) { return creationDeployers.tokenLaunchpad(); }
    function positionManager() external view returns (address) { return creationDeployers.positionManager(); }
    function vault() external view returns (address) { return creationDeployers.vault(); }
    function _lockSalt(Identity calldata i) private pure returns (bytes32) {
        return keccak256(abi.encode(keccak256("PANCAKE_V1_INFINITY_LOCK"),
            i.creator, i.name, i.symbol, i.metadataURI, i.metadataHash));
    }
    function _tokenSalt(address creator, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(keccak256("PANCAKE_V1_INFINITY_TOKEN"), creator, salt));
    }
    function predictStandard(Identity calldata i, bytes32 salt, uint256 protection)
        public view returns (address token, address lock)
    {
        if (protection != 0 || engine == address(0)) revert InvalidConfiguration();
        lock = creationDeployers.predictLock(_lockSalt(i));
        token = creationDeployers.predictStandard(_tokenSalt(i.creator, salt), i.name, i.symbol,
            i.metadataURI, i.metadataHash, lock, i.creator, creationDeployers.tokenLaunchpad(), 0);
    }
    function deploy(Identity calldata i, bytes32 salt, bytes calldata configuration, address[] calldata quotes)
        external returns (address token, address lock, address collection)
    {
        if (msg.sender != engine || engine == address(0)) revert InvalidConfiguration();
        lock = creationDeployers.lock(_lockSalt(i));
        token = creationDeployers.standard(_tokenSalt(i.creator, salt), i.name, i.symbol,
            i.metadataURI, i.metadataHash, lock, i.creator, creationDeployers.tokenLaunchpad(), 0);
        (string memory name, string memory symbol, uint256 maximum, uint256 cost, string memory uri) =
            abi.decode(configuration, (string, string, uint256, uint256, string));
        collection = collectionDeployer.deploy(token, name, symbol, maximum, cost, uri, quotes);
        collectionOf[token] = collection;
        emit NFTCollectionCreated(token, collection, i.creator);
    }
}