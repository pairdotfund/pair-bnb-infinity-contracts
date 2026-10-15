// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PancakeV1NFTProxyFactory} from "./PancakeV1NFTProxyFactory.sol";
import {PancakeV1InfinityPoolBootstrapper} from "./PancakeV1InfinityPoolBootstrapper.sol";
import {PancakeV1PoolKey, PancakeV1Currency, IPancakeV1Hooks, IPancakeV1CLPoolManager} from "./PancakeV1InfinityHookTypes.sol";

interface IIntegratedNftHook {
    function poolManager() external view returns (address);
    function frozen() external view returns (bool);
    function registrar() external view returns (address);
    function attestor() external view returns (address);
    function getHooksRegistrationBitmap() external view returns (uint16);
    function schedulePolicy(address, uint8, uint16, address, uint64) external returns (uint64);
    function registerPool(PancakeV1PoolKey calldata, address, address, uint160, bool) external;
    function poolId(PancakeV1PoolKey calldata) external pure returns (bytes32);
}

interface IIntegratedNftBuy {
    function launchpad() external view returns (address);
    function engine() external view returns (address);
    function hook() external view returns (address);
    function poolManager() external view returns (address);
    function execute(address, address, uint256, bytes calldata) external payable returns (uint256);
}
interface IIntegratedNftTokenBinding {
    function launchpad() external view returns (address);
    function poolManager() external view returns (address);
}
interface IIntegratedNftCollectionBinding {
    function projectToken() external view returns (address);
    function hook() external view returns (address);
}

interface IIntegratedNftProxy {
    function launchFee() external view returns (uint256);
    function launchFeeRecipient() external view returns (address);
    function recordInfinityNftPool(address, address, bytes32, uint16,
        uint256, uint256, int24, int24, uint256, uint8) external;
    function releaseInfinityNftSupply(address) external;
}

