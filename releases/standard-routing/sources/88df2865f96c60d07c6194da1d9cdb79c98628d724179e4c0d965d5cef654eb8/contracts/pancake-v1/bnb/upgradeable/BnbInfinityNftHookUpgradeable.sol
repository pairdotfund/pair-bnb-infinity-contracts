// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ERC1967Utils as BnbERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IBnbUpgradeableAdapter} from "./BnbInfinityGuardedHookUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PancakeV1Currency, PancakeV1BeforeSwapDelta, PancakeV1BalanceDelta,
    PancakeV1PoolKey, IPancakeV1Hooks, IPancakeV1CLPoolManager, IPancakeV1FeeReceiver,
    PancakeV1BalanceDeltaLib, PancakeV1BeforeSwapDeltaLib} from "../../PancakeV1InfinityHookTypes.sol";
import {IPancakeV1FeeSettler} from "../../PancakeV1InfinityHook.sol";

interface INFTUpgradeableGraph {
    function hook() external view returns (address);
    function factory() external view returns (address);
    function engine() external view returns (address);
    function verifyVault(address, uint8, address) external view returns (bool);
}
interface INFTUpgradeableActive { function rewardsActive() external view returns (bool); }
interface INFTSharedProtocolVault {
    function additionalHook(address) external view returns (bool);
    function recordFeeFromAdditionalHook(address, uint256) external;
}

