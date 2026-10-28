// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    PancakeV1Currency,
    PancakeV1PoolKey,
    IPancakeV1CLPoolManager,
    IPancakeV1Hooks,
    IPancakeV1Vault,
    IPancakeV1LockCallback
} from "../../PancakeV1InfinityHookTypes.sol";

interface IPancakeV1PostSwapFeeHook {
    function settleUnspecifiedFee() external;
}

/// @notice Direct Pancake Infinity CL settlement adapter.
/// @dev The public Universal Router does not safely settle a positive
/// beforeSwap specified delta on the deployed Infinity Vault. This adapter
/// performs the canonical Vault.lock -> CLPoolManager.swap flow and clears
/// both the caller and hook deltas before the lock returns.
contract BnbInfinitySwapAdapterUpgradeable is IPancakeV1LockCallback , BnbPlatformUUPS {
    using SafeERC20 for IERC20;

    uint24 public constant MAX_HOOK_FEE_BPS = 30;
    uint160 private constant MIN_SQRT_PRICE = 4295128740;
    uint160 private constant MAX_SQRT_PRICE =
        1461446703485210103287273052203988822378723970341;
    uint256 private _entered;

    IPancakeV1CLPoolManager public  poolManager;
    IPancakeV1Vault public  vault;
    IPancakeV1Hooks public  hook;

    error InvalidRoute();
    error OnlyVault();
    error OnlyHook();
    error Reentered();
    error DeadlineExpired();
    error Slippage();
    error Residual(address token);
    error Unsettled();

    struct SwapRequest {
        PancakeV1PoolKey key;
        IPancakeV1CLPoolManager.SwapParams params;
        bytes hookData;
        address payer;
        address recipient;
        uint256 maxInput;
        uint256 deadline;
    }

    function initializeProxy(address upgradeAuthority, IPancakeV1CLPoolManager manager_, IPancakeV1Hooks hook_) external initializer {
_initializePlatform(upgradeAuthority);

        address vault_ = manager_.vault();
        if (address(manager_) == address(0) || vault_ == address(0)
            || address(manager_).code.length == 0 || vault_.code.length == 0
            || address(hook_) == address(0) || address(hook_).code.length == 0) {
            revert InvalidRoute();
        }
        poolManager = manager_;
        vault = IPancakeV1Vault(vault_);
        hook = hook_;
    
    }

    function executeExactInput(
        PancakeV1PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 inputMaximum,
        uint256 amountOutMinimum,
        address payer,
        address recipient,
        uint256 deadline,
        bytes calldata hookData
    ) external returns (uint256 amountOut) {
        if (amountIn == 0 || inputMaximum < amountIn) revert InvalidRoute();
        amountOut = _execute(key, zeroForOne, -int256(amountIn), amountOutMinimum,
            inputMaximum, payer, recipient, deadline, hookData);
    }

    function executeExactOutput(
        PancakeV1PoolKey calldata key,
        bool zeroForOne,
        uint256 amountOut,
        uint256 amountInMaximum,
        address payer,
        address recipient,
        uint256 deadline,
        bytes calldata hookData
    ) external returns (uint256 amountIn) {
        if (amountOut == 0) revert InvalidRoute();
        amountIn = _execute(key, zeroForOne, int256(amountOut), amountInMaximum,
            amountInMaximum, payer, recipient, deadline, hookData);
    }

    function lockAcquired(bytes calldata raw) external returns (bytes memory) {
        if (msg.sender != address(vault)) revert OnlyVault();
        SwapRequest memory request = abi.decode(raw, (SwapRequest));
        PancakeV1Currency input = request.params.zeroForOne
            ? request.key.currency0 : request.key.currency1;
        PancakeV1Currency output = request.params.zeroForOne
            ? request.key.currency1 : request.key.currency0;
        // Fund gross input before the swap. The pool consumes the net specified
        // amount and the hook settles fees from the adapter's remaining input
        // or output credit without creating hook-owned deltas.
        vault.sync(input);
        IERC20(PancakeV1Currency.unwrap(input)).safeTransfer(address(vault), request.maxInput);
        if (vault.settleFor(address(this)) != request.maxInput) revert Unsettled();
        poolManager.swap(request.key, request.params, request.hookData);
        IPancakeV1PostSwapFeeHook(address(hook)).settleUnspecifiedFee();
        // Unspent input belongs to the payer, not the output recipient.
        // Executors must observe this refund to reject partial-fill launches.
        _settle(address(this), input, request.payer);
        _settle(address(this), output, request.recipient);
        if (vault.getUnsettledDeltasCount() != 0) revert Unsettled();
        return "";
    }

    function settleHookFee(address asset, address destination, uint256 amount) external {
        if (msg.sender != address(hook)) revert OnlyHook();
        if (_entered != 1 || asset == address(0) || destination == address(0) || amount == 0) {
            revert InvalidRoute();
        }
        PancakeV1Currency currency = PancakeV1Currency.wrap(asset);
        int256 credit = vault.currencyDelta(address(this), currency);
        if (credit < 0 || uint256(credit) < amount) revert Unsettled();
        vault.take(currency, destination, amount);
    }

    function _execute(
        PancakeV1PoolKey calldata key,
        bool zeroForOne,
        int256 amountSpecified,
        uint256 amountLimit,
        uint256 maxInput,
        address payer,
        address recipient,
        uint256 deadline,
        bytes calldata hookData
    ) private returns (uint256 result) {
        if (_entered != 0) revert Reentered();
        if (block.timestamp > deadline || payer == address(0) || recipient == address(0)
            || address(key.poolManager) != address(poolManager)
            || address(key.hooks) != address(hook)
            || PancakeV1Currency.unwrap(key.currency0) >= PancakeV1Currency.unwrap(key.currency1)
            || key.fee > 30_000) revert InvalidRoute();
        _entered = 1;
        PancakeV1Currency input = zeroForOne ? key.currency0 : key.currency1;
        address inputToken = PancakeV1Currency.unwrap(input);
        uint256 beforeBalance = IERC20(inputToken).balanceOf(address(this));
        if (beforeBalance != 0) revert Residual(inputToken);
        IERC20(inputToken).safeTransferFrom(payer, address(this), maxInput);
        if (IERC20(inputToken).balanceOf(address(this)) != maxInput) revert InvalidRoute();
        address outputToken = PancakeV1Currency.unwrap(zeroForOne ? key.currency1 : key.currency0);
        uint256 beforeOut = IERC20(outputToken).balanceOf(recipient);
        SwapRequest memory request = SwapRequest(
            key,
            IPancakeV1CLPoolManager.SwapParams(
                zeroForOne, amountSpecified, zeroForOne ? MIN_SQRT_PRICE : MAX_SQRT_PRICE
            ),
            hookData, payer, recipient, maxInput, deadline
        );
        vault.lock(abi.encode(request));
        uint256 afterBalance = IERC20(inputToken).balanceOf(address(this));
        if (afterBalance > 0) {
            IERC20(inputToken).safeTransfer(payer, afterBalance);
        }
        if (IERC20(inputToken).balanceOf(address(this)) != 0) revert Residual(inputToken);
        if (amountSpecified < 0) {
            uint256 afterOut = IERC20(outputToken).balanceOf(recipient);
            if (afterOut < beforeOut || afterOut - beforeOut < amountLimit) revert Slippage();
            result = afterOut - beforeOut;
        } else {
            uint256 afterOut = IERC20(outputToken).balanceOf(recipient);
            if (afterOut < beforeOut || afterOut - beforeOut < uint256(amountSpecified)) revert Slippage();
            result = maxInput - afterBalance;
            if (result > amountLimit) revert Slippage();
        }
        _entered = 0;
    }

    function _settle(address settler, PancakeV1Currency currency, address recipient) private {
        int256 delta = vault.currencyDelta(settler, currency);
        address token = PancakeV1Currency.unwrap(currency);
        if (delta < 0) {
            uint256 amount = uint256(-delta);
            vault.sync(currency);
            IERC20(token).safeTransfer(address(vault), amount);
            vault.settleFor(settler);
        } else if (delta > 0) {
            vault.take(currency, settler == address(this) ? recipient : settler, uint256(delta));
        }
    }

    receive() external payable {
        revert InvalidRoute();
    }
}