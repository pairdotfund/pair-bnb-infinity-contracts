// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Quote-token creator fee vault with append-only, admin-authorized
/// recipient epochs. An epoch change only affects fees recorded afterwards.
contract PancakeV1CreatorFeeVault {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_FEE_BPS = BPS;
    uint8 public constant MAX_EPOCHS = 64;
    address public immutable projectToken;
    address public immutable hook;
    address public immutable admin;

    struct Policy {
        uint64 activatesAt;
        address recipient;
        uint16 feeBps;
    }
    Policy[] private _policies;
    mapping(address => uint256) public accrued;
    mapping(address => uint256) public claimed;
    mapping(address => mapping(address => uint256)) public claimable;

    error OnlyHook();
    error OnlyAdmin();
    error InvalidConfiguration();
    error NoClaim();
    error InsufficientRecordedBalance();

    event PolicyAppended(uint64 indexed epoch, uint64 activatesAt, address indexed recipient, uint16 feeBps);
    event FeeRecorded(uint64 indexed epoch, address indexed asset, uint256 amount, address indexed recipient);
    event FeeClaimed(address indexed recipient, address indexed asset, uint256 amount);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    constructor(address project_, address hook_, address admin_, address recipient_, uint16 feeBps_) {
        if (project_ == address(0) || hook_ == address(0) || admin_ == address(0)
            || recipient_ == address(0) || feeBps_ > MAX_FEE_BPS) revert InvalidConfiguration();
        projectToken = project_;
        hook = hook_;
        admin = admin_;
        _policies.push(Policy(0, recipient_, feeBps_));
        emit PolicyAppended(1, 0, recipient_, feeBps_);
    }

    function epochCount() external view returns (uint256) { return _policies.length; }
    function policy(uint256 epoch) external view returns (Policy memory) {
        return _policies[epoch - 1];
    }

    function currentPolicy() public view returns (uint64 epoch, address recipient, uint16 feeBps) {
        epoch = uint64(_policies.length);
        while (epoch > 1 && _policies[epoch - 1].activatesAt > block.timestamp) --epoch;
        Policy memory p = _policies[epoch - 1];
        return (epoch, p.recipient, p.feeBps);
    }

    function appendPolicy(address recipient_, uint16 feeBps_, uint64 activatesAt)
        external onlyAdmin {
        if (recipient_ == address(0) || feeBps_ > MAX_FEE_BPS || _policies.length >= MAX_EPOCHS) {
            revert InvalidConfiguration();
        }
        if (activatesAt < _policies[_policies.length - 1].activatesAt) {
            revert InvalidConfiguration();
        }
        _policies.push(Policy(activatesAt, recipient_, feeBps_));
        emit PolicyAppended(uint64(_policies.length), activatesAt, recipient_, feeBps_);
    }

    function recordFee(address asset, uint256 amount) external {
        if (msg.sender != hook) revert OnlyHook();
        if (asset == address(0) || amount == 0) revert InvalidConfiguration();
        uint256 outstanding = accrued[asset] - claimed[asset];
        if (_backedBalance(asset) < outstanding + amount) {
            revert InsufficientRecordedBalance();
        }
        (uint64 e, address recipient,) = currentPolicy();
        accrued[asset] += amount;
        claimable[recipient][asset] += amount;
        emit FeeRecorded(e, asset, amount, recipient);
    }

    function claim(address[] calldata assets) external returns (uint256 total) {
        if (assets.length == 0 || assets.length > 20) revert InvalidConfiguration();
        for (uint256 i; i < assets.length; ++i) {
            address asset = assets[i];
            if (asset == address(0)) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) if (assets[j] == asset) revert InvalidConfiguration();
            uint256 amount = claimable[msg.sender][asset];
            if (amount != 0) {
                claimable[msg.sender][asset] = 0;
                claimed[asset] += amount;
                _beforePayout(asset);
                IERC20(asset).safeTransfer(msg.sender, amount);
                emit FeeClaimed(msg.sender, asset, amount);
                total += amount;
            }
        }
        if (total == 0) revert NoClaim();
    }

    // Default behavior is unchanged. Only separately deployed credit-aware
    // successors override these hooks; no deployed vault is modified.
    function _backedBalance(address asset) internal view virtual returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
    function _beforePayout(address) internal virtual {}
}