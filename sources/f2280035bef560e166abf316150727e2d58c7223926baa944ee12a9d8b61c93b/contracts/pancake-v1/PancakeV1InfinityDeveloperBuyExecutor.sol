// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PairV5LaunchV2DeveloperBuyRoutePolicy as Routes} from "../v5/PairV5LaunchV2DeveloperBuyRoutePolicy.sol";
import {
    V1PoolKey, V1PoolId, V1Currency, IV1Hooks, IV1PoolManager, IV1Permit2
} from "./PancakeV1Interfaces.sol";
import {
    PancakeV1PoolKey, PancakeV1Currency, IPancakeV1Hooks,
    IPancakeV1CLPoolManager
} from "./PancakeV1InfinityHookTypes.sol";
import {PancakeV1InfinitySwapAdapter} from "./PancakeV1InfinitySwapAdapter.sol";

interface IPancakeV1InfinityWETH is IERC20 { function deposit() external payable; function withdraw(uint256) external; }
interface IPancakeV1InfinitySwapRouter {
    struct ExactInputParams { bytes path; address recipient; uint256 amountIn; uint256 amountOutMinimum; }
    function exactInput(ExactInputParams calldata) external returns (uint256);
}
interface IPancakeV1InfinityUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}
interface IPancakeV1InfinityPermit2Allowance {
    function allowance(address owner, address token, address spender)
        external view returns (uint160 amount, uint48 expiration, uint48 nonce);
}
interface IPancakeV1InfinityBuySource {
    struct PoolRecord {
        address quoteToken; uint16 weightBps; V1PoolId poolId; uint256 positionId;
        uint256 projectAmount; int24 tickLower; int24 tickUpper; uint256 quotePriceE8; uint8 quoteDecimals;
    }
    function pools(address) external view returns (PoolRecord[] memory);
}
interface IPancakeV1InfinityFeeView {
    function quoteInputFee(address project, uint256 amount) external view returns (uint256);
    function getHooksRegistrationBitmap() external view returns (uint16);
}