/// @notice Stable-address UUPS hook for new NFT pools; old Infinity pools never use this hook.
/// @dev The proxy must be initialized atomically. Upgrade authority can alter financial
/// behavior; it must be governed and independently audited before live use.
contract BnbInfinityNftHookUpgradeable is Initializable, OwnableUpgradeable, UUPSUpgradeable, IPancakeV1Hooks {
    using PancakeV1BalanceDeltaLib for PancakeV1BalanceDelta;

    uint16 public constant HOOK_BITMAP = (1 << 6) | (1 << 7) | (1 << 10) | (1 << 11);
    uint16 public constant PROTOCOL_FEE_BPS = 30;
    uint8 public constant NFT_QUOTE = 5;

    struct Policy { uint8 mode; uint16 feeBps; address destination; uint64 effectiveAt; }
    struct Pool { address project; address quote; uint160 graduationSqrtPriceX96; bool graduateWhenAbove; bool registered; }
    struct Pending { address project; address quote; address destination; uint256 protocolFee; uint256 modeFee; }
    /// @custom:storage-location erc7201:pair.infinity.nft.hook.storage
    struct Layout {
        IPancakeV1CLPoolManager poolManager;
        address protocolVault;
        address registrar;
        address attestor;
        bool frozen;
        bool adaptersAttested;
        mapping(address => bool) trustedAdapter;
        mapping(address => Policy) policies;
        mapping(bytes32 => Pool) pools;
        mapping(address => bool) graduated;
        mapping(address => Pending) pending;
        mapping(address => bytes32) adapterHash;
        mapping(address => bytes32) adapterImplementationHash;
    }
    // ERC-7201-style isolated storage; existing upgrades must retain this slot and layout.
    bytes32 private constant STORAGE_SLOT =
        bytes32(uint256(keccak256(abi.encode(uint256(keccak256("pair.infinity.nft.hook.storage")) - 1))) & ~uint256(0xff));
    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly { s.slot := slot }
    }

    error InvalidConfiguration();
    error Unauthorized();
    event AdapterAttested(address indexed adapter, bytes32 runtimeHash);
    event PoolRegistered(bytes32 indexed poolId,address indexed project,address indexed quote,uint160 graduationSqrtPriceX96,bool graduateWhenAbove);
    event PolicyScheduled(address indexed project,uint64 indexed epoch,uint8 mode,uint16 feeBps,address destination,uint64 effectiveAt);
    event TokenGraduated(address indexed project,bytes32 indexed poolId,uint160 sqrtPriceX96);
    event ProtocolFeeAccrued(address indexed quote,address indexed destination,uint256 amount);
    event ModeFeeAccrued(address indexed project,address indexed asset,address indexed destination,uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address owner_, IPancakeV1CLPoolManager manager_, address protocol_) external initializer {
        require(block.chainid == 56 && address(manager_) == 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b, "WRONG_BNB_MANAGER");
        if (owner_ == address(0) || address(manager_).code.length == 0
            || protocol_.code.length == 0 || manager_.vault().code.length == 0) revert InvalidConfiguration();
        __Ownable_init(owner_);
        Layout storage s = _layout();
        s.poolManager = manager_;
        s.protocolVault = protocol_;
    }
    function _authorizeUpgrade(address) internal override onlyOwner {}
    function poolManager() external view returns (IPancakeV1CLPoolManager) { return _layout().poolManager; }
    function protocolVault() external view returns (address) { return _layout().protocolVault; }
    function registrar() external view returns (address) { return _layout().registrar; }
    function attestor() external view returns (address) { return _layout().attestor; }
    function frozen() external view returns (bool) { return _layout().frozen; }
    function adaptersAttested() external view returns (bool) { return _layout().adaptersAttested; }
    function trustedAdapter(address a) external view returns (bool) { return _layout().trustedAdapter[a]; }
    function pools(bytes32 id) external view returns (Pool memory) { return _layout().pools[id]; }
    function graduated(address project) external view returns (bool) { return _layout().graduated[project]; }
    function getHooksRegistrationBitmap() external pure returns(uint16) { return HOOK_BITMAP; }

    function finalizeRelease(address engine_,address factory_) external onlyOwner {
        Layout storage s = _layout();
        if (s.frozen || !s.adaptersAttested) revert Unauthorized();
        if (engine_.code.length == 0 || factory_.code.length == 0
            || INFTUpgradeableGraph(engine_).hook() != address(this)
            || INFTUpgradeableGraph(engine_).factory() != factory_
            || INFTUpgradeableGraph(factory_).hook() != address(this)
            || INFTUpgradeableGraph(factory_).engine() != engine_
            || !INFTSharedProtocolVault(s.protocolVault).additionalHook(address(this)))
            revert InvalidConfiguration();
        s.registrar = engine_;
        s.attestor = factory_;
        s.frozen = true;
    }
    /// @notice Once-only attestation of reviewed adapters, including their actual code hashes.
    function attestAdapters(address[] calldata adapters) external onlyOwner {
        Layout storage s = _layout();
        if (s.frozen || s.adaptersAttested || adapters.length == 0 || adapters.length > 5)
            revert Unauthorized();
        s.adaptersAttested = true;
        for (uint256 i; i < adapters.length; ++i) {
            address adapter = adapters[i];
            if (adapter.code.length == 0 || s.trustedAdapter[adapter]) revert InvalidConfiguration();
            s.trustedAdapter[adapter] = true;
            s.adapterHash[adapter] = adapter.codehash;
            _pinImplementation(adapter);
            emit AdapterAttested(adapter, adapter.codehash);
        }
    }
    function schedulePolicy(address project,uint8 mode,uint16 fee,address destination,uint64 effectiveAt)
        external returns(uint64) {
        Layout storage s = _layout();
        if (!s.frozen || msg.sender != s.registrar) revert Unauthorized();
        if (mode != NFT_QUOTE || s.policies[project].destination != address(0) || effectiveAt != 0
            || fee < 100 || fee > 1000 || fee % 100 != 0 || destination.code.length == 0
            || !INFTUpgradeableGraph(s.attestor).verifyVault(project, mode, destination))
            revert InvalidConfiguration();
        s.policies[project] = Policy(mode,fee,destination,uint64(block.timestamp));
        emit PolicyScheduled(project,1,mode,fee,destination,uint64(block.timestamp));
        return 1;
    }
    function activePolicy(address project) public view returns(Policy memory) {
        return _layout().policies[project];
    }
    function effectiveFeeBps(address project) public view returns(uint16) {
        Policy memory p = _layout().policies[project];
        if (p.destination == address(0)) revert InvalidConfiguration();
        return INFTUpgradeableActive(p.destination).rewardsActive() ? p.feeBps : 0;
    }
    function quoteInputFee(address project,uint256 amount) external view returns(uint256) {
        return amount * PROTOCOL_FEE_BPS / 10000 + amount * effectiveFeeBps(project) / 10000;
    }
    function poolId(PancakeV1PoolKey calldata key) public pure returns(bytes32) { return keccak256(abi.encode(key)); }
    function registerPool(PancakeV1PoolKey calldata key,address project,address quote,uint160 threshold,bool above) external {
        Layout storage s = _layout();
        if (!s.frozen || msg.sender != s.registrar) revert Unauthorized();
        address c0 = PancakeV1Currency.unwrap(key.currency0);
        address c1 = PancakeV1Currency.unwrap(key.currency1);
        bytes32 id = poolId(key);
        if (s.pools[id].registered || s.policies[project].destination == address(0) || threshold == 0
            || project == quote || project == address(0) || quote == address(0)
            || address(key.hooks) != address(this) || address(key.poolManager) != address(s.poolManager)
            || c0 >= c1 || !((c0 == project && c1 == quote) || (c1 == project && c0 == quote)))
            revert InvalidConfiguration();
        s.pools[id] = Pool(project,quote,threshold,above,true);
        emit PoolRegistered(id,project,quote,threshold,above);
    }
    function beforeSwap(address sender,PancakeV1PoolKey calldata key,IPancakeV1CLPoolManager.SwapParams calldata,bytes calldata)
        external view returns(bytes4,PancakeV1BeforeSwapDelta,uint24) {
        Layout storage s = _layout();
        if (msg.sender != address(s.poolManager) || !s.frozen || !_approvedAdapter(sender)) revert Unauthorized();
        Pool memory p = s.pools[poolId(key)];
        if (!p.registered) revert InvalidConfiguration();
        effectiveFeeBps(p.project);
        return (this.beforeSwap.selector,PancakeV1BeforeSwapDeltaLib.toDelta(0,0),0);
    }
    function afterSwap(address sender,PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params,PancakeV1BalanceDelta delta,bytes calldata)
        external returns(bytes4,int128) {
        Layout storage s = _layout();
        if (msg.sender != address(s.poolManager) || !s.frozen || !_approvedAdapter(sender)) revert Unauthorized();
        bytes32 id = poolId(key);
        Pool memory p = s.pools[id];
        if (!p.registered || sender.code.length == 0) revert InvalidConfiguration();
        if (!s.graduated[p.project]) {
            (uint160 price,,,) = s.poolManager.getSlot0(id);
            if (p.graduateWhenAbove ? price >= p.graduationSqrtPriceX96 : price <= p.graduationSqrtPriceX96) {
                s.graduated[p.project] = true;
                emit TokenGraduated(p.project,id,price);
            }
        }
        bool exactInput = params.amountSpecified < 0;
        bool quote0 = PancakeV1Currency.unwrap(key.currency0) == p.quote;
        bool quoteInput = params.zeroForOne == quote0;
        bool specified = quoteInput == exactInput;
        uint256 amount;
        if (specified) amount = uint256(exactInput ? -params.amountSpecified : params.amountSpecified);
        else {
            int256 q = quote0 ? int256(delta.amount0()) : int256(delta.amount1());
            amount = uint256(q < 0 ? -q : q);
        }
        Pending memory fees = Pending(p.project,p.quote,s.policies[p.project].destination,
            amount * PROTOCOL_FEE_BPS / 10000,amount * effectiveFeeBps(p.project) / 10000);
        if (s.pending[sender].project != address(0)) revert InvalidConfiguration();
        if (specified) _settle(sender,fees);
        else if (fees.protocolFee != 0 || fees.modeFee != 0) s.pending[sender] = fees;
        return (this.afterSwap.selector,0);
    }
    function settleUnspecifiedFee() external {
        Layout storage s = _layout();
        if (!_approvedAdapter(msg.sender)) revert Unauthorized();
        Pending memory p = s.pending[msg.sender];
        if (p.project == address(0)) return;
        delete s.pending[msg.sender];
        _settle(msg.sender,p);
    }
    function _settle(address sender,Pending memory p) private {
        address vault = _layout().protocolVault;
        if (p.protocolFee != 0) {
            uint256 beforeBalance = IERC20(p.quote).balanceOf(vault);
            IPancakeV1FeeSettler(sender).settleHookFee(p.quote,vault,p.protocolFee);
            if (IERC20(p.quote).balanceOf(vault) != beforeBalance + p.protocolFee)
                revert InvalidConfiguration();
            INFTSharedProtocolVault(vault).recordFeeFromAdditionalHook(p.quote,p.protocolFee);
            emit ProtocolFeeAccrued(p.quote,vault,p.protocolFee);
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

    function platformImplementation() external view returns (address) { return BnbERC1967Utils.getImplementation(); }
    function adapterImplementationHash(address a) external view returns (bytes32) { return _layout().adapterImplementationHash[a]; }
    function approveAdapterImplementation(address a) external onlyOwner {
        Layout storage s = _layout();
        if (!s.frozen || !s.trustedAdapter[a] || s.adapterHash[a] != a.codehash) revert Unauthorized();
        _pinImplementation(a);
    }
    function _pinImplementation(address a) private {
        IBnbUpgradeableAdapter adapter = IBnbUpgradeableAdapter(a);
        address implementation = adapter.platformImplementation();
        if (adapter.hook() != address(this) || adapter.poolManager() != address(_layout().poolManager)
            || adapter.owner() != owner() || implementation.code.length == 0) revert InvalidConfiguration();
        _layout().adapterImplementationHash[a] = implementation.codehash;
    }
    function _approvedAdapter(address a) private view returns (bool) {
        Layout storage s = _layout();
        return s.trustedAdapter[a] && s.adapterHash[a] == a.codehash
            && s.adapterImplementationHash[a] == IBnbUpgradeableAdapter(a).platformImplementation().codehash;
    }
}