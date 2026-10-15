// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PancakeV1Currency, PancakeV1BeforeSwapDelta, PancakeV1BalanceDelta,
    PancakeV1PoolKey, IPancakeV1Hooks, IPancakeV1CLPoolManager, IPancakeV1FeeReceiver,
    PancakeV1BalanceDeltaLib, PancakeV1BeforeSwapDeltaLib} from "./PancakeV1InfinityHookTypes.sol";
import {IPancakeV1FeeSettler} from "./PancakeV1InfinityHook.sol";
interface INFTGraph {
    function hook() external view returns (address);
    function factory() external view returns (address);
    function engine() external view returns (address);
    function verifyVault(address,uint8,address) external view returns (bool);
}
interface INFTActive { function rewardsActive() external view returns (bool); }

/// @notice New immutable hook; no policy changes, ownership transfer or legacy modes.
contract PancakeV1NFTHook is IPancakeV1Hooks {
    using PancakeV1BalanceDeltaLib for PancakeV1BalanceDelta;
    uint16 public constant HOOK_BITMAP = (1 << 6) | (1 << 7) | (1 << 10) | (1 << 11);
    uint16 public constant PROTOCOL_FEE_BPS = 30;
    uint8 public constant NFT_QUOTE = 5;
    address public immutable owner;
    IPancakeV1CLPoolManager public immutable poolManager;
    address public immutable protocolVault;
    address public registrar;
    address public attestor;
    bool public frozen;
    bool public adaptersAttested;
    mapping(address => bool) public trustedAdapter;
    event AdapterAttested(address indexed adapter,bytes32 runtimeHash);
    struct Policy { uint8 mode; uint16 feeBps; address destination; uint64 effectiveAt; }
    struct Pool { address project; address quote; uint160 graduationSqrtPriceX96; bool graduateWhenAbove; bool registered; }
    struct Pending { address project; address quote; address destination; uint256 protocolFee; uint256 modeFee; }
    mapping(address => Policy) private _policies;
    mapping(bytes32 => Pool) public pools;
    mapping(address => bool) public graduated;
    mapping(address => Pending) private _pending;
    error InvalidConfiguration();
    error Unauthorized();
    event PoolRegistered(bytes32 indexed poolId,address indexed project,address indexed quote,uint160 graduationSqrtPriceX96,bool graduateWhenAbove);
    event PolicyScheduled(address indexed project,uint64 indexed epoch,uint8 mode,uint16 feeBps,address destination,uint64 effectiveAt);
    event TokenGraduated(address indexed project,bytes32 indexed poolId,uint160 sqrtPriceX96);
    event ProtocolFeeAccrued(address indexed quote,address indexed destination,uint256 amount);
    event ModeFeeAccrued(address indexed project,address indexed asset,address indexed destination,uint256 amount);

    constructor(IPancakeV1CLPoolManager manager_,address protocol_) {
        if (address(manager_).code.length == 0 || protocol_.code.length == 0
            || manager_.vault().code.length == 0) revert InvalidConfiguration();
        owner = msg.sender; poolManager = manager_; protocolVault = protocol_;
    }
    function finalizeRelease(address engine_,address factory_) external {
        if (msg.sender != owner || frozen || !adaptersAttested) revert Unauthorized();
        if (INFTGraph(engine_).hook() != address(this) || INFTGraph(engine_).factory() != factory_
            || INFTGraph(factory_).hook() != address(this) || INFTGraph(factory_).engine() != engine_)
            revert InvalidConfiguration();
        if (INFTGraph(protocolVault).hook() != address(this)) revert InvalidConfiguration();
        registrar = engine_; attestor = factory_; frozen = true;
    }
    /// @notice Deployment-manifest attestation, deliberately NOT derived from
    /// untrusted sender getters. The deployer must verify these exact runtimes
    /// and constructor bindings before this irreversible authorization.
    function attestAdapters(address[] calldata adapters) external {
        if (msg.sender != owner || frozen || adaptersAttested || adapters.length == 0 || adapters.length > 5)
            revert Unauthorized();
        adaptersAttested = true;
        for (uint256 i; i < adapters.length; ++i) {
            address adapter = adapters[i];
            if (adapter.code.length == 0 || trustedAdapter[adapter]) revert InvalidConfiguration();
            trustedAdapter[adapter] = true;
            emit AdapterAttested(adapter,adapter.codehash);
        }
    }
    function getHooksRegistrationBitmap() external pure returns(uint16) { return HOOK_BITMAP; }
    function schedulePolicy(address project,uint8 mode,uint16 fee,address destination,uint64 effectiveAt)
        external returns(uint64) {
        if (!frozen || msg.sender != registrar) revert Unauthorized();
        if (mode != NFT_QUOTE || _policies[project].destination != address(0) || effectiveAt != 0
            || fee < 100 || fee > 1000 || fee % 100 != 0
            || !INFTGraph(attestor).verifyVault(project,mode,destination)) revert InvalidConfiguration();
        _policies[project] = Policy(mode,fee,destination,uint64(block.timestamp));
        emit PolicyScheduled(project,1,mode,fee,destination,uint64(block.timestamp));
        return 1;
    }
    function activePolicy(address project) public view returns(Policy memory) { return _policies[project]; }
    function effectiveFeeBps(address project) public view returns(uint16) {
        Policy memory p = _policies[project];
        if (p.destination == address(0)) revert InvalidConfiguration();
        return INFTActive(p.destination).rewardsActive() ? p.feeBps : 0;
    }
    function quoteInputFee(address project,uint256 amount) external view returns(uint256) {
        return amount * 30 / 10000 + amount * effectiveFeeBps(project) / 10000;
    }
    function poolId(PancakeV1PoolKey calldata key) public pure returns(bytes32) { return keccak256(abi.encode(key)); }
    function registerPool(PancakeV1PoolKey calldata key,address project,address quote,uint160 threshold,bool above) external {
        if (!frozen || msg.sender != registrar) revert Unauthorized();
        address c0 = PancakeV1Currency.unwrap(key.currency0);
        address c1 = PancakeV1Currency.unwrap(key.currency1);
        bytes32 id = poolId(key);
        if (pools[id].registered || _policies[project].destination == address(0) || threshold == 0
            || project == quote || project == address(0) || quote == address(0)
            || address(key.hooks) != address(this) || address(key.poolManager) != address(poolManager)
            || c0 >= c1 || !((c0 == project && c1 == quote) || (c1 == project && c0 == quote)))
            revert InvalidConfiguration();
        pools[id] = Pool(project,quote,threshold,above,true);
        emit PoolRegistered(id,project,quote,threshold,above);
    }
    function beforeSwap(address sender,PancakeV1PoolKey calldata key,IPancakeV1CLPoolManager.SwapParams calldata,bytes calldata)
        external view returns(bytes4,PancakeV1BeforeSwapDelta,uint24) {
        if (msg.sender != address(poolManager) || !frozen || !trustedAdapter[sender]) revert Unauthorized();
        Pool memory p = pools[poolId(key)];
        if (!p.registered) revert InvalidConfiguration();
        effectiveFeeBps(p.project); // Also blocks trades inside NFT receiver callbacks.
        return (this.beforeSwap.selector,PancakeV1BeforeSwapDeltaLib.toDelta(0,0),0);
    }
    function afterSwap(address sender,PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params,PancakeV1BalanceDelta delta,bytes calldata)
        external returns(bytes4,int128) {
        if (msg.sender != address(poolManager) || !frozen || !trustedAdapter[sender]) revert Unauthorized();
        bytes32 id = poolId(key);
        Pool memory p = pools[id];
        if (!p.registered || sender.code.length == 0) revert InvalidConfiguration();
        if (!graduated[p.project]) {
            (uint160 price,,,) = poolManager.getSlot0(id);
            if (p.graduateWhenAbove ? price >= p.graduationSqrtPriceX96 : price <= p.graduationSqrtPriceX96) {
                graduated[p.project] = true;
                emit TokenGraduated(p.project,id,price);
            }
        }
        bool exactInput = params.amountSpecified < 0;
        bool quote0 = PancakeV1Currency.unwrap(key.currency0) == p.quote;
        bool quoteInput = params.zeroForOne == quote0;
        bool specified = quoteInput == exactInput;
        uint256 amount;
        if (specified) {
            amount = uint256(exactInput ? -params.amountSpecified : params.amountSpecified);
        } else {
            int256 q = quote0 ? int256(delta.amount0()) : int256(delta.amount1());
            amount = uint256(q < 0 ? -q : q);
        }
        Pending memory fees = Pending(p.project,p.quote,_policies[p.project].destination,
            amount * 30 / 10000,amount * effectiveFeeBps(p.project) / 10000);
        if (_pending[sender].project != address(0)) revert InvalidConfiguration();
        if (specified) _settle(sender,fees);
        else if (fees.protocolFee != 0 || fees.modeFee != 0) _pending[sender] = fees;
        return (this.afterSwap.selector,0);
    }
    function settleUnspecifiedFee() external {
        if (!trustedAdapter[msg.sender]) revert Unauthorized();
        Pending memory p = _pending[msg.sender];
        if (p.project == address(0)) return;
        delete _pending[msg.sender];
        _settle(msg.sender,p);
    }
    function _settle(address sender,Pending memory p) private {
        if (p.protocolFee != 0) {
            uint256 beforeBalance = IERC20(p.quote).balanceOf(protocolVault);
            IPancakeV1FeeSettler(sender).settleHookFee(p.quote,protocolVault,p.protocolFee);
            if (IERC20(p.quote).balanceOf(protocolVault) != beforeBalance + p.protocolFee)
                revert InvalidConfiguration();
            IPancakeV1FeeReceiver(protocolVault).recordFee(p.quote,p.protocolFee);
            emit ProtocolFeeAccrued(p.quote,protocolVault,p.protocolFee);
        }
        if (p.modeFee != 0) {
            uint256 beforeBalance = IERC20(p.quote).balanceOf(p.destination);
            IPancakeV1FeeSettler(sender).settleHookFee(p.quote,p.destination,p.modeFee);
            if (IERC20(p.quote).balanceOf(p.destination) != beforeBalance + p.modeFee)
                revert InvalidConfiguration();
            IPancakeV1FeeReceiver(p.destination).recordFee(p.quote,p.modeFee);
            emit ModeFeeAccrued(p.project,p.quote,p.destination,p.modeFee);
        }
    }
}