/// @notice Typed, hook-bound exact-ETH developer-buy executor for Infinity V1.
/// @dev This is deliberately separate from the historical no-hook executor.
contract PancakeV1InfinityDeveloperBuyExecutor {
    using SafeERC20 for IERC20;

    uint256 private constant BPS = 10_000;
    uint24 private constant POOL_FEE = 10_000;
    int24 private constant TICK_SPACING = 200;
    uint8 public constant BUY_PLAN_VERSION = 1;
    uint8 public constant HOOK_DATA_VERSION = 1;
    bytes32 public constant ROUTE_POLICY_ID = keccak256("pancake-v1-infinity-funding-v1");

    address public immutable launchpad;
    address public engine;
    IV1PoolManager public immutable poolManager;
    IPancakeV1InfinityUniversalRouter public immutable universalRouter;
    IV1Permit2 public immutable permit2;
    address public immutable swapRouter02;
    address public immutable weth;
    address public immutable usdg;
    IPancakeV1InfinityFeeView public immutable hook;
    PancakeV1InfinitySwapAdapter public immutable adapter;
    address public immutable binder;
    bool public engineBound;

    address private constant CANONICAL_WETH = 0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73;
    address private constant CANONICAL_MANAGER = 0xeE04c68742e6Bf434bE8039580D2e89BBE55bc6f;
    address private constant CANONICAL_ROUTER = 0x57fc55F719DF19B4b90A03F9D78E1177D002E504;
    address private constant CANONICAL_PERMIT2 = 0x31c2F6fcFf4F8759b3Bd5Bf0e1084A055615c768;
    address private constant CANONICAL_SWAP = 0xCaf681a66D020601342297493863E78C959E5cb2;
    address private constant CANONICAL_USDG = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    uint256 private _status;

    struct BuyPlan {
        uint8 version;
        address recipient;
        uint256 totalProjectMinimum;
        uint256[] projectMinimums;
        uint256[] quoteMinimums;
        uint256 deadline;
        bytes32 routePolicyId;
    }
    struct HookData { uint8 version; bytes32 poolId; uint256 legIndex; }

    error OnlyEngine();
    error InvalidBuy();
    error UnsupportedRoute(address);
    error Slippage();
    error Residual(address);
    error RefundFailed();

    constructor(
        address launchpad_, address engine_, IV1PoolManager manager_,
        IPancakeV1InfinityUniversalRouter router_, IV1Permit2 permit2_,
        address swapRouter_, address weth_, address usdg_, IPancakeV1InfinityFeeView hook_
    ) {
        if (launchpad_ == address(0) || address(manager_) != CANONICAL_MANAGER
            || address(router_) != CANONICAL_ROUTER || address(permit2_) != CANONICAL_PERMIT2
            || swapRouter_ != CANONICAL_SWAP || weth_ != CANONICAL_WETH || usdg_ != CANONICAL_USDG
            || address(hook_) == address(0) || address(manager_).code.length == 0
            || address(router_).code.length == 0 || address(permit2_).code.length == 0
            || swapRouter_.code.length == 0 || weth_ == usdg_) revert InvalidBuy();
        launchpad = launchpad_; engine = engine_; binder = msg.sender; engineBound = engine_ != address(0);
        poolManager = manager_; universalRouter = router_;
        permit2 = permit2_; swapRouter02 = swapRouter_; weth = weth_; usdg = usdg_; hook = hook_;
        adapter = new PancakeV1InfinitySwapAdapter(
            IPancakeV1CLPoolManager(address(manager_)), IPancakeV1Hooks(address(hook_))
        );
    }

    function bindEngine(address engine_) external {
        if (msg.sender != binder || engineBound || engine_ == address(0)) revert InvalidBuy();
        engine = engine_;
        engineBound = true;
    }

    function routePolicyId() external pure returns (bytes32) { return ROUTE_POLICY_ID; }

    function execute(address project, address payer, uint256 launchDeadline, bytes calldata encodedPlan)
        external payable returns (uint256 received)
    {
        if (!engineBound || msg.sender != engine) revert OnlyEngine();
        BuyPlan memory buy = abi.decode(encodedPlan, (BuyPlan));
        uint256 ethAmount = msg.value;
        if (project == address(0) || payer == address(0) || buy.version != BUY_PLAN_VERSION
            || buy.recipient == address(0) || ethAmount == 0 || buy.totalProjectMinimum == 0
            || buy.routePolicyId != ROUTE_POLICY_ID || buy.projectMinimums.length == 0
            || buy.projectMinimums.length > 5 || buy.projectMinimums.length != buy.quoteMinimums.length
            || buy.deadline < block.timestamp || buy.deadline > type(uint48).max
            || launchDeadline > type(uint48).max || buy.deadline > launchDeadline) revert InvalidBuy();
        if (_status != 0) revert InvalidBuy();
        _status = 1;
        IPancakeV1InfinityBuySource.PoolRecord[] memory pools =
            IPancakeV1InfinityBuySource(launchpad).pools(project);
        if (pools.length == 0 || pools.length > 5 || pools.length != buy.projectMinimums.length) revert InvalidBuy();
        IPancakeV1InfinityWETH wrapped = IPancakeV1InfinityWETH(weth);
        uint256 openingWeth = wrapped.balanceOf(address(this));
        // The launch ETH is converted exactly once, before any leg starts.
        // Keep prefunded WETH outside the refundable accounting baseline.
        wrapped.deposit{value: ethAmount}();
        uint256 fundedWeth = openingWeth + ethAmount;
        if (wrapped.balanceOf(address(this)) != fundedWeth) revert Residual(weth);
        uint256 beforeOut = IERC20(project).balanceOf(buy.recipient);
        uint256 allocated;
        uint256 weightTotal;
        for (uint256 i; i < pools.length; ++i) {
            if (pools[i].weightBps == 0 || buy.projectMinimums[i] == 0 || buy.quoteMinimums[i] == 0) {
                revert InvalidBuy();
            }
            weightTotal += pools[i].weightBps;
            uint256 leg = i + 1 == pools.length ? ethAmount - allocated : ethAmount * pools[i].weightBps / BPS;
            if (leg == 0 || V1PoolId.unwrap(pools[i].poolId) == bytes32(0)) revert InvalidBuy();
            allocated += leg;
            PancakeV1PoolKey memory key = _key(project, pools[i].quoteToken);
            if (keccak256(abi.encode(key)) != V1PoolId.unwrap(pools[i].poolId)) revert InvalidBuy();
            uint256 grossQuote = pools[i].quoteToken == weth
                ? leg
                : _convert(pools[i].quoteToken, leg, buy.quoteMinimums[i]);
            // A negative specified before-swap delta is an additional debit
            // from the specified input.  The amount available from this leg
            // is therefore the gross quote amount, while the CL swap's
            // amountSpecified must be net of the fee.  This is especially
            // important for converted (non-WETH) quotes: converting only the
            // net amount leaves the hook fee unfunded, while specifying the
            // gross amount asks the pool to debit gross + fee.
            _swap(project, pools[i].quoteToken, grossQuote, grossQuote, buy.recipient,
                buy.projectMinimums[i], buy.deadline, pools[i].poolId, i);
        }
        if (weightTotal != BPS || allocated != ethAmount) revert InvalidBuy();
        received = IERC20(project).balanceOf(buy.recipient) - beforeOut;
        if (received < buy.totalProjectMinimum) revert Slippage();
        uint256 closingWeth = wrapped.balanceOf(address(this));
        if (closingWeth < openingWeth) revert Residual(weth);
        if (closingWeth != openingWeth) {
            uint256 refund = closingWeth - openingWeth;
            wrapped.withdraw(refund);
            (bool ok,) = payable(payer).call{value: refund}("");
            if (!ok) revert RefundFailed();
            if (wrapped.balanceOf(address(this)) != openingWeth) revert Residual(weth);
        }
        _status = 0;
    }

    function _convert(address quote, uint256 amount, uint256 minimum) private returns (uint256 result) {
        (uint8 kind, uint24 wethFee, uint24 quoteFee) = Routes.route(quote);
        if (kind == 0 || amount == 0) revert UnsupportedRoute(quote);
        bytes memory path = kind == Routes.DIRECT
            ? abi.encodePacked(weth, wethFee, quote)
            : abi.encodePacked(weth, wethFee, usdg, quoteFee, quote);
        uint256 beforeQuote = IERC20(quote).balanceOf(address(this));
        IERC20(weth).forceApprove(swapRouter02, amount);
        result = IPancakeV1InfinitySwapRouter(swapRouter02).exactInput(
            IPancakeV1InfinitySwapRouter.ExactInputParams(path, address(this), amount, minimum));
        IERC20(weth).forceApprove(swapRouter02, 0);
        uint256 afterQuote = IERC20(quote).balanceOf(address(this));
        if (result == 0 || afterQuote < beforeQuote || afterQuote - beforeQuote != result || result < minimum) {
            revert Slippage();
        }
        if (IERC20(weth).allowance(address(this), swapRouter02) != 0) revert Residual(weth);
    }

    function _swap(address project, address quote, uint256 amount, uint256 gross,
        address recipient, uint256 minimum,
        uint256 deadline, V1PoolId poolId, uint256 legIndex) private {
        if (amount > type(uint128).max || minimum > type(uint128).max || deadline > type(uint48).max) {
            revert InvalidBuy();
        }
        PancakeV1PoolKey memory key = _key(project, quote);
        uint256 beforeOut = IERC20(project).balanceOf(recipient);
        uint256 beforeExecutorOut = IERC20(project).balanceOf(address(this));
        uint256 beforeQuote = IERC20(quote).balanceOf(address(this));
        // quoteInputFee is defined over the specified (net) exact-input
        // amount. Solve net + fee(net) == gross; the fee is floored in the
        // hook. The bounded loop handles both the protocol fee and a possible
        // quote-denominated policy fee without rounding a unit into residue.
        uint256 debit = amount;
        for (uint256 i; i < 256; ++i) {
            uint256 hookFee = hook.quoteInputFee(project, debit);
            if (hookFee >= gross) revert InvalidBuy();
            uint256 next = gross - hookFee;
            if (next == debit) break;
            debit = next;
        }
        uint256 hookFeeFinal = hook.quoteInputFee(project, debit);
        if (hookFeeFinal >= gross || debit + hookFeeFinal != gross) revert InvalidBuy();
        if (debit > type(uint160).max || gross > type(uint160).max) revert InvalidBuy();
        IERC20(quote).forceApprove(address(adapter), gross);
        HookData memory typedHookData = HookData(HOOK_DATA_VERSION, V1PoolId.unwrap(poolId), legIndex);
        bool projectIs0 = project < quote;
        adapter.executeExactInput(
            key, !projectIs0, debit, gross, minimum, address(this), recipient, deadline,
            abi.encode(typedHookData)
        );
        IERC20(quote).forceApprove(address(adapter), 0);
        uint256 executorOut = IERC20(project).balanceOf(address(this)) - beforeExecutorOut;
        if (executorOut != 0) IERC20(project).safeTransfer(recipient, executorOut);
        if (IERC20(project).balanceOf(recipient) - beforeOut < minimum) revert Slippage();
        uint256 afterQuote = IERC20(quote).balanceOf(address(this));
        if (afterQuote > beforeQuote || beforeQuote - afterQuote != gross) revert Residual(quote);
        uint256 principalConsumed = beforeQuote - afterQuote;
        if (principalConsumed != gross) revert Residual(quote);
        if (IERC20(quote).allowance(address(this), address(adapter)) != 0) revert Residual(quote);
    }

    function _key(address project, address quote) private view returns (PancakeV1PoolKey memory) {
        bool projectIs0 = project < quote;
        uint16 bitmap = hook.getHooksRegistrationBitmap();
        return PancakeV1PoolKey(
            PancakeV1Currency.wrap(projectIs0 ? project : quote),
            PancakeV1Currency.wrap(projectIs0 ? quote : project),
            IPancakeV1Hooks(address(hook)), IPancakeV1CLPoolManager(address(poolManager)), POOL_FEE,
            bytes32(uint256(bitmap) | (uint256(uint24(uint24(TICK_SPACING))) << 16))
        );
    }

    receive() external payable { if (msg.sender != weth) revert InvalidBuy(); }
}