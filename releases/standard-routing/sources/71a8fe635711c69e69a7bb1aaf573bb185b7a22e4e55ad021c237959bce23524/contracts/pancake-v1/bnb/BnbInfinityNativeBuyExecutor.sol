// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PancakeV1InfinitySwapAdapter} from "../PancakeV1InfinitySwapAdapter.sol";
import {IPancakeV1CLPoolManager, IPancakeV1Hooks, PancakeV1PoolKey, PancakeV1Currency} from "../PancakeV1InfinityHookTypes.sol";
import {IPancakeV1InfinityBuySource, IPancakeV1InfinityFeeView} from "../PancakeV1InfinityDeveloperBuyExecutor.sol";
import {V1PoolId} from "../PancakeV1Interfaces.sol";

interface IWBNB is IERC20 { function deposit() external payable; }
interface IBnbV3Router {
    struct ExactInputParams { bytes path; address recipient; uint256 deadline; uint256 amountIn; uint256 amountOutMinimum; }
    function exactInput(ExactInputParams calldata) external payable returns (uint256);
}
interface IBnbV3Factory { function getPool(address, address, uint24) external view returns (address); }

/// @notice Typed native BNB funding. No ETH/USDG intermediary, arbitrary router
/// calldata, or inferred route authority. Partial fills revert atomically.
contract BnbInfinityNativeBuyExecutor {
    using SafeERC20 for IERC20;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant V3_ROUTER = 0x1b81D678ffb9C0263b24A97847620C99d213eB14;
    address public constant V3_FACTORY = 0x0BFbCF9fa4f9C56B0F40a671Ad40E0805A091865;
    bytes32 public constant ROUTE_POLICY_ID = keccak256("pair-bnb-infinity-native-v1");
    address public immutable launchpad;
    address public immutable binder;
    address public engine;
    IPancakeV1CLPoolManager public immutable poolManager;
    IPancakeV1InfinityFeeView public immutable hook;
    PancakeV1InfinitySwapAdapter public immutable adapter;
    mapping(address => uint24) public routeFee;
    bool public routesFrozen;
    uint256 private entered;
    struct BuyPlan {
        uint8 version; address recipient; uint256 totalProjectMinimum;
        uint256[] projectMinimums; uint256[] quoteMinimums; uint256 deadline; bytes32 routePolicyId;
    }
    error InvalidBuy();
    error Residual();

    constructor(address launchpad_, IPancakeV1InfinityFeeView hook_, address expectedEngine) {
        if (block.chainid != 56 || launchpad_.code.length == 0 || address(hook_).code.length == 0)
            revert InvalidBuy();
        launchpad = launchpad_; binder = msg.sender; hook = hook_;
        engine = expectedEngine;
        poolManager = IPancakeV1CLPoolManager(0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b);
        adapter = new PancakeV1InfinitySwapAdapter(poolManager, IPancakeV1Hooks(address(hook_)));
    }
    /// Freeze only independently reviewed, liquid WBNB -> quote Pancake V3 pools.
    function bind(address engine_, address[] calldata quotes, uint24[] calldata fees) external {
        if (msg.sender != binder || routesFrozen || engine_.code.length == 0
            || (engine != address(0) && engine != engine_)
            || quotes.length != fees.length || quotes.length > 8) revert InvalidBuy();
        for (uint256 i; i < quotes.length; ++i) {
            if (quotes[i] == WBNB || quotes[i] == address(0) || routeFee[quotes[i]] != 0
                || fees[i] == 0 || IBnbV3Factory(V3_FACTORY).getPool(WBNB, quotes[i], fees[i]).code.length == 0)
                revert InvalidBuy();
            routeFee[quotes[i]] = fees[i];
        }
        engine = engine_; routesFrozen = true;
    }
    function execute(address project, address payer, uint256 launchDeadline, bytes calldata encoded)
        external payable returns (uint256 received) {
        BuyPlan memory p = abi.decode(encoded, (BuyPlan));
        if (msg.sender != engine || !routesFrozen || entered != 0 || msg.value == 0
            || project == address(0) || payer == address(0) || p.recipient != payer || p.version != 1
            || p.routePolicyId != ROUTE_POLICY_ID || p.totalProjectMinimum == 0
            || p.deadline < block.timestamp || p.deadline > launchDeadline
            || keccak256(encoded) != keccak256(abi.encode(p))) revert InvalidBuy();
        entered = 1;
        IPancakeV1InfinityBuySource.PoolRecord[] memory pools = IPancakeV1InfinityBuySource(launchpad).pools(project);
        if (pools.length == 0 || pools.length > 5 || p.projectMinimums.length != pools.length
            || p.quoteMinimums.length != pools.length) revert InvalidBuy();
        uint256 baseline = IERC20(WBNB).balanceOf(address(this));
        IWBNB(WBNB).deposit{value: msg.value}();
        if (IERC20(WBNB).balanceOf(address(this)) != baseline + msg.value) revert Residual();
        uint256 beforeOutput = IERC20(project).balanceOf(payer);
        uint256 allocated; uint256 weights;
        for (uint256 i; i < pools.length; ++i) {
            weights += pools[i].weightBps;
            uint256 leg = i + 1 == pools.length ? msg.value - allocated : msg.value * pools[i].weightBps / 10_000;
            allocated += leg;
            if (leg == 0 || pools[i].weightBps == 0 || p.projectMinimums[i] == 0 || p.quoteMinimums[i] == 0)
                revert InvalidBuy();
            uint256 gross = _fund(pools[i].quoteToken, leg, p.quoteMinimums[i], p.deadline);
            _buy(project, pools[i].quoteToken, gross, payer, p.projectMinimums[i], p.deadline,
                V1PoolId.unwrap(pools[i].poolId), i);
        }
        received = IERC20(project).balanceOf(payer) - beforeOutput;
        if (weights != 10_000 || allocated != msg.value || received < p.totalProjectMinimum
            || IERC20(WBNB).balanceOf(address(this)) != baseline) revert Residual();
        entered = 0;
    }
    function _fund(address quote, uint256 amount, uint256 floor, uint256 deadline) private returns (uint256 gross) {
        if (quote == WBNB) {
            if (amount < floor) revert InvalidBuy();
            return amount;
        }
        uint24 fee = routeFee[quote];
        if (fee == 0) revert InvalidBuy();
        uint256 beforeQuote = IERC20(quote).balanceOf(address(this));
        uint256 beforeWbnb = IERC20(WBNB).balanceOf(address(this));
        IERC20(WBNB).forceApprove(V3_ROUTER, amount);
        gross = IBnbV3Router(V3_ROUTER).exactInput(
            IBnbV3Router.ExactInputParams(abi.encodePacked(WBNB, fee, quote), address(this), deadline, amount, floor));
        IERC20(WBNB).forceApprove(V3_ROUTER, 0);
        if (gross < floor || IERC20(quote).balanceOf(address(this)) - beforeQuote != gross
            || beforeWbnb - IERC20(WBNB).balanceOf(address(this)) != amount
            || IERC20(WBNB).allowance(address(this), V3_ROUTER) != 0) revert Residual();
    }
    function _buy(address project, address quote, uint256 gross, address recipient,
        uint256 floor, uint256 deadline, bytes32 id, uint256 index) private {
        bool project0 = project < quote;
        PancakeV1PoolKey memory key = PancakeV1PoolKey(
            PancakeV1Currency.wrap(project0 ? project : quote), PancakeV1Currency.wrap(project0 ? quote : project),
            IPancakeV1Hooks(address(hook)), poolManager, 10_000,
            bytes32(uint256(hook.getHooksRegistrationBitmap()) | (uint256(200) << 16)));
        if (keccak256(abi.encode(key)) != id) revert InvalidBuy();
        uint256 net = gross;
        for (uint256 i; i < 256; ++i) {
            uint256 fee = hook.quoteInputFee(project, net);
            if (fee >= gross) revert InvalidBuy();
            uint256 next = gross - fee;
            if (next == net) break;
            net = next;
        }
        if (net + hook.quoteInputFee(project, net) != gross) revert InvalidBuy();
        uint256 beforeQuote = IERC20(quote).balanceOf(address(this));
        IERC20(quote).forceApprove(address(adapter), gross);
        adapter.executeExactInput(key, !project0, net, gross, floor, address(this), recipient, deadline,
            abi.encode(uint8(1), id, index));
        IERC20(quote).forceApprove(address(adapter), 0);
        if (beforeQuote - IERC20(quote).balanceOf(address(this)) != gross
            || IERC20(quote).allowance(address(this), address(adapter)) != 0) revert Residual();
    }
}
