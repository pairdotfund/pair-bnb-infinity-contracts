// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    PancakeV1Currency, PancakeV1BeforeSwapDelta, PancakeV1BalanceDelta,
    PancakeV1PoolKey, IPancakeV1Hooks, IPancakeV1CLPoolManager,
    IPancakeV1Vault, IPancakeV1FeeReceiver,
    PancakeV1BalanceDeltaLib, PancakeV1BeforeSwapDeltaLib
} from "../../PancakeV1InfinityHookTypes.sol";

interface IStandardReleaseGraph {
    function hook() external view returns (address);
    function factory() external view returns (address);
    function engine() external view returns (address);
    function verifyVault(address project, uint8 mode, address destination) external view returns (bool);
}

interface IStandardCreditVault {
    function mint(address to, PancakeV1Currency currency, uint256 amount) external;
    function burn(address from, PancakeV1Currency currency, uint256 amount) external;
    function balanceOf(address owner, PancakeV1Currency currency) external view returns (uint256);
}

/// @notice Isolated, non-proxy successor. NOT a replacement implementation for a deployed hook.
/// @dev Any locker may swap. Fees are minted as backed Infinity Vault claims.
/// CLPoolManager cancels the hook's mint debt with its positive callback delta.
/// Permissionless redemption occurs in a SEPARATE lock after router funding;
/// it never relies on unrelated physical Vault liquidity during a callback.
contract BnbInfinityStandardHook is Ownable, IPancakeV1Hooks {
    using PancakeV1BalanceDeltaLib for PancakeV1BalanceDelta;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 30;
    uint16 public constant MAX_MODE_FEE_BPS = 1_000;
    uint16 public constant HOOK_BITMAP = (1 << 6) | (1 << 7) | (1 << 10) | (1 << 11);
    address public constant BURN = 0x000000000000000000000000000000000000dEaD;
    // Keep the numeric mode identities used by the existing factories.
    enum FeeMode { NONE, CREATOR_QUOTE, BURN_PROJECT, FEE_SHARING_QUOTE, HOLDER_QUOTE, NFT_QUOTE }
    struct PoolConfig {
        address project;
        address quote;
        uint160 graduationSqrtPriceX96;
        bool graduateWhenAbove;
        bool registered;
    }
    struct Policy { FeeMode mode; uint16 feeBps; address destination; uint64 effectiveAt; }
    struct TokenState { uint64 currentEpoch; bool graduated; bool holderMode; }

    IPancakeV1CLPoolManager public immutable poolManager;
    IPancakeV1Vault public immutable vault;
    address public immutable protocolVault;
    address public registrar;
    address public attestor;
    bool public frozen;
    bool internal _inCallback;
    bool private _settling;
    bool private _settlementCallbackPending;
    mapping(bytes32 => PoolConfig) public pools;
    mapping(address => TokenState) public tokenStates;
    mapping(address => mapping(uint64 => Policy)) public policies;
    mapping(address => mapping(address => uint256)) public pendingFee;
    mapping(address => uint256) public totalPendingFee;

    error Unauthorized();
    error InvalidConfiguration();
    error UnknownPool();
    error InvalidPolicy();
    error PartialFill();
    error FeeOverflow();
    error Reentered();
    error NothingToSettle();
    error UnsupportedTransfer();

    event PoolRegistered(bytes32 indexed poolId, address indexed project, address indexed quote,
        uint160 graduationSqrtPriceX96, bool graduateWhenAbove);
    event PolicyScheduled(address indexed project, uint64 indexed epoch, FeeMode mode,
        uint16 feeBps, address destination, uint64 effectiveAt);
    event TokenGraduated(address indexed project, bytes32 indexed poolId, uint160 sqrtPriceX96);
    event ProtocolFeeAccrued(address indexed quote, address indexed destination, uint256 amount);
    event ModeFeeAccrued(address indexed project, address indexed asset, address indexed destination, uint256 amount);
    event FeesDistributed(address indexed destination, address indexed asset, uint256 amount, address indexed caller);
    event ProjectFeesBurned(address indexed project, uint256 amount, address indexed caller);

    constructor(IPancakeV1CLPoolManager manager_, address admin, address protocol_) Ownable(admin) {
        if (block.chainid != 56
            || address(manager_) != 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b
            || protocol_.code.length == 0) revert InvalidConfiguration();
        address vault_ = manager_.vault();
        if (vault_ != 0x238a358808379702088667322f80aC48bAd5e6c4 || vault_.code.length == 0)
            revert InvalidConfiguration();
        poolManager = manager_;
        vault = IPancakeV1Vault(vault_);
        protocolVault = protocol_;
    }

    modifier callback() {
        if (msg.sender != address(poolManager)) revert Unauthorized();
        if (_inCallback || _settling) revert Reentered();
        _inCallback = true;
        _;
        _inCallback = false;
    }

    function feeAccountingVersion() external pure returns (uint8) { return 2; }
    function getHooksRegistrationBitmap() external pure returns (uint16) { return HOOK_BITMAP; }
    function poolId(PancakeV1PoolKey calldata key) public pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    function finalizeRelease(address engine_, address factory_) external onlyOwner {
        if (frozen || _inCallback || _settling || engine_.code.length == 0 || factory_.code.length == 0)
            revert InvalidConfiguration();
        if (IStandardReleaseGraph(engine_).hook() != address(this)
            || IStandardReleaseGraph(engine_).factory() != factory_
            || IStandardReleaseGraph(factory_).hook() != address(this)
            || IStandardReleaseGraph(factory_).engine() != engine_) revert InvalidConfiguration();
        registrar = engine_;
        attestor = factory_;
        frozen = true;
    }

    function registerPool(PancakeV1PoolKey calldata key, address project, address quote,
        uint160 threshold, bool above) external {
        if (!frozen || msg.sender != registrar || _inCallback || _settling) revert Unauthorized();
        address c0 = PancakeV1Currency.unwrap(key.currency0);
        address c1 = PancakeV1Currency.unwrap(key.currency1);
        if (address(key.hooks) != address(this) || address(key.poolManager) != address(poolManager)
            || key.fee != 10_000 || uint16(uint256(key.parameters)) != HOOK_BITMAP
            || c0 >= c1 || project == address(0) || quote == address(0) || project == quote
            || threshold == 0 || tokenStates[project].currentEpoch == 0
            || !((c0 == project && c1 == quote) || (c0 == quote && c1 == project)))
            revert InvalidConfiguration();
        bytes32 id = poolId(key);
        if (pools[id].registered) revert InvalidConfiguration();
        pools[id] = PoolConfig(project, quote, threshold, above, true);
        emit PoolRegistered(id, project, quote, threshold, above);
    }

    function schedulePolicy(address project, FeeMode mode, uint16 feeBps, address destination,
        uint64 effectiveAt) external virtual returns (uint64 epoch) {
        if (_inCallback || _settling || (msg.sender != owner() && (!frozen || msg.sender != registrar)))
            revert Unauthorized();
        if (mode == FeeMode.NFT_QUOTE) revert InvalidPolicy();
        return _schedulePolicy(project, mode, feeBps, destination, effectiveAt);
    }

    function _schedulePolicy(address project, FeeMode mode, uint16 feeBps, address destination,
        uint64 effectiveAt) internal returns (uint64 epoch) {
        if (_inCallback || _settling) revert Reentered();
        if (effectiveAt == 0) effectiveAt = uint64(block.timestamp);
        if (!frozen || project == address(0) || effectiveAt < block.timestamp) revert InvalidPolicy();
        if (mode == FeeMode.NONE) {
            if (feeBps != 0 || destination != address(0)) revert InvalidPolicy();
        } else {
            if (feeBps == 0 || feeBps > MAX_MODE_FEE_BPS || feeBps % 100 != 0) revert InvalidPolicy();
            if (mode == FeeMode.BURN_PROJECT) {
                if (destination != BURN) revert InvalidPolicy();
            } else if (destination.code.length == 0) revert InvalidPolicy();
            if (mode != FeeMode.BURN_PROJECT
                && !IStandardReleaseGraph(attestor).verifyVault(project, uint8(mode), destination))
                revert InvalidPolicy();
        }
        TokenState storage state = tokenStates[project];
        bool holder = mode == FeeMode.HOLDER_QUOTE;
        if (state.currentEpoch != 0 && holder != state.holderMode) revert InvalidPolicy();
        epoch = ++state.currentEpoch;
        policies[project][epoch] = Policy(mode, feeBps, destination, effectiveAt);
        state.holderMode = holder;
        emit PolicyScheduled(project, epoch, mode, feeBps, destination, effectiveAt);
    }

    function activePolicy(address project) public view returns (Policy memory result) {
        uint64 epoch = tokenStates[project].currentEpoch;
        while (epoch != 0) {
            result = policies[project][epoch--];
            if (result.effectiveAt <= block.timestamp) return result;
        }
        return Policy(FeeMode.NONE, 0, address(0), 0);
    }

    /// @notice Informational only. Fees are ALREADY in CLQuoter's returned delta.
    /// Never add this amount to a standard-router exact-input amount.
    function quoteInputFee(address project, uint256 amount) external view returns (uint256) {
        Policy memory p = _feePolicy(project);
        return amount * PROTOCOL_FEE_BPS / BPS
            + (p.mode != FeeMode.NONE && p.mode != FeeMode.BURN_PROJECT ? amount * p.feeBps / BPS : 0);
    }

    function _feePolicy(address project) internal view virtual returns (Policy memory) {
        return activePolicy(project);
    }

    function _pool(PancakeV1PoolKey calldata key) private view returns (PoolConfig memory p) {
        p = pools[poolId(key)];
        if (!p.registered) revert UnknownPool();
    }

    function _specifiedFees(PoolConfig memory p, Policy memory policy,
        PancakeV1PoolKey calldata key, IPancakeV1CLPoolManager.SwapParams calldata params)
        private pure returns (uint256 protocol, uint256 mode) {
        bool exactInput = params.amountSpecified < 0;
        // All standard quoter/router amounts are restricted to signed int128.
        if (params.amountSpecified == 0 || params.amountSpecified < -int256(type(int128).max)
            || params.amountSpecified > int256(type(int128).max)) revert FeeOverflow();
        uint256 amount = uint256(exactInput ? -params.amountSpecified : params.amountSpecified);
        bool quoteInput = params.zeroForOne == (PancakeV1Currency.unwrap(key.currency0) == p.quote);
        bool specifiedQuote = quoteInput == exactInput;
        if (specifiedQuote) protocol = amount * PROTOCOL_FEE_BPS / BPS;
        if (policy.mode != FeeMode.NONE && (policy.mode != FeeMode.BURN_PROJECT) == specifiedQuote)
            mode = amount * policy.feeBps / BPS;
    }

    function beforeSwap(address, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params, bytes calldata)
        external callback returns (bytes4, PancakeV1BeforeSwapDelta, uint24) {
        PoolConfig memory p = _pool(key);
        Policy memory policy = _feePolicy(p.project);
        (uint256 protocol, uint256 mode) = _specifiedFees(p, policy, key, params);
        uint256 total = protocol + mode;
        if (params.amountSpecified < 0 && total >= uint256(-params.amountSpecified)) revert InvalidPolicy();
        _pay(p, policy, protocol, mode);
        // Positive specified fee: less pool input for exact-input, extra pool
        // output for exact-output. The returned caller delta includes both.
        return (this.beforeSwap.selector, PancakeV1BeforeSwapDeltaLib.toDelta(_int128(total), 0), 0);
    }

    function afterSwap(address, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params, PancakeV1BalanceDelta delta, bytes calldata)
        external callback returns (bytes4, int128) {
        PoolConfig memory p = _pool(key);
        Policy memory policy = _feePolicy(p.project);
        (uint256 ps, uint256 ms) = _specifiedFees(p, policy, key, params);
        bool exactInput = params.amountSpecified < 0;
        int256 expected = params.amountSpecified + int256(ps + ms);
        // Never collect a fee for an unfilled specified amount.
        bool specified0 = exactInput == params.zeroForOne;
        if (int256(specified0 ? delta.amount0() : delta.amount1()) != expected) revert PartialFill();
        int256 q = PancakeV1Currency.unwrap(key.currency0) == p.quote
            ? int256(delta.amount0()) : int256(delta.amount1());
        int256 t = PancakeV1Currency.unwrap(key.currency0) == p.project
            ? int256(delta.amount0()) : int256(delta.amount1());
        bool quoteInput = params.zeroForOne == (PancakeV1Currency.unwrap(key.currency0) == p.quote);
        bool specifiedQuote = quoteInput == exactInput;
        uint256 quoteAmount = uint256(q < 0 ? -q : q);
        uint256 projectAmount = uint256(t < 0 ? -t : t);
        uint256 protocol = specifiedQuote ? 0 : quoteAmount * PROTOCOL_FEE_BPS / BPS;
        uint256 mode;
        if (policy.mode == FeeMode.BURN_PROJECT && specifiedQuote)
            mode = projectAmount * policy.feeBps / BPS;
        else if (policy.mode != FeeMode.NONE && policy.mode != FeeMode.BURN_PROJECT && !specifiedQuote)
            mode = quoteAmount * policy.feeBps / BPS;
        _syncGraduation(poolId(key), p);
        _pay(p, policy, protocol, mode);
        return (this.afterSwap.selector, _int128(protocol + mode));
    }

    function _int128(uint256 amount) private pure returns (int128) {
        if (amount > uint256(uint128(type(int128).max))) revert FeeOverflow();
        return int128(uint128(amount));
    }

    function _pay(PoolConfig memory p, Policy memory policy, uint256 protocol, uint256 mode) private {
        if (protocol != 0) {
            _credit(protocolVault, p.quote, protocol);
            IPancakeV1FeeReceiver(protocolVault).recordFee(p.quote, protocol);
            emit ProtocolFeeAccrued(p.quote, protocolVault, protocol);
        }
        if (mode != 0) {
            address asset = policy.mode == FeeMode.BURN_PROJECT ? p.project : p.quote;
            _credit(policy.destination, asset, mode);
            if (policy.destination != BURN) IPancakeV1FeeReceiver(policy.destination).recordFee(asset, mode);
            emit ModeFeeAccrued(p.project, asset, policy.destination, mode);
        }
    }

    function _credit(address destination, address asset, uint256 amount) private {
        pendingFee[destination][asset] += amount;
        totalPendingFee[asset] += amount;
        IStandardCreditVault(address(vault)).mint(address(this), PancakeV1Currency.wrap(asset), amount);
    }

    /// @notice Anyone pays gas; only an already-accrued destination can receive
    /// funds. This does NOT claim the destination vault's users' entitlements.
    /// maximum caps work and allows partial redemption. No caller bounty.
    function distributeFees(address destination, address asset, uint256 maximum) external returns (uint256) {
        return _distribute(destination, asset, maximum);
    }

    /// @notice Permissionless burn trigger. BURN is fixed; no caller-supplied recipient.
    /// Transfers project tokens to the existing dead-address sink (not a supply burn).
    function burnFees(address project, uint256 maximum) external returns (uint256 amount) {
        amount = _distribute(BURN, project, maximum);
        emit ProjectFeesBurned(project, amount, msg.sender);
    }

    function _distribute(address destination, address asset, uint256 maximum) private returns (uint256 amount) {
        if (_inCallback || _settling) revert Reentered();
        if (maximum == 0) revert NothingToSettle();
        amount = pendingFee[destination][asset];
        if (amount > maximum) amount = maximum;
        if (amount > uint256(uint128(type(int128).max))) amount = uint256(uint128(type(int128).max));
        if (amount == 0) revert NothingToSettle();
        _settling = true;
        _settlementCallbackPending = true;
        vault.lock(abi.encode(destination, asset, amount));
        if (_settlementCallbackPending) revert InvalidConfiguration();
        _settling = false;
        emit FeesDistributed(destination, asset, amount, msg.sender);
    }

    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(vault) || !_settling || !_settlementCallbackPending) revert Unauthorized();
        _settlementCallbackPending = false;
        (address destination, address asset, uint256 amount) = abi.decode(data, (address, address, uint256));
        pendingFee[destination][asset] -= amount;
        totalPendingFee[asset] -= amount;
        uint256 beforeBalance = IERC20(asset).balanceOf(destination);
        IStandardCreditVault(address(vault)).burn(address(this), PancakeV1Currency.wrap(asset), amount);
        vault.take(PancakeV1Currency.wrap(asset), destination, amount);
        if (IERC20(asset).balanceOf(destination) != beforeBalance + amount) revert UnsupportedTransfer();
        // Do not recordFee again: recipients were credited at the original
        // trade's policy/ownership checkpoint, not at this settlement time.
        return "";
    }

    function _syncGraduation(bytes32 id, PoolConfig memory p) private {
        TokenState storage state = tokenStates[p.project];
        if (state.graduated) return;
        (uint160 price,,,) = poolManager.getSlot0(id);
        if (p.graduateWhenAbove ? price >= p.graduationSqrtPriceX96 : price <= p.graduationSqrtPriceX96) {
            state.graduated = true;
            emit TokenGraduated(p.project, id, price);
        }
    }
}
