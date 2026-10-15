// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";

import {PancakeV1HolderToken} from "../../PancakeV1HolderToken.sol";
import {PancakeV1InfinityCreationDeployers} from "../../PancakeV1InfinityCreationDeployers.sol";
import {PancakeV1HolderDistributionVault} from "../../PancakeV1HolderDistributionVault.sol";
import {PancakeV1FeeSharingVault} from "../../PancakeV1FeeSharingVault.sol";
interface IPancakeV1InfinityVaultDeployer {
    function admin() external view returns(address);
    function engine() external view returns(address);
    function hook() external view returns(address);
    function creator(address,address,uint16) external returns(address);
    function sharing(address,PancakeV1FeeSharingVault.Recipient[] calldata,address,uint16) external returns(address);
}

interface IPancakeV1InfinityHookFactory {
    function addressOf() external view returns (address);
    function poolManager() external view returns (address);
}
interface IPancakeV1InfinityManager { function vault() external view returns (address); }
interface IPancakeV1InfinityGraphEngine {
    function launchpad() external view returns (address);
    function factory() external view returns (address);
    function hook() external view returns (address);
}

/// @notice CREATE2 factory for the hooked Infinity release. Standard tokens
/// use the existing  token; holder launches use a token/vault pair
/// whose vault is bound before the initial mint.
contract BnbInfinityLaunchFactoryUpgradeable  is BnbPlatformUUPS {
    address public  admin;
    address public  launchpad;
    address public engine;
    address public  tokenLaunchpad;
    address public  vault;
    address public  positionManager;
    address public  hook;
    IPancakeV1InfinityVaultDeployer public  vaultDeployer;
    PancakeV1InfinityCreationDeployers public  creationDeployers;
    bool public frozen;
    mapping(address => mapping(uint8 => mapping(address => bool))) public attestedVault;

    error OnlyLaunchpad();
    error Occupied();
    error InvalidConfiguration();
    error AttestationAuthority();
    event HolderDeployed(address indexed token, address indexed lock, address indexed holderVault);
    event VaultAttested(address indexed project, uint8 indexed mode, address indexed vault);

    struct Identity {
        address creator;
        string name;
        string symbol;
        string metadataURI;
        bytes32 metadataHash;
    }

    function initializeProxy(address upgradeAuthority, address admin_, address tokenLaunchpad_, address vault_, address positionManager_, address hook_,
        IPancakeV1InfinityVaultDeployer vaultDeployer_, PancakeV1InfinityCreationDeployers creationDeployers_) external initializer {
_initializePlatform(upgradeAuthority);
        require(admin_ == upgradeAuthority, "UPGRADE_ADMIN_MISMATCH");

        if (admin_ == address(0) || tokenLaunchpad_ == address(0) || vault_.code.length == 0 || positionManager_.code.length == 0
            || hook_.code.length == 0 || address(vaultDeployer_).code.length == 0
            || vaultDeployer_.hook() != hook_ || vaultDeployer_.admin() != admin_
            || address(creationDeployers_).code.length == 0 || creationDeployers_.admin() != admin_
            || creationDeployers_.positionManager() != positionManager_) revert InvalidConfiguration();
        admin = admin_;
        launchpad = tokenLaunchpad_;
        tokenLaunchpad = tokenLaunchpad_;
        vault = vault_;
        positionManager = positionManager_;
        hook = hook_;
        vaultDeployer = vaultDeployer_;
        creationDeployers = creationDeployers_;
    
    }

    function bindEngine(address engine_) external {
        if (msg.sender != admin || frozen || engine_ == address(0) || engine_.code.length == 0) {
            revert AttestationAuthority();
        }
        (bool ok, bytes memory data) = engine_.staticcall(abi.encodeWithSignature("factory()"));
        if (!ok || data.length < 32 || abi.decode(data, (address)) != address(this)) revert InvalidConfiguration();
        (ok, data) = engine_.staticcall(abi.encodeWithSignature("hook()"));
        if (!ok || data.length < 32 || abi.decode(data, (address)) != hook) revert InvalidConfiguration();
        // The protected release coordinator binds these two creation helpers
        // to this factory before this final graph edge is frozen.  Requiring
        // the reciprocal identity here prevents a helper from being swapped
        // after activation without allowing the factory to self-authorize a
        // helper binding.
        if (creationDeployers.engine() != address(this)
            || vaultDeployer.engine() != address(this)) revert InvalidConfiguration();
        engine = engine_;
        frozen = true;
    }

    /// @notice Compact reciprocal graph check consumed by the storage-safe
    /// launchpad successor initializer.
    function validateGraph(address launchpad_, address engine_) external view returns (bool) {
        if (!frozen || engine_ != engine || tokenLaunchpad != launchpad_
            || IPancakeV1InfinityGraphEngine(engine_).launchpad() != launchpad_
            || IPancakeV1InfinityGraphEngine(engine_).factory() != address(this)
            || IPancakeV1InfinityGraphEngine(engine_).hook() != hook
            || creationDeployers.engine() != address(this)
            || vaultDeployer.engine() != address(this)) return false;
        return true;
    }

    function deployStandard(Identity calldata i, bytes32 salt, uint256 protectionBlocks)
        external returns (address token, address lock) {
        if (!frozen || msg.sender != engine) revert OnlyLaunchpad();
        (token, lock) = predictStandard(i, salt, protectionBlocks);
        if (token.code.length != 0 || lock.code.length != 0) revert Occupied();
        lock = creationDeployers.lock(_lockSalt(i));
        Identity memory m = i;
        token = _deployStandardToken(m, salt, lock, protectionBlocks);
    }

    /// @notice Predicts the exact standard Infinity token and lock addresses.
    /// The user salt is creator-bound by _tokenSalt but is otherwise unrestricted:
    /// vanity policy (if any) belongs to the website, never this factory.
    function predictStandard(Identity calldata i, bytes32 salt, uint256 protectionBlocks)
        public view returns (address token, address lock) {
        lock = creationDeployers.predictLock(_lockSalt(i));
        token = creationDeployers.predictStandard(
            _tokenSalt(i.creator, salt), i.name, i.symbol, i.metadataURI, i.metadataHash,
            lock, i.creator, engine, protectionBlocks
        );
    }

    function _deployStandardToken(Identity memory i, bytes32 salt, address lock, uint256 protectionBlocks)
        private returns (address token) {
        return creationDeployers.standard(_tokenSalt(i.creator, salt), i.name, i.symbol, i.metadataURI,
            i.metadataHash, lock, i.creator, engine, protectionBlocks);
    }

    function deployHolder(Identity calldata i, bytes32 salt, uint256 protectionBlocks,
        address[] calldata excluded, address[] calldata assets)
        external returns (address token, address lock, address holderVault) {
        if (!frozen || msg.sender != engine) revert OnlyLaunchpad();
        (token, lock) = predictHolder(i, salt, protectionBlocks);
        if (token.code.length != 0 || lock.code.length != 0) revert Occupied();
        lock = creationDeployers.lock(_lockSalt(i));
        token = _deployHolderToken(i, salt, lock, protectionBlocks);
        holderVault = _deployHolderVault(token, excluded, lock);
        _attest(token, 4, holderVault);
        for (uint256 i; i < assets.length; ++i) {
            PancakeV1HolderDistributionVault(holderVault).registerAsset(assets[i]);
        }
        creationDeployers.bind(token, holderVault);
        emit HolderDeployed(token, lock, holderVault);
    }

    /// @notice Predicts the exact holder-token address before vault binding.
    function predictHolder(Identity calldata i, bytes32 salt, uint256 protectionBlocks)
        public view returns (address token, address lock) {
        lock = creationDeployers.predictLock(_lockSalt(i));
        token = _predictHolderToken(i, salt, lock, protectionBlocks);
    }

    function attestVault(address project, uint8 mode, address vault_) external {
        if (!frozen || msg.sender != engine || project == address(0) || vault_.code.length == 0) revert AttestationAuthority();
        _attest(project, mode, vault_);
    }
    function deployCreatorVault(address project, address recipient, uint16 feeBps)
        external returns (address vault_) {
        if (!frozen || msg.sender != engine || recipient == address(0)) revert AttestationAuthority();
        vault_ = vaultDeployer.creator(project, recipient, feeBps);
        _attest(project, 1, vault_);
    }
    function deploySharingVault(address project, PancakeV1FeeSharingVault.Recipient[] calldata recipients,
        address verifier, uint16 feeBps) external returns (address vault_) {
        if (!frozen || msg.sender != engine || verifier == address(0)) revert AttestationAuthority();
        vault_ = vaultDeployer.sharing(project, recipients, verifier, feeBps);
        _attest(project, 3, vault_);
    }
    function verifyVault(address project, uint8 mode, address vault_) external view returns (bool) {
        return attestedVault[project][mode][vault_];
    }
    function _attest(address project, uint8 mode, address vault_) private {
        if (PancakeV1HolderDistributionVault(vault_).projectToken() != project
            || PancakeV1HolderDistributionVault(vault_).hook() != hook) revert InvalidConfiguration();
        attestedVault[project][mode][vault_] = true;
        emit VaultAttested(project, mode, vault_);
    }

    function _deployHolderToken(Identity calldata i, bytes32 salt, address lock, uint256 protectionBlocks)
        private returns (address token) {
        return creationDeployers.holder(_tokenSalt(i.creator, salt), i.name, i.symbol, i.metadataURI,
            i.metadataHash, lock, i.creator, engine, protectionBlocks);
    }

    function _predictHolderToken(Identity calldata i, bytes32 salt, address lock, uint256 protectionBlocks)
        private view returns (address token) {
        return creationDeployers.predictHolder(_tokenSalt(i.creator, salt), i.name, i.symbol,
            i.metadataURI, i.metadataHash, lock, i.creator, engine, protectionBlocks);
    }

    function _deployHolderVault(address token, address[] calldata excluded, address lock)
        private returns (address) {
        address manager = _manager();
        (bool ok, bytes memory data) = manager.staticcall(
            abi.encodeWithSelector(IPancakeV1InfinityManager.vault.selector));
        address custody = ok && data.length >= 32 ? abi.decode(data, (address)) : manager;
        uint256 count = 1;
        if (manager != engine) ++count;
        if (custody != engine && custody != manager) ++count;
        if (positionManager != engine && positionManager != manager && positionManager != custody) ++count;
        if (lock != engine && lock != manager && lock != custody && lock != positionManager) ++count;
        if (tokenLaunchpad != engine && tokenLaunchpad != manager && tokenLaunchpad != custody && tokenLaunchpad != positionManager && tokenLaunchpad != lock) ++count;
        for (uint256 i; i < excluded.length; ++i) {
            if (!_forced(excluded[i], manager, custody, lock, token) && !_contains(excluded, i, excluded[i])) ++count;
        }
        address[] memory all = new address[](count);
        all[0] = engine;
        uint256 n = 1;
        if (manager != engine) all[n++] = manager;
        if (custody != engine && custody != manager) all[n++] = custody;
        if (positionManager != engine && positionManager != manager && positionManager != custody) all[n++] = positionManager;
        if (lock != engine && lock != manager && lock != custody && lock != positionManager) all[n++] = lock;
        if (tokenLaunchpad != engine && tokenLaunchpad != manager && tokenLaunchpad != custody && tokenLaunchpad != positionManager && tokenLaunchpad != lock) all[n++] = tokenLaunchpad;
        for (uint256 i; i < excluded.length; ++i) {
            if (!_forced(excluded[i], manager, custody, lock, token) && !_contains(excluded, i, excluded[i])) all[n++] = excluded[i];
        }
        return address(new PancakeV1HolderDistributionVault(token, hook, address(this), all));
    }

    function _forced(address a, address manager, address custody, address lock, address token) private view returns (bool) {
        return a == address(0) || a == 0x000000000000000000000000000000000000dEaD
            || a == address(this) || a == engine || a == manager || a == custody || a == positionManager
            || a == lock || a == tokenLaunchpad || a == token;
    }
    function _manager() private view returns (address manager) {
        (bool ok, bytes memory data) = hook.staticcall(abi.encodeWithSelector(
            IPancakeV1InfinityHookFactory.poolManager.selector));
        manager = ok && data.length >= 32 ? abi.decode(data, (address)) : positionManager;
    }
    function _contains(address[] calldata a, uint256 end, address value) private pure returns (bool) {
        for (uint256 i; i < end; ++i) if (a[i] == value) return true;
        return false;
    }

    function predictLock(Identity calldata i) external view returns (address) {
        return creationDeployers.predictLock(_lockSalt(i));
    }

    function _lockSalt(Identity calldata i) private pure returns (bytes32) {
        return keccak256(abi.encode(keccak256("PANCAKE_V1_INFINITY_LOCK"), i.creator, i.name,
            i.symbol, i.metadataURI, i.metadataHash));
    }
    function _tokenSalt(address creator, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(keccak256("PANCAKE_V1_INFINITY_TOKEN"), creator, salt));
    }
    function _create2(bytes32 salt, bytes32 hash) private view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff), address(this), salt, hash
        )))));
    }
}