/// @notice Only the existing Infinity proxy may invoke the separate NFT engine.
/// Historical mode engines, hooks and PoolIds are not replaced.
contract PancakeV1InfinityNftLaunchModule is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Allocation { address quoteToken; uint16 weightBps; }
    struct Params {
        bytes identityData; Allocation[] allocations; bytes[] openingData; uint256 deadline;
        bytes32 userSalt; bool sniperProtection; uint256 protectionBlocks; uint8 mode;
        uint16 feeBps; bytes modeData; uint64 policyEffectiveAt; address[] holderExcluded;
    }
    struct Opening {
        uint8 decimals; uint160 opening; int24 lower; int24 upper; uint256 observed;
        bytes32 evidence; uint160 graduation; bool above;
    }
    struct RegisteredPool {
        address quote; bytes32 id; uint16 weight; uint256 positionId;
        uint256 projectAmount; int24 lower; int24 upper; uint256 quotePriceE8; uint8 quoteDecimals;
    }

    address public immutable launchpad;
    PancakeV1NFTProxyFactory public immutable factory;
    IIntegratedNftHook public immutable hook;
    PancakeV1InfinityPoolBootstrapper public immutable bootstrapper;
    IIntegratedNftBuy public immutable developerBuyExecutor;
    mapping(address => RegisteredPool[]) private _registeredPools;
    error InvalidLaunch();
    event NFTProjectLaunched(address indexed projectToken, address indexed creator, address indexed collection);

    constructor(address proxy_, PancakeV1NFTProxyFactory factory_, IIntegratedNftHook hook_,
        PancakeV1InfinityPoolBootstrapper bootstrapper_, IIntegratedNftBuy executor_) {
        if (proxy_.code.length == 0 || address(factory_).code.length == 0
            || address(hook_).code.length == 0 || address(bootstrapper_).code.length == 0
            || factory_.hook() != address(hook_) || address(bootstrapper_.hook()) != address(hook_)
            || address(bootstrapper_.manager()) != hook_.poolManager()
            || executor_.launchpad() != proxy_ || executor_.engine() != address(this)
            || executor_.hook() != address(hook_)
            || executor_.poolManager() != hook_.poolManager()
            || factory_.creationDeployers().tokenLaunchpad() != proxy_)
            revert InvalidLaunch();
        launchpad = proxy_;
        factory = factory_;
        hook = hook_;
        bootstrapper = bootstrapper_;
        developerBuyExecutor = executor_;
    }

    function validatePool(address project, address quote, bytes32 id, uint16 weight,
        uint256 positionId, uint256 projectAmount, int24 lower, int24 upper,
        uint256 quotePriceE8, uint8 quoteDecimals) external view returns (bool)
    {
        if (msg.sender != launchpad || factory.collectionOf(project) == address(0)) return false;
        RegisteredPool[] storage records = _registeredPools[project];
        for (uint256 i; i < records.length; ++i)
            if (records[i].quote == quote && records[i].id == id
                && records[i].weight == weight && records[i].positionId == positionId
                && records[i].projectAmount == projectAmount && records[i].lower == lower
                && records[i].upper == upper && records[i].quotePriceE8 == quotePriceE8
                && records[i].quoteDecimals == quoteDecimals)
                return true;
        return false;
    }

    function validateSupply(address project) external view returns (bool) {
        if (msg.sender != launchpad || project.code.length == 0) return false;
        address collection = factory.collectionOf(project);
        return collection.code.length != 0
            && factory.creationDeployers().tokenLaunchpad() == launchpad
            && IIntegratedNftCollectionBinding(collection).projectToken() == project
            && IIntegratedNftCollectionBinding(collection).hook() == address(hook)
            && IIntegratedNftTokenBinding(project).launchpad() == launchpad
            // The token's poolManager is the CL manager's *vault* (its
            // transfer-gated settlement address), as wired by the existing
            // creation deployer. It is not the CL manager contract itself.
            && IIntegratedNftTokenBinding(project).poolManager() == factory.creationDeployers().vault();
    }

    function launch(address creator, bytes calldata encoded)
        external payable nonReentrant returns (address token)
    {
        if (msg.sender != launchpad || creator == address(0)
            || msg.value != IIntegratedNftProxy(launchpad).launchFee()) revert InvalidLaunch();
        token = _launch(creator, encoded);
    }

    function launchAndBuy(address creator, bytes calldata encoded)
        external payable nonReentrant returns (address token, uint256 output)
    {
        if (msg.sender != launchpad || creator == address(0)
            || msg.value <= IIntegratedNftProxy(launchpad).launchFee()) revert InvalidLaunch();
        (bytes memory launchData, bytes memory buyPlan) = abi.decode(encoded, (bytes, bytes));
        if (launchData.length == 0) revert InvalidLaunch();
        Params memory p = abi.decode(launchData, (Params));
        token = _launch(creator, launchData);
        output = developerBuyExecutor.execute{
            value: msg.value - IIntegratedNftProxy(launchpad).launchFee()
        }(token, creator, p.deadline, buyPlan);
    }

    function _launch(address creator, bytes memory encoded) private returns (address token) {
        if (!hook.frozen() || hook.registrar() != address(this)
            || hook.attestor() != address(factory) || factory.engine() != address(this))
            revert InvalidLaunch();
        Params memory p = abi.decode(encoded, (Params));
        // ABI decoders accept trailing garbage and overlapping offsets. NFT
        // launches require the precise canonical tuple, not a parser prefix.
        if (keccak256(encoded) != keccak256(abi.encode(p))) revert InvalidLaunch();
        if (p.mode != 5 || p.feeBps < 100 || p.feeBps > 1000 || p.feeBps % 100 != 0
            || p.policyEffectiveAt != 0 || p.holderExcluded.length != 0
            || p.sniperProtection || p.protectionBlocks != 0 || p.deadline < block.timestamp
            || p.deadline > type(uint48).max || p.allocations.length == 0
            || p.allocations.length > 5 || p.openingData.length != p.allocations.length)
            revert InvalidLaunch();
        (string memory name, string memory symbol, string memory uri, bytes32 hash) =
            abi.decode(p.identityData, (string, string, string, bytes32));
        address[] memory quotes = new address[](p.allocations.length);
        uint256 totalWeight;
        for (uint256 i; i < quotes.length; ++i) {
            quotes[i] = p.allocations[i].quoteToken;
            if (p.allocations[i].weightBps == 0 || (i != 0 && quotes[i] <= quotes[i - 1]))
                revert InvalidLaunch();
            totalWeight += p.allocations[i].weightBps;
        }
        if (totalWeight != 10000) revert InvalidLaunch();
        address lock;
        address collection;
        (token, lock, collection) = factory.deploy(
            PancakeV1NFTProxyFactory.Identity(creator, name, symbol, uri, hash),
            p.userSalt, p.modeData, quotes
        );
        hook.schedulePolicy(token, 5, p.feeBps, collection, 0);
        IIntegratedNftProxy(launchpad).releaseInfinityNftSupply(token);
        uint256 allocated;
        for (uint256 i; i < quotes.length; ++i) {
            Opening memory o = abi.decode(p.openingData[i], (Opening));
            bool project0 = token < quotes[i];
            if (o.decimals != IERC20Metadata(quotes[i]).decimals()
                || o.observed > block.timestamp || block.timestamp - o.observed > 30 minutes
                || o.lower >= o.upper || o.lower % 200 != 0 || o.upper % 200 != 0
                || o.lower < TickMath.MIN_TICK || o.upper > TickMath.MAX_TICK
                || o.above != project0
                || o.graduation < TickMath.MIN_SQRT_PRICE || o.graduation >= TickMath.MAX_SQRT_PRICE
                || (project0 ? o.graduation <= o.opening : o.graduation >= o.opening)
                || o.opening != TickMath.getSqrtPriceAtTick(project0 ? o.lower : o.upper))
                revert InvalidLaunch();
            uint256 amount = i + 1 == quotes.length ? 1_000_000_000 ether - allocated
                : uint256(1_000_000_000 ether) * p.allocations[i].weightBps / 10000;
            allocated += amount;
            IERC20(token).safeTransfer(address(bootstrapper), amount);
            (bytes32 id, uint256 positionId) = bootstrapper.initializePool(
                token, quotes[i], amount, p.deadline, lock,
                o.opening, o.lower, o.upper, hook.getHooksRegistrationBitmap()
            );
            PancakeV1PoolKey memory key = PancakeV1PoolKey(
                PancakeV1Currency.wrap(project0 ? token : quotes[i]),
                PancakeV1Currency.wrap(project0 ? quotes[i] : token),
                IPancakeV1Hooks(address(hook)), IPancakeV1CLPoolManager(hook.poolManager()),
                10000, bytes32(uint256(hook.getHooksRegistrationBitmap()) | (uint256(200) << 16))
            );
            if (hook.poolId(key) != id) revert InvalidLaunch();
            hook.registerPool(key, token, quotes[i], o.graduation, o.above);
            _registeredPools[token].push(RegisteredPool(quotes[i], id, p.allocations[i].weightBps,
                positionId, amount, o.lower, o.upper, 0, o.decimals));
            IIntegratedNftProxy(launchpad).recordInfinityNftPool(
                token, quotes[i], id, p.allocations[i].weightBps,
                positionId, amount, o.lower, o.upper, 0, o.decimals
            );
        }
        uint256 residue = IERC20(token).balanceOf(address(this));
        if (residue != 0)
            IERC20(token).safeTransfer(0x000000000000000000000000000000000000dEaD, residue);
        (bool ok,) = payable(IIntegratedNftProxy(launchpad).launchFeeRecipient()).call{
            value: IIntegratedNftProxy(launchpad).launchFee()
        }("");
        if (!ok) revert InvalidLaunch();
        emit NFTProjectLaunched(token, creator, collection);
    }
}