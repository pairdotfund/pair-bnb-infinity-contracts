// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @notice One final treasury balance for every Infinity quote asset.
/// @dev Fees are transferred here before recordFee is called. Unknown direct
/// transfers are never made claimable by this accounting surface.
contract PancakeV1ProtocolFeeVault is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BATCH = 20;
    address public hook;
    address[] private _assets;
    mapping(address => bool) public knownAsset;
    mapping(address => uint256) public accrued;
    mapping(address => uint256) public claimed;

    error OnlyHook();
    error InvalidConfiguration();
    error InvalidBatch();
    error NothingToClaim();
    error InsufficientRecordedBalance();

    event HookUpdated(address indexed previousHook, address indexed newHook);
    event FeeRecorded(address indexed asset, uint256 amount);
    event FeeClaimed(address indexed asset, address indexed recipient, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address owner_, address hook_) external initializer {
        if (owner_ == address(0) || hook_ == address(0)) revert InvalidConfiguration();
        __Ownable_init(owner_);
        hook = hook_;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function setHook(address hook_) external onlyOwner {
        if (hook_ == address(0)) revert InvalidConfiguration();
        emit HookUpdated(hook, hook_);
        hook = hook_;
    }

    function assetCount() external view returns (uint256) { return _assets.length; }
    function assetAt(uint256 index) external view returns (address) { return _assets[index]; }

    function recordFee(address asset, uint256 amount) external virtual {
        if (msg.sender != hook) revert OnlyHook();
        _recordFee(asset, amount);
    }

    /// @dev Shared accounting for authenticated hooks in storage-compatible successors.
    function _recordFee(address asset, uint256 amount) internal {
        if (asset == address(0) || amount == 0) revert InvalidConfiguration();
        uint256 outstanding = accrued[asset] - claimed[asset];
        if (IERC20(asset).balanceOf(address(this)) < outstanding + amount) {
            revert InsufficientRecordedBalance();
        }
        if (!knownAsset[asset]) {
            knownAsset[asset] = true;
            _assets.push(asset);
        }
        accrued[asset] += amount;
        emit FeeRecorded(asset, amount);
    }

    function claim(address asset, address recipient, uint256 amount)
        external onlyOwner returns (uint256) {
        if (recipient == address(0) || amount == 0) revert InvalidConfiguration();
        uint256 available = accrued[asset] - claimed[asset];
        if (amount > available) revert NothingToClaim();
        claimed[asset] += amount;
        IERC20(asset).safeTransfer(recipient, amount);
        emit FeeClaimed(asset, recipient, amount);
        return amount;
    }

    function claimMany(address[] calldata assets, address recipient)
        external onlyOwner returns (uint256 total) {
        if (recipient == address(0) || assets.length == 0 || assets.length > MAX_BATCH) {
            revert InvalidBatch();
        }
        for (uint256 i; i < assets.length; ++i) {
            if (assets[i] == address(0)) revert InvalidBatch();
            for (uint256 j; j < i; ++j) {
                if (assets[i] == assets[j]) revert InvalidBatch();
            }
            uint256 amount = accrued[assets[i]] - claimed[assets[i]];
            if (amount != 0) {
                claimed[assets[i]] += amount;
                IERC20(assets[i]).safeTransfer(recipient, amount);
                emit FeeClaimed(assets[i], recipient, amount);
                total += amount;
            }
        }
        if (total == 0) revert NothingToClaim();
    }
}