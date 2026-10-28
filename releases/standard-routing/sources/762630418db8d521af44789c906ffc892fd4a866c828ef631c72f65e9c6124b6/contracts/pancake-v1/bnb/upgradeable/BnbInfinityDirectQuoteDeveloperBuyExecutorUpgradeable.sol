// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbInfinityFundingMath} from "./BnbInfinityFundingMath.sol";
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    V1PoolId
} from "../../PancakeV1Interfaces.sol";
import {
    PancakeV1PoolKey, PancakeV1Currency, IPancakeV1Hooks,
    IPancakeV1CLPoolManager
} from "../../PancakeV1InfinityHookTypes.sol";
interface IPancakeV1DirectBuyPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
interface IPancakeV1DirectBuyRouter {
    struct PoolKey { address currency0; address currency1; address hooks; address poolManager; uint24 fee; bytes32 parameters; }
    struct SwapParams { PoolKey poolKey; bool zeroForOne; uint128 amountIn; uint128 amountOutMinimum; bytes hookData; }
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline) external payable;
}

interface IPancakeV1DirectBuyAdapter {
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
    ) external returns (uint256 amountOut);
}

interface IPancakeV1DirectBuySource {
    struct PoolRecord {
        address quoteToken; uint16 weightBps; V1PoolId poolId; uint256 positionId;
        uint256 projectAmount; int24 tickLower; int24 tickUpper; uint256 quotePriceE8; uint8 quoteDecimals;
    }
    function pools(address) external view returns (PoolRecord[] memory);
}

interface IPancakeV1DirectBuyHook {
    function quoteInputFee(address project, uint256 amount) external view returns (uint256);
    function getHooksRegistrationBitmap() external view returns (uint16);
}
interface IPancakeV1DirectBuyLaunchpad {
    function launchInfinityFor(address creator, bytes calldata encoded)
        external payable returns (address);
    function poolManager() external view returns (address);
}

