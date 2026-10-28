// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PancakeV1InfinityLaunchFactory} from "./PancakeV1InfinityLaunchFactory.sol";
import {PancakeV1InfinityPoolBootstrapper} from "./PancakeV1InfinityPoolBootstrapper.sol";
import {PancakeV1FeeSharingVault} from "./PancakeV1FeeSharingVault.sol";
import {IPancakeV1Hooks, IPancakeV1CLPoolManager, PancakeV1PoolKey, PancakeV1Currency} from "./PancakeV1InfinityHookTypes.sol";

interface IPancakeV1InfinityLaunchpad {
    function launchFee() external view returns (uint256);
    function launchFeeRecipient() external view returns (address);
    function poolManager() external view returns (address);
    function positionManager() external view returns (address);
    function permit2() external view returns (address);
    function infinityApprove(address token, uint256 amount, uint256 deadline) external;
    function recordInfinityPool(address,address,bytes32,uint16) external;
    function modeVault(address project, uint8 mode, bytes calldata modeData, uint16 feeBps)
        external returns (address);
}
interface IPancakeV1Permit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IPancakeV1InfinityHookEngine {
    enum FeeMode { NONE, CREATOR_QUOTE, BURN_PROJECT, FEE_SHARING_QUOTE, HOLDER_QUOTE }
    function getHooksRegistrationBitmap() external view returns (uint16);
    function schedulePolicy(address, FeeMode, uint16, address, uint64) external returns (uint64);
    function registerPool(PancakeV1PoolKey calldata,address,address,uint160,bool) external;
    function poolManager() external view returns(address);
    function registrar() external view returns(address);
    function owner() external view returns(address);
    function frozen() external view returns(bool);
}
interface IPancakeV1InfinityDeveloperBuy {
    function launchpad() external view returns(address);
    function engine() external view returns(address);
    function poolManager() external view returns(address);
    function hook() external view returns(address);
    function execute(address project, address payer, uint256 launchDeadline, bytes calldata encodedPlan)
        external payable returns (uint256);
}

