// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";
import {PancakeV1InfinityToken} from "../../PancakeV1InfinityToken.sol";
import {PancakeV1HolderToken} from "../../PancakeV1HolderToken.sol";
import {PancakeV1PermanentPositionLock} from "../../PancakeV1PermanentPositionLock.sol";
import {PancakeV1HolderDistributionVault} from "../../PancakeV1HolderDistributionVault.sol";
contract BnbInfinityCreationDeployersUpgradeable  is BnbPlatformUUPS {
    address public  admin;
    address public engine;
    address public  positionManager;
    address public  tokenLaunchpad;
    address public  vault;
    error Unauthorized();
    error AlreadyBound();
    function initializeProxy(address upgradeAuthority, address admin_,address p,address l,address v) external initializer {
_initializePlatform(upgradeAuthority);
        require(admin_ == upgradeAuthority, "UPGRADE_ADMIN_MISMATCH");

        require(admin_ != address(0));
        admin=admin_; positionManager=p; tokenLaunchpad=l; vault=v;
    
    }
    function bindEngine(address engine_) external {
        if (msg.sender != admin || engine != address(0) || engine_ == address(0)) revert Unauthorized();
        engine = engine_;
    }
    function lock(bytes32 salt) external returns(address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new PancakeV1PermanentPositionLock{salt:salt}(positionManager));
    }
    function predictLock(bytes32 salt) external view returns(address) {
        bytes32 h=keccak256(abi.encodePacked(type(PancakeV1PermanentPositionLock).creationCode,abi.encode(positionManager)));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff),address(this),salt,h)))));
    }
    function standard(bytes32 salt,string calldata n,string calldata s,string calldata u,bytes32 h,
        address locker,address creator,address mintTo,uint256 blocks_) external returns(address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new PancakeV1InfinityToken{salt:salt}(
            n,s,u,h,tokenLaunchpad,vault,positionManager,locker,creator,mintTo,blocks_));
    }
    function predictStandard(bytes32 salt,string calldata n,string calldata s,string calldata u,bytes32 h,
        address locker,address creator,address mintTo,uint256 blocks_) external view returns(address) {
        bytes32 initHash = keccak256(abi.encodePacked(type(PancakeV1InfinityToken).creationCode,
            abi.encode(n,s,u,h,tokenLaunchpad,vault,positionManager,locker,creator,mintTo,blocks_)));
        return _create2(salt, initHash);
    }
    function holder(bytes32 salt,string calldata n,string calldata s,string calldata u,bytes32 h,
        address locker,address creator,address mintTo,uint256 blocks_) external returns(address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new PancakeV1HolderToken{salt:salt}(
            n,s,u,h,tokenLaunchpad,vault,positionManager,locker,creator,mintTo,blocks_));
    }
    function predictHolder(bytes32 salt,string calldata n,string calldata s,string calldata u,bytes32 h,
        address locker,address creator,address mintTo,uint256 blocks_) external view returns(address) {
        bytes32 initHash = keccak256(abi.encodePacked(type(PancakeV1HolderToken).creationCode,
            abi.encode(n,s,u,h,tokenLaunchpad,vault,positionManager,locker,creator,mintTo,blocks_)));
        return _create2(salt, initHash);
    }
    function bind(address token, address vault_) external {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        PancakeV1HolderToken(token).bindVaultAndMint(PancakeV1HolderDistributionVault(vault_));
    }
    function _create2(bytes32 salt, bytes32 initHash) private view returns(address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), salt, initHash
        )))));
    }
}