// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Keeperless cumulative quote-fee distribution for a PAIR token.
/// @dev The project token must call checkpoint before each balance update.
contract PancakeV1HolderDistributionVault {
    using SafeERC20 for IERC20;

    uint256 public constant MAGNITUDE = 2 ** 128;
    uint256 public constant MAX_ASSETS = 5;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public immutable projectToken;
    address public immutable hook;
    address public immutable registrar;
    mapping(address => bool) public excluded;
    address[] private _assets;
    mapping(address => bool) public registeredAsset;
    uint256 public eligibleSupply;
    mapping(address => uint256) public magnifiedFeePerShare;
    mapping(address => uint256) public magnifiedRemainder;
    mapping(address => uint256) public pending;
    mapping(address => uint256) public accrued;
    mapping(address => uint256) public claimed;
    mapping(address => mapping(address => int256)) private _correction;
    mapping(address => mapping(address => uint256)) public withdrawn;

    error OnlyHook();
    error OnlyRegistrar();
    error OnlyProjectToken();
    error InvalidConfiguration();
    error NoClaim();
    error InsufficientRecordedBalance();

    event AssetRegistered(address indexed asset);
    event FeeRecorded(address indexed asset, uint256 amount, uint256 eligibleSupply);
    event Checkpoint(address indexed from, address indexed to, uint256 amount, uint256 eligibleSupply);
    event FeeClaimed(address indexed holder, address indexed asset, uint256 amount);

    constructor(address project_, address hook_, address registrar_, address[] memory excluded_) {
        if (project_ == address(0) || hook_ == address(0) || registrar_ == address(0) || excluded_.length > 32) {
            revert InvalidConfiguration();
        }
        projectToken = project_;
        hook = hook_;
        registrar = registrar_;
        excluded[address(0)] = true;
        excluded[address(this)] = true;
        excluded[DEAD] = true;
        for (uint256 i; i < excluded_.length; ++i) {
            if (excluded_[i] == address(0) || excluded_[i] == project_ || excluded[excluded_[i]]) {
                revert InvalidConfiguration();
            }
            excluded[excluded_[i]] = true;
        }
    }

    function assetCount() external view returns (uint256) { return _assets.length; }
    function assetAt(uint256 index) external view returns (address) { return _assets[index]; }

    function registerAsset(address asset) external {
        if (msg.sender != registrar && msg.sender != hook) revert OnlyRegistrar();
        if (asset == address(0) || registeredAsset[asset] || _assets.length >= MAX_ASSETS) {
            revert InvalidConfiguration();
        }
        registeredAsset[asset] = true;
        _assets.push(asset);
        emit AssetRegistered(asset);
    }

    function recordFee(address asset, uint256 amount) external {
        if (msg.sender != hook) revert OnlyHook();
        if (!registeredAsset[asset] || amount == 0) revert InvalidConfiguration();
        uint256 outstanding = accrued[asset] - claimed[asset];
        if (_backedBalance(asset) < outstanding + amount) {
            revert InsufficientRecordedBalance();
        }
        accrued[asset] += amount;
        if (eligibleSupply == 0) pending[asset] += amount;
        else _distribute(asset, amount);
        emit FeeRecorded(asset, amount, eligibleSupply);
    }

    function checkpoint(address from, address to, uint256 amount) external {
        if (msg.sender != projectToken) revert OnlyProjectToken();
        if (amount == 0 || from == to) return;
        bool fromEligible = !excluded[from];
        bool toEligible = !excluded[to];
        if (fromEligible) {
            if (eligibleSupply < amount) revert InvalidConfiguration();
            eligibleSupply -= amount;
        }
        if (toEligible) eligibleSupply += amount;
        for (uint256 i; i < _assets.length; ++i) {
            address asset = _assets[i];
            uint256 mps = magnifiedFeePerShare[asset];
            if (fromEligible) _correction[asset][from] += int256(mps * amount);
            if (toEligible) _correction[asset][to] -= int256(mps * amount);
            if (eligibleSupply != 0 && pending[asset] != 0) {
                uint256 deferred = pending[asset];
                pending[asset] = 0;
                _distribute(asset, deferred);
            }
        }
        emit Checkpoint(from, to, amount, eligibleSupply);
    }

    function _distribute(address asset, uint256 amount) private {
        uint256 numerator = amount * MAGNITUDE + magnifiedRemainder[asset];
        magnifiedFeePerShare[asset] += numerator / eligibleSupply;
        magnifiedRemainder[asset] = numerator % eligibleSupply;
    }

    function withdrawableOf(address holder, address asset) public view returns (uint256) {
        if (excluded[holder] || !registeredAsset[asset]) return 0;
        int256 value = int256(magnifiedFeePerShare[asset] * IERC20(projectToken).balanceOf(holder))
            + _correction[asset][holder];
        if (value <= 0) return 0;
        uint256 total = uint256(value) / MAGNITUDE;
        return total > withdrawn[asset][holder] ? total - withdrawn[asset][holder] : 0;
    }

    function correctionOf(address holder, address asset) external view returns (int256) {
        return _correction[asset][holder];
    }

    function claimMany(address[] calldata assets) external returns (uint256 total) {
        if (assets.length == 0 || assets.length > MAX_ASSETS) revert InvalidConfiguration();
        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            uint256 amount = withdrawableOf(msg.sender, asset);
            if (amount != 0) {
                withdrawn[asset][msg.sender] += amount;
                claimed[asset] += amount;
                _beforePayout(asset);
                IERC20(asset).safeTransfer(msg.sender, amount);
                emit FeeClaimed(msg.sender, asset, amount);
                total += amount;
            }
        }
        if (total == 0) revert NoClaim();
    }
    function _backedBalance(address asset) internal view virtual returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
    function _beforePayout(address) internal virtual {}
}