/// @notice Immutable ordinary-call orchestrator. It never owns launch tokens:
/// the launchpad proxy remains the ERC20 owner and approves Infinity Permit2
/// through its engine-only gateway for each mint.
contract PancakeV1InfinityLaunchEngine {
    using SafeERC20 for IERC20;
    address public immutable launchpad;
    PancakeV1InfinityLaunchFactory public immutable factory;
    PancakeV1InfinityPoolBootstrapper public immutable bootstrapper;
    IPancakeV1InfinityHookEngine public immutable hook;
    IPancakeV1InfinityDeveloperBuy public immutable developerBuyExecutor;

    struct Allocation { address quoteToken; uint16 weightBps; }
    struct Params {
        bytes identityData;
        Allocation[] allocations;
        bytes[] openingData;
        uint256 deadline;
        bytes32 userSalt;
        bool sniperProtection;
        uint256 protectionBlocks;
        IPancakeV1InfinityHookEngine.FeeMode mode;
        uint16 feeBps;
        bytes modeData;
        uint64 policyEffectiveAt;
        address[] holderExcluded;
    }
    struct Opening {
        uint8 decimals; uint160 opening; int24 lower; int24 upper; uint256 observed;
        bytes32 evidence; uint160 graduation; bool above;
    }

    error OnlyLaunchpad();
    error InvalidLaunch();
    error InvalidGraduation();
    error DeveloperBuyUnavailable();

    constructor(address launchpad_, PancakeV1InfinityLaunchFactory factory_,
        PancakeV1InfinityPoolBootstrapper bootstrapper_, IPancakeV1InfinityHookEngine hook_,
        IPancakeV1InfinityDeveloperBuy buyExecutor_) {
        if (launchpad_ == address(0) || address(factory_).code.length == 0
            || address(bootstrapper_).code.length == 0 || address(hook_).code.length == 0
            || address(buyExecutor_) == address(0)
            || factory_.tokenLaunchpad() != launchpad_
            || address(bootstrapper_.hook()) != address(hook_)
            || address(hook_.poolManager()) != address(IPancakeV1InfinityLaunchpad(launchpad_).poolManager())
            || buyExecutor_.launchpad() != launchpad_
            || (buyExecutor_.engine() != address(0) && buyExecutor_.engine() != address(this))
            || buyExecutor_.poolManager() != address(hook_.poolManager())
            || buyExecutor_.hook() != address(hook_)) revert InvalidLaunch();
        launchpad = launchpad_; factory = factory_; bootstrapper = bootstrapper_; hook = hook_;
        developerBuyExecutor = buyExecutor_;
    }

    /// @notice Reciprocal graph attestation used by the storage-safe
    /// launchpad successor initializer.
    function validateLaunchpad(address launchpad_) external view returns (bool) {
        return launchpad_ == launchpad && factory.validateGraph(launchpad_, address(this))
            && address(hook).code.length != 0 && hook.frozen()
            && hook.registrar() == address(this);
    }

    function launch(address creator, bytes calldata encoded) external payable returns (address token) {
        if (msg.sender != launchpad || creator == address(0)) revert OnlyLaunchpad();
        uint256 fee = IPancakeV1InfinityLaunchpad(launchpad).launchFee();
        if (msg.value != fee) revert InvalidLaunch();
        (token,) = _launch(creator, encoded, fee);
    }

    function launchAndBuy(address creator, bytes calldata encoded)
        external payable returns (address token, uint256 projectAmountOut) {
        if (msg.sender != launchpad || creator == address(0)
            || address(developerBuyExecutor) == address(0)) revert DeveloperBuyUnavailable();
        (bytes memory launchEncoded, bytes memory buyEncoded) = abi.decode(encoded, (bytes, bytes));
        if (launchEncoded.length == 0) {
            (token, buyEncoded) = abi.decode(buyEncoded, (address, bytes));
            projectAmountOut = developerBuyExecutor.execute{value: msg.value}(
                token, creator, block.timestamp + 30 minutes, buyEncoded);
            return (token, projectAmountOut);
        }
        uint256 fee = IPancakeV1InfinityLaunchpad(launchpad).launchFee();
        if (msg.value <= fee) revert InvalidLaunch();
        uint256 launchDeadline;
        (token, launchDeadline) = _launch(creator, launchEncoded, fee);
        projectAmountOut = developerBuyExecutor.execute{value: msg.value - fee}(
            token, creator, launchDeadline, buyEncoded);
    }

    function _launch(address creator, bytes memory encoded, uint256 fee)
        internal returns (address token, uint256 launchDeadline) {
        if (!factory.frozen() || !hook.frozen() || factory.engine() != address(this)
            || hook.registrar() != address(this)) revert InvalidLaunch();
        Params memory p = abi.decode(encoded, (Params));
        if (block.timestamp > p.deadline || p.allocations.length == 0
            || p.allocations.length > 5 || p.openingData.length != p.allocations.length) revert InvalidLaunch();
        launchDeadline = p.deadline;
        (string memory name, string memory symbol, string memory uri, bytes32 hash) =
            abi.decode(p.identityData, (string,string,string,bytes32));
        PancakeV1InfinityLaunchFactory.Identity memory identity =
            PancakeV1InfinityLaunchFactory.Identity(creator,name,symbol,uri,hash);
        uint256 protection = p.sniperProtection ? p.protectionBlocks : 0;
        if ((!p.sniperProtection && p.protectionBlocks != 0) || protection > 64) revert InvalidLaunch();
        address lock; address holderVault;
        if (p.mode == IPancakeV1InfinityHookEngine.FeeMode.HOLDER_QUOTE) {
            (token,lock,holderVault) = factory.deployHolder(identity,p.userSalt,protection,
                p.holderExcluded,_quotes(p.allocations));
            hook.schedulePolicy(token,p.mode,p.feeBps,holderVault,p.policyEffectiveAt);
        } else {
            (token,lock) = factory.deployStandard(identity,p.userSalt,protection);
            address destination;
            if (p.mode == IPancakeV1InfinityHookEngine.FeeMode.CREATOR_QUOTE
                || p.mode == IPancakeV1InfinityHookEngine.FeeMode.FEE_SHARING_QUOTE) {
                destination = _modeVault(token, p);
            } else if (p.mode == IPancakeV1InfinityHookEngine.FeeMode.NONE
                || p.mode == IPancakeV1InfinityHookEngine.FeeMode.BURN_PROJECT) {
                if (p.mode == IPancakeV1InfinityHookEngine.FeeMode.NONE && p.modeData.length != 0
                    || p.mode == IPancakeV1InfinityHookEngine.FeeMode.BURN_PROJECT && p.modeData.length != 0) revert InvalidLaunch();
                destination = p.mode == IPancakeV1InfinityHookEngine.FeeMode.BURN_PROJECT
                    ? address(0x000000000000000000000000000000000000dEaD) : address(0);
            } else revert InvalidLaunch();
            hook.schedulePolicy(token,p.mode,p.feeBps,destination,p.policyEffectiveAt);
        }
        uint256 totalWeight;
        uint256 allocated;
        for (uint256 i; i < p.allocations.length; ++i) {
            totalWeight += p.allocations[i].weightBps;
            if (i != 0 && p.allocations[i].quoteToken <= p.allocations[i-1].quoteToken) revert InvalidLaunch();
            Opening memory o = _opening(p.allocations[i],p.openingData[i]);
            uint256 amount = i + 1 == p.allocations.length ? 1_000_000_000 ether - allocated
                : uint256(1_000_000_000 ether) * uint256(p.allocations[i].weightBps) / 10_000;
            allocated += amount;
            IERC20(token).safeTransfer(address(bootstrapper), amount);
            (bytes32 pid,) = bootstrapper.initializePool(token,p.allocations[i].quoteToken,
                amount,p.deadline,lock,o.opening,o.lower,o.upper,hook.getHooksRegistrationBitmap());
            bool project0 = token < p.allocations[i].quoteToken;
            bytes32 parameters = bytes32(uint256(hook.getHooksRegistrationBitmap())
                | (uint256(uint24(uint24(200))) << 16));
            PancakeV1PoolKey memory key = PancakeV1PoolKey(
                PancakeV1Currency.wrap(project0 ? token : p.allocations[i].quoteToken),
                PancakeV1Currency.wrap(project0 ? p.allocations[i].quoteToken : token),
                IPancakeV1Hooks(address(hook)), IPancakeV1CLPoolManager(IPancakeV1InfinityLaunchpad(launchpad).poolManager()),
                10_000, parameters);
            bool above = token < p.allocations[i].quoteToken;
            if (o.above != above) revert InvalidGraduation();
            hook.registerPool(key,token,p.allocations[i].quoteToken,o.graduation,above);
            IPancakeV1InfinityLaunchpad(launchpad).recordInfinityPool(token,p.allocations[i].quoteToken,
                pid,p.allocations[i].weightBps);
        }
        if (totalWeight != 10_000) revert InvalidLaunch();
        (bool ok,) = payable(IPancakeV1InfinityLaunchpad(launchpad).launchFeeRecipient()).call{value: fee}("");
        if (!ok) revert InvalidLaunch();
    }

    function _opening(Allocation memory a, bytes memory data) private view returns (Opening memory o) {
        (o.decimals,o.opening,o.lower,o.upper,o.observed,o.evidence,o.graduation,o.above) =
            abi.decode(data,(uint8,uint160,int24,int24,uint256,bytes32,uint160,bool));
        uint8 d = IERC20Metadata(a.quoteToken).decimals();
        if (d != o.decimals || o.observed > block.timestamp || block.timestamp-o.observed > 30 minutes
            || o.opening < TickMath.MIN_SQRT_PRICE || o.opening >= TickMath.MAX_SQRT_PRICE
            || o.graduation < TickMath.MIN_SQRT_PRICE || o.graduation >= TickMath.MAX_SQRT_PRICE
            || o.lower >= o.upper || o.lower % 200 != 0 || o.upper % 200 != 0) revert InvalidLaunch();
        uint160 lo=TickMath.getSqrtPriceAtTick(o.lower); uint160 hi=TickMath.getSqrtPriceAtTick(o.upper);
        if (o.opening != lo && o.opening != hi
            || (o.above ? o.graduation <= o.opening : o.graduation >= o.opening)) revert InvalidGraduation();
    }

    function _quotes(Allocation[] memory a) private pure returns (address[] memory q) {
        q = new address[](a.length);
        for (uint256 i; i < a.length; ++i) q[i] = a[i].quoteToken;
    }

    function _modeVault(address token, Params memory p) private returns (address destination) {
        if (p.mode == IPancakeV1InfinityHookEngine.FeeMode.CREATOR_QUOTE) {
            (address recipient) = abi.decode(p.modeData, (address));
            destination = factory.deployCreatorVault(token, recipient, p.feeBps);
        } else {
            (PancakeV1FeeSharingVault.Recipient[] memory recipients, address verifier) =
                abi.decode(p.modeData, (PancakeV1FeeSharingVault.Recipient[], address));
            destination = factory.deploySharingVault(token, recipients, verifier, p.feeBps);
        }
    }
}