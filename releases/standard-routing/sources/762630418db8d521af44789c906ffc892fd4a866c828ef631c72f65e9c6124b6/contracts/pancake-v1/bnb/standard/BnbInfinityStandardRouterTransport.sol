// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BnbPlatformUUPS} from "../upgradeable/BnbPlatformUUPS.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPancakeV1CLPoolManager, IPancakeV1Hooks, PancakeV1PoolKey, PancakeV1Currency}
    from "../../PancakeV1InfinityHookTypes.sol";

interface IStandardPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
interface IStandardUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

/// @notice Optional PAIR funding transport, not a custom Infinity settlement
/// adapter. Swaps execute through PancakeSwap's official Universal Router.
/// The immutable hooks also admit the router/quoter directly without this helper.
contract BnbInfinityStandardRouterTransport is BnbPlatformUUPS {
    using SafeERC20 for IERC20;
    address public constant ROUTER = 0xd9C500DfF816a1Da21A48A732d3498Bf09dc9AEB;
    address public constant PERMIT2 = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;
    IPancakeV1CLPoolManager public poolManager;
    IPancakeV1Hooks public hook;
    address public vault;
    bool private entered;
    error InvalidSwap();
    error Residual();
    struct Swap {
        PancakeV1PoolKey poolKey;
        bool zeroForOne;
        uint128 amount;
        uint128 limit;
        bytes hookData;
    }

    function initializeProxy(address authority, IPancakeV1CLPoolManager manager, IPancakeV1Hooks hook_)
        external initializer {
        _initializePlatform(authority);
        if (block.chainid != 56 || address(manager) != 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b
            || address(hook_).code.length == 0 || ROUTER.code.length == 0 || PERMIT2.code.length == 0)
            revert InvalidSwap();
        poolManager = manager;
        hook = hook_;
        vault = address(manager.vault());
    }

    function standardRoutingVersion() external pure returns (uint8) { return 1; }

    function executeExactInput(PancakeV1PoolKey calldata key, bool zeroForOne, uint256 amountIn,
        uint256 inputMaximum, uint256 minimum, address payer, address recipient, uint256 deadline,
        bytes calldata hookData) external returns (uint256 amountOut) {
        if (entered || payer != msg.sender || recipient == address(0) || recipient == address(this)
            || amountIn == 0 || inputMaximum != amountIn || amountIn > type(uint128).max
            || minimum > type(uint128).max || deadline < block.timestamp || deadline > type(uint48).max
            || address(key.hooks) != address(hook) || address(key.poolManager) != address(poolManager)
            || key.fee != 10_000 || PancakeV1Currency.unwrap(key.currency0) == address(0)
            || PancakeV1Currency.unwrap(key.currency1) == address(0)) revert InvalidSwap();
        entered = true;
        address input = PancakeV1Currency.unwrap(zeroForOne ? key.currency0 : key.currency1);
        address output = PancakeV1Currency.unwrap(zeroForOne ? key.currency1 : key.currency0);
        uint256 beforeIn = IERC20(input).balanceOf(address(this));
        uint256 beforeOut = IERC20(output).balanceOf(address(this));
        uint256 beforeRecipient = IERC20(output).balanceOf(recipient);
        uint256 beforePayer = IERC20(input).balanceOf(payer);
        IERC20(input).safeTransferFrom(payer, address(this), amountIn);
        if (IERC20(input).balanceOf(address(this)) != beforeIn + amountIn
            || beforePayer - IERC20(input).balanceOf(payer) != amountIn) revert Residual();
        IERC20(input).forceApprove(PERMIT2, amountIn);
        IStandardPermit2(PERMIT2).approve(input, ROUTER, uint160(amountIn), uint48(deadline));
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(Swap(key, zeroForOne, uint128(amountIn), uint128(minimum), hookData));
        params[1] = abi.encode(input, amountIn);
        params[2] = abi.encode(output, minimum);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(hex"060c0f", params);
        IStandardUniversalRouter(ROUTER).execute(hex"10", inputs, deadline);
        IStandardPermit2(PERMIT2).approve(input, ROUTER, 0, 0);
        IERC20(input).forceApprove(PERMIT2, 0);
        amountOut = IERC20(output).balanceOf(address(this)) - beforeOut;
        if (amountOut < minimum || IERC20(input).balanceOf(address(this)) != beforeIn
            || IERC20(input).allowance(address(this), PERMIT2) != 0) revert Residual();
        IERC20(output).safeTransfer(recipient, amountOut);
        if (IERC20(output).balanceOf(address(this)) != beforeOut
            || IERC20(output).balanceOf(recipient) - beforeRecipient != amountOut) revert Residual();
        entered = false;
    }
}