/// @notice Versioned, all-direct quote-token developer buys for Infinity V1.
/// @dev The existing exact-ETH executor is intentionally not changed. This
/// executor is only callable by the active launchpad proxy and only consumes
/// quote tokens declared by the creator in a typed plan.
contract BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable  is BnbPlatformUUPS {
    using SafeERC20 for IERC20;

    uint24 private constant POOL_FEE = 10_000;
    int24 private constant TICK_SPACING = 200;
    uint8 public constant BUY_PLAN_VERSION = 1;
    uint8 public constant HOOK_DATA_VERSION = 1;
    bytes32 public constant ROUTE_POLICY_ID =
        keccak256("pancake-v1-infinity-direct-quote-v1");

    address public  launchpad;
    IPancakeV1CLPoolManager public  poolManager;
    IPancakeV1DirectBuyHook public  hook;
    IPancakeV1DirectBuyAdapter public  adapter;
    IPancakeV1DirectBuyPermit2 public  permit2;
    uint256 private _status;

    struct BuyPlan {
        uint8 version;
        address recipient;
        uint256 totalProjectMinimum;
        uint256[] projectMinimums;
        uint256[] quoteAmounts;
        uint256 deadline;
        bytes32 routePolicyId;
    }
    struct HookData { uint8 version; bytes32 poolId; uint256 legIndex; }
    struct Leg {
        address project;
        address payer;
        address quote;
        uint256 amount;
        address recipient;
        uint256 minimum;
        uint256 deadline;
        V1PoolId poolId;
        uint256 legIndex;
    }

    error OnlyLaunchpad();
    error InvalidBuy();
    error PoolBindingMismatch(bytes32 storedPoolId, bytes32 computedPoolId);
    error Slippage();
    error Residual(address token);
    error RefundFailed();

    function initializeProxy(address upgradeAuthority, 
        address launchpad_,
        IPancakeV1CLPoolManager manager_,
        IPancakeV1DirectBuyHook hook_,
        IPancakeV1DirectBuyAdapter adapter_,
        IPancakeV1DirectBuyPermit2 permit2_
    ) external initializer {
        _initializeDirectQuote(upgradeAuthority, launchpad_, manager_, hook_, adapter_, permit2_);
    }
    function _initializeDirectQuote(address upgradeAuthority, address launchpad_,
        IPancakeV1CLPoolManager manager_,
        IPancakeV1DirectBuyHook hook_,
        IPancakeV1DirectBuyAdapter adapter_,
        IPancakeV1DirectBuyPermit2 permit2_
    ) internal onlyInitializing {
        _initializePlatform(upgradeAuthority);


        if (launchpad_ == address(0) || address(manager_) == address(0)
            || address(manager_).code.length == 0 || address(hook_).code.length == 0
            || address(manager_.vault()).code.length == 0 || address(adapter_).code.length == 0
            || address(permit2_).code.length == 0) revert InvalidBuy();
        launchpad = launchpad_;
        poolManager = manager_;
        hook = hook_;
        adapter = adapter_;
        permit2 = permit2_;
    
    
    }

    function routePolicyId() external pure returns (bytes32) { return ROUTE_POLICY_ID; }

    function execute(
        address project,
        address payer,
        bytes calldata encodedPlan
    ) external payable {
        if ((msg.sender != launchpad && msg.sender != address(this))
            || project == address(0) || payer == address(0)
            || msg.value != 0) revert OnlyLaunchpad();
        BuyPlan memory buy = abi.decode(encodedPlan, (BuyPlan));
        if (buy.version != BUY_PLAN_VERSION || buy.recipient == address(0)
            || buy.totalProjectMinimum == 0 || buy.routePolicyId != ROUTE_POLICY_ID
            || buy.projectMinimums.length == 0 || buy.projectMinimums.length > 5
            || buy.projectMinimums.length != buy.quoteAmounts.length
            || buy.deadline < block.timestamp || buy.deadline > type(uint48).max) {
            revert InvalidBuy();
        }
        if (_status != 0) revert InvalidBuy();
        _status = 1;

        IPancakeV1DirectBuySource.PoolRecord[] memory pools =
            IPancakeV1DirectBuySource(launchpad).pools(project);
        if (pools.length == 0 || pools.length > 5
            || pools.length != buy.projectMinimums.length) revert InvalidBuy();

        uint256 received = _executeLegs(project, payer, buy, pools);
        if (received < buy.totalProjectMinimum) revert Slippage();
        if (IERC20(project).balanceOf(address(this)) != 0) revert Residual(project);
        _status = 0;
    }

    /// @notice Atomic direct-quote launch followed by the typed buy plan.
    /// @dev The creator approves this coordinator, never the launchpad proxy.
    function launchAndBuy(bytes calldata launchData, bytes calldata encodedPlan)
        external payable virtual returns (address project) {
        project = IPancakeV1DirectBuyLaunchpad(launchpad).launchInfinityFor{value: msg.value}(
            msg.sender, launchData
        );
        this.execute(project, msg.sender, encodedPlan);
    }

    function _executeLegs(
        address project,
        address payer,
        BuyPlan memory buy,
        IPancakeV1DirectBuySource.PoolRecord[] memory pools
    ) private returns (uint256 received) {
        uint256 beforeOut = IERC20(project).balanceOf(buy.recipient);
        uint256 weightTotal;
        for (uint256 i; i < pools.length; ++i) {
            weightTotal += pools[i].weightBps;
            _executeLeg(project, payer, buy, pools[i], i);
        }
        if (weightTotal != 10_000) revert InvalidBuy();
        received = IERC20(project).balanceOf(buy.recipient) - beforeOut;
    }

    function _executeLeg(
        address project,
        address payer,
        BuyPlan memory buy,
        IPancakeV1DirectBuySource.PoolRecord memory pool,
        uint256 legIndex
    ) private {
        uint256 amount = buy.quoteAmounts[legIndex];
        if (pool.weightBps == 0 || amount == 0 || buy.projectMinimums[legIndex] == 0
            || V1PoolId.unwrap(pool.poolId) == bytes32(0)) revert InvalidBuy();
        PancakeV1PoolKey memory key = _key(project, pool.quoteToken);
        bytes32 computedPoolId = keccak256(abi.encode(key));
        if (computedPoolId != V1PoolId.unwrap(pool.poolId)) {
            revert PoolBindingMismatch(V1PoolId.unwrap(pool.poolId), computedPoolId);
        }
        _buyLeg(Leg(
            project, payer, pool.quoteToken, amount, buy.recipient,
            buy.projectMinimums[legIndex], buy.deadline, pool.poolId, legIndex
        ));
    }

    function _buyLeg(Leg memory leg) internal virtual {
        address project = leg.project;
        address payer = leg.payer;
        address quote = leg.quote;
        uint256 amount = leg.amount;
        address recipient = leg.recipient;
        uint256 minimum = leg.minimum;
        uint256 deadline = leg.deadline;
        V1PoolId poolId = leg.poolId;
        uint256 legIndex = leg.legIndex;
        if (amount > type(uint128).max || minimum > type(uint128).max
            || deadline > type(uint48).max
            || IERC20(quote).balanceOf(address(this)) != 0) revert InvalidBuy();
        uint256 payerBefore = IERC20(quote).balanceOf(payer);
        IERC20(quote).safeTransferFrom(payer, address(this), amount);
        if (IERC20(quote).balanceOf(address(this)) != amount
            || payerBefore < IERC20(quote).balanceOf(payer)
            || payerBefore - IERC20(quote).balanceOf(payer) != amount) {
            revert Residual(quote);
        }
        (uint256 debit, uint256 funded) = BnbInfinityFundingMath.resolve(amount, address(hook), project);
        if (funded < amount) IERC20(quote).safeTransfer(payer, amount - funded);
        IERC20(quote).forceApprove(address(adapter), funded);
        PancakeV1PoolKey memory key = _key(project, quote);
        uint256 beforeOut = IERC20(project).balanceOf(recipient);
        uint256 beforeExecutorOut = IERC20(project).balanceOf(address(this));
        IPancakeV1DirectBuyAdapter(adapter).executeExactInput(
            key, project >= quote, debit, funded, minimum, address(this), recipient, deadline,
            abi.encode(HookData(HOOK_DATA_VERSION, V1PoolId.unwrap(poolId), legIndex)
        ));
        uint256 executorOut = IERC20(project).balanceOf(address(this)) - beforeExecutorOut;
        if (executorOut != 0) IERC20(project).safeTransfer(recipient, executorOut);
        if (IERC20(project).balanceOf(address(this)) < beforeExecutorOut
            || IERC20(project).balanceOf(address(this)) - beforeExecutorOut != 0
            || IERC20(project).balanceOf(recipient) - beforeOut < minimum) revert Slippage();
        uint256 afterQuote = IERC20(quote).balanceOf(address(this));
        if (afterQuote != 0 || IERC20(quote).allowance(address(this), address(adapter)) != 0) {
            revert Residual(quote);
        }
    }

    function _key(address project, address quote) internal view returns (PancakeV1PoolKey memory) {
        bool projectIs0 = project < quote;
        return PancakeV1PoolKey(
            PancakeV1Currency.wrap(projectIs0 ? project : quote),
            PancakeV1Currency.wrap(projectIs0 ? quote : project),
            IPancakeV1Hooks(address(hook)), poolManager, POOL_FEE,
            bytes32(uint256(hook.getHooksRegistrationBitmap())
                | (uint256(uint24(uint24(TICK_SPACING))) << 16))
        );
    }

    receive() external payable { revert InvalidBuy(); }
}