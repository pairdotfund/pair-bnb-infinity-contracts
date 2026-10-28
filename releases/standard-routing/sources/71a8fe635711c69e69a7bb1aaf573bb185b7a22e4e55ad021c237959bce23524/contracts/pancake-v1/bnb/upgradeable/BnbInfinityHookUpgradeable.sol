// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbPlatformUUPS} from "./BnbPlatformUUPS.sol";

import {
    PancakeV1Currency,
    PancakeV1BeforeSwapDelta,
    PancakeV1BalanceDelta,
    PancakeV1PoolKey,
    IPancakeV1Hooks,
    IPancakeV1CLPoolManager,
    IPancakeV1Vault,
    IPancakeV1FeeReceiver,
    PancakeV1BalanceDeltaLib,
    PancakeV1BeforeSwapDeltaLib
} from "../../PancakeV1InfinityHookTypes.sol";

interface IPancakeV1FeeSettler {
    function settleHookFee(address asset, address destination, uint256 amount) external;
}

interface IPancakeV1InfinityReleaseEngine {
    function hook() external view returns (address);
    function factory() external view returns (address);
}

interface IPancakeV1InfinityReleaseFactory {
    function hook() external view returns (address);
    function engine() external view returns (address);
}

/// @notice Infinity CL hook core for the new PANCAKE_V1 release only.
/// @dev This hook is deliberately . Infinity validates the callback
/// bitmap from the PoolKey parameters and the hook address is part of PoolId;
/// proxying it would make address/permission mistakes a pool-identity risk.
contract BnbInfinityHookUpgradeable is BnbPlatformUUPS, IPancakeV1Hooks {
    using PancakeV1BalanceDeltaLib for PancakeV1BalanceDelta;

    uint16 public constant BPS = 10_000;
    uint16 public constant PROTOCOL_FEE_BPS = 30;
    uint16 public constant MAX_MODE_FEE_BPS = 1_000;
    uint16 public constant HOOK_BITMAP = (1 << 6) | (1 << 7) | (1 << 10) | (1 << 11);
    address public constant BURN = 0x000000000000000000000000000000000000dEaD;

    enum FeeMode { NONE, CREATOR_QUOTE, BURN_PROJECT, FEE_SHARING_QUOTE, HOLDER_QUOTE }
    struct PoolConfig {
        address project;
        address quote;
        uint160 graduationSqrtPriceX96;
        bool graduateWhenAbove;
        bool registered;
    }
    struct Policy {
        FeeMode mode;
        uint16 feeBps;
        address destination;
        uint64 effectiveAt;
    }
    struct PendingFee {
        address project;
        address quote;
        address modeAsset;
        address modeDestination;
        uint256 protocolFee;
        uint256 modeFee;
    }
    struct TokenState {
        uint64 currentEpoch;
        bool graduated;
        bool holderMode;
    }

    IPancakeV1CLPoolManager public  poolManager;
    address public registrar;
    address public  protocolVault;
    address public attestor;
    bool public frozen;
    mapping(bytes32 => PoolConfig) public pools;
    mapping(address => TokenState) public tokenStates;
    mapping(address => mapping(uint64 => Policy)) public policies;
    mapping(address => PendingFee) private _pendingFees;

    error OnlyPoolManager();
    error OnlyRegistrar();
    error UnknownPool();
    error InvalidPool();
    error InvalidPolicy();
    error HolderTransition();
    error AlreadyRegistered();
    error GraduationReadFailed();
    error UnattestedVault();

    event PoolRegistered(bytes32 indexed poolId, address indexed project, address indexed quote,
        uint160 graduationSqrtPriceX96, bool graduateWhenAbove);
    event PolicyScheduled(address indexed project, uint64 indexed epoch, FeeMode mode,
        uint16 feeBps, address destination, uint64 effectiveAt);
    event TokenGraduated(address indexed project, bytes32 indexed poolId, uint160 sqrtPriceX96);
    event ProtocolFeeAccrued(address indexed quote, address indexed destination, uint256 amount);
    event ModeFeeAccrued(address indexed project, address indexed asset, address indexed destination, uint256 amount);

    function initializeProxy(address upgradeAuthority, IPancakeV1CLPoolManager manager_, address registrar_, address owner_, address protocolVault_) external initializer {
_initializePlatform(upgradeAuthority);

        if (address(manager_) == address(0) || protocolVault_ == address(0)
            || protocolVault_.code.length == 0) {
            revert InvalidPool();
        }
        address vault_ = manager_.vault();
        if (vault_ == address(0) || vault_.code.length == 0) revert InvalidPool();
        _validateReceiver(protocolVault_);
        poolManager = manager_;
        // Retain the old constructor shape for artifact compatibility, but
        // never trust a constructor-supplied registrar.  The protected admin
        // binds it exactly once after the reciprocal release graph exists.
        protocolVault = protocolVault_;
    
        if (owner_ != upgradeAuthority || address(manager_) != 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b) revert InvalidPool();
    }

    function getHooksRegistrationBitmap() external pure returns (uint16) {
        return HOOK_BITMAP;
    }

    function finalizeRelease(address engine_, address factory_) external onlyOwner {
        if (frozen || engine_.code.length == 0 || factory_.code.length == 0) revert InvalidPolicy();
        if (IPancakeV1InfinityReleaseEngine(engine_).hook() != address(this)
            || IPancakeV1InfinityReleaseEngine(engine_).factory() != factory_
            || IPancakeV1InfinityReleaseFactory(factory_).hook() != address(this)
            || IPancakeV1InfinityReleaseFactory(factory_).engine() != engine_) {
            revert InvalidPolicy();
        }
        registrar = engine_;
        attestor = factory_;
        frozen = true;
    }

    /// @notice Exact fee debited in quote units when an exact-input quote swap
    /// is executed. Keeping the two floor operations here lets the developer
    /// buy prove the complete quote debit without accepting an arbitrary
    /// slippage allowance for hook fees.
    function quoteInputFee(address project, uint256 amount) external view returns (uint256) {
        Policy memory policy = activePolicy(project);
        uint256 fee = amount * PROTOCOL_FEE_BPS / BPS;
        if (policy.mode != FeeMode.BURN_PROJECT && policy.mode != FeeMode.NONE) {
            fee += amount * policy.feeBps / BPS;
        }
        return fee;
    }

    function poolId(PancakeV1PoolKey calldata key) public pure returns (bytes32) {
        return keccak256(abi.encode(key));
    }

    function registerPool(
        PancakeV1PoolKey calldata key,
        address project,
        address quote,
        uint160 graduationSqrtPriceX96,
        bool graduateWhenAbove
    ) external {
        if (!frozen || msg.sender != registrar) revert OnlyRegistrar();
        if (address(key.hooks) != address(this) || address(key.poolManager) != address(poolManager)
            || project == address(0) || quote == address(0) || project == quote
            || graduationSqrtPriceX96 == 0) revert InvalidPool();
        address c0 = PancakeV1Currency.unwrap(key.currency0);
        address c1 = PancakeV1Currency.unwrap(key.currency1);
        if (!((c0 == project && c1 == quote) || (c0 == quote && c1 == project))) revert InvalidPool();
        bytes32 id = poolId(key);
        if (pools[id].registered) revert AlreadyRegistered();
        pools[id] = PoolConfig(project, quote, graduationSqrtPriceX96, graduateWhenAbove, true);
        emit PoolRegistered(id, project, quote, graduationSqrtPriceX96, graduateWhenAbove);
    }

    /// @notice Append a policy epoch. effectiveAt is intentionally admin
    /// selected and may be block.timestamp (there is no forced timelock).
    function schedulePolicy(address project, FeeMode mode, uint16 feeBps, address destination,
        uint64 effectiveAt) external returns (uint64 epoch) {
        if (msg.sender != owner() && (!frozen || msg.sender != registrar)) revert OnlyRegistrar();
        // Zero is the explicit immediate-activation sentinel. This avoids a
        // race between reading the latest block and mining the admin tx while
        // retaining strict rejection of stale non-zero timestamps.
        if (effectiveAt == 0) effectiveAt = uint64(block.timestamp);
        if (project == address(0) || effectiveAt < block.timestamp) revert InvalidPolicy();
        if (mode == FeeMode.NONE) {
            if (feeBps != 0 || destination != address(0)) revert InvalidPolicy();
        } else {
            if (feeBps == 0 || feeBps > MAX_MODE_FEE_BPS || feeBps % 100 != 0) revert InvalidPolicy();
            if (mode == FeeMode.BURN_PROJECT && destination != BURN) revert InvalidPolicy();
            if (mode != FeeMode.BURN_PROJECT && destination == address(0)) revert InvalidPolicy();
            if (!frozen || mode != FeeMode.BURN_PROJECT) {
                (bool ok, bytes memory data) = attestor.staticcall(abi.encodeWithSignature(
                    "verifyVault(address,uint8,address)", project, uint8(mode), destination));
                if (!ok || data.length < 32 || !abi.decode(data, (bool))) revert UnattestedVault();
            }
            if (mode != FeeMode.BURN_PROJECT) _validateReceiver(destination);
        }
        TokenState storage state = tokenStates[project];
        bool holder = mode == FeeMode.HOLDER_QUOTE;
        if (state.currentEpoch != 0 && holder != state.holderMode) revert HolderTransition();
        epoch = state.currentEpoch + 1;
        policies[project][epoch] = Policy(mode, feeBps, destination, effectiveAt);
        state.currentEpoch = epoch;
        state.holderMode = holder;
        emit PolicyScheduled(project, epoch, mode, feeBps, destination, effectiveAt);
    }

    function activePolicy(address project) public view returns (Policy memory result) {
        TokenState memory state = tokenStates[project];
        if (state.currentEpoch == 0) return result;
        result = policies[project][state.currentEpoch];
        uint64 epoch = state.currentEpoch;
        while (result.effectiveAt > block.timestamp && epoch > 1) {
            result = policies[project][--epoch];
        }
        if (result.effectiveAt > block.timestamp) result = Policy(FeeMode.NONE, 0, address(0), 0);
    }

    function beforeSwap(address sender, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params, bytes calldata)
        external view returns (bytes4, PancakeV1BeforeSwapDelta, uint24) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _authorizeAdapter(sender);
        _pool(key);
        key;
        params;
        // Fees are settled from the authenticated adapter's gross input/output
        // credits. Infinity's specified custom delta creates a matching hook
        // debt, so it cannot safely collect an additive fee.
        return (this.beforeSwap.selector, PancakeV1BeforeSwapDeltaLib.toDelta(0, 0), 0);
    }

    function afterSwap(address sender, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params, PancakeV1BalanceDelta delta, bytes calldata)
        external returns (bytes4, int128) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        _authorizeAdapter(sender);
        PoolConfig memory p = _pool(key);
        bytes32 id = poolId(key);
        _syncGraduation(id, p);
        (uint256 protocolSpecified, uint256 modeSpecified) = _feeQuote(key, p, params);
        (uint256 protocolFee, uint256 modeFee, uint256 unspecifiedFee) =
            _feeQuoteAfter(key, p, params, delta);
        if (protocolSpecified != 0 || modeSpecified != 0) {
            _settleFees(sender, p, protocolSpecified, modeSpecified);
        }
        if (unspecifiedFee != 0) {
            PendingFee storage pending = _pendingFees[sender];
            if (pending.protocolFee != 0 || pending.modeFee != 0) revert InvalidPolicy();
            Policy memory policy = activePolicy(p.project);
            pending.project = p.project;
            pending.quote = p.quote;
            pending.modeAsset = policy.mode == FeeMode.BURN_PROJECT ? p.project : p.quote;
            pending.modeDestination = policy.destination;
            pending.protocolFee = protocolFee;
            pending.modeFee = modeFee;
        }
        // Unspecified output credit is posted to the adapter only after this
        // callback returns. settleUnspecifiedFee() consumes the pending fee
        // from that adapter credit without creating any hook delta.
        return (this.afterSwap.selector, 0);
    }

    function settleUnspecifiedFee() external {
        _authorizeAdapter(msg.sender);
        if (msg.sender.code.length == 0) revert InvalidPolicy();
        PendingFee memory pending = _pendingFees[msg.sender];
        if (pending.protocolFee == 0 && pending.modeFee == 0) return;
        delete _pendingFees[msg.sender];
        if (pending.protocolFee != 0) {
            IPancakeV1FeeSettler(msg.sender).settleHookFee(
                pending.quote, protocolVault, pending.protocolFee
            );
            IPancakeV1FeeReceiver(protocolVault).recordFee(
                pending.quote, pending.protocolFee
            );
            emit ProtocolFeeAccrued(pending.quote, protocolVault, pending.protocolFee);
        }
        if (pending.modeFee != 0) {
            IPancakeV1FeeSettler(msg.sender).settleHookFee(
                pending.modeAsset, pending.modeDestination, pending.modeFee
            );
            if (pending.modeDestination != BURN) {
                IPancakeV1FeeReceiver(pending.modeDestination).recordFee(
                    pending.modeAsset, pending.modeFee
                );
            }
            emit ModeFeeAccrued(
                pending.project, pending.modeAsset, pending.modeDestination, pending.modeFee
            );
        }
    }

    function _pool(PancakeV1PoolKey calldata key) private view returns (PoolConfig memory p) {
        p = pools[poolId(key)];
        if (!p.registered) revert UnknownPool();
    }

    /// @dev Historical releases retain their behavior. New chain candidates
    /// override this boundary to enforce cooperative settlement adapters.
    function _authorizeAdapter(address) internal view virtual {}

    function _syncGraduation(bytes32 id, PoolConfig memory p) private {
        TokenState storage state = tokenStates[p.project];
        if (state.graduated) return;
        (bool ok, bytes memory data) = address(poolManager).staticcall(
            abi.encodeCall(IPancakeV1CLPoolManager.getSlot0, (id)));
        if (!ok || data.length < 32) revert GraduationReadFailed();
        (uint160 current,,,) = abi.decode(data, (uint160, int24, uint24, uint24));
        bool reached = p.graduateWhenAbove
            ? current >= p.graduationSqrtPriceX96
            : current <= p.graduationSqrtPriceX96;
        if (reached) {
            state.graduated = true;
            emit TokenGraduated(p.project, id, current);
        }
    }

    function _feeQuote(PancakeV1PoolKey calldata key, PoolConfig memory p,
        IPancakeV1CLPoolManager.SwapParams calldata params)
        private view returns (uint256 protocol, uint256 mode) {
        bool exactInput = params.amountSpecified < 0;
        bool quoteInput = params.zeroForOne
            ? PancakeV1Currency.unwrap(key.currency0) == p.quote
            : PancakeV1Currency.unwrap(key.currency1) == p.quote;
        bool specifiedIsQuote = quoteInput == exactInput;
        uint256 amount = uint256(exactInput ? -params.amountSpecified : params.amountSpecified);
        Policy memory policy = activePolicy(p.project);
        protocol = specifiedIsQuote ? amount * PROTOCOL_FEE_BPS / BPS : 0;
        bool modeIsQuote = policy.mode != FeeMode.BURN_PROJECT;
        mode = _modeFee(policy, modeIsQuote == specifiedIsQuote, amount);
    }

    function _feeQuoteAfter(PancakeV1PoolKey calldata key, PoolConfig memory p,
        IPancakeV1CLPoolManager.SwapParams calldata params, PancakeV1BalanceDelta delta)
        private view returns (uint256 protocol, uint256 mode, uint256 unspecifiedFee) {
        bool exactInput = params.amountSpecified < 0;
        bool quoteInput = params.zeroForOne
            ? PancakeV1Currency.unwrap(key.currency0) == p.quote
            : PancakeV1Currency.unwrap(key.currency1) == p.quote;
        bool specifiedIsQuote = quoteInput == exactInput;
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();
        bool quote0 = p.quote == PancakeV1Currency.unwrap(key.currency0);
        int128 q = quote0 ? amount0 : amount1;
        int128 t = quote0 ? amount1 : amount0;
        uint256 quoteAmount = uint256(q < 0 ? -int256(q) : int256(q));
        uint256 projectAmount = uint256(t < 0 ? -int256(t) : int256(t));
        Policy memory policy = activePolicy(p.project);
        protocol = specifiedIsQuote ? 0
            : quoteAmount * PROTOCOL_FEE_BPS / BPS;
        bool modeIsQuote = policy.mode != FeeMode.BURN_PROJECT;
        if (policy.mode == FeeMode.NONE) {
            mode = 0;
        } else if (modeIsQuote) {
            mode = specifiedIsQuote ? 0 : quoteAmount * policy.feeBps / BPS;
        } else {
            mode = specifiedIsQuote ? projectAmount * policy.feeBps / BPS : 0;
        }
        unspecifiedFee = protocol + mode;
    }

    function _modeFee(Policy memory policy, bool feeAssetIsSpecified, uint256 amount)
        private pure returns (uint256) {
        if (policy.mode == FeeMode.NONE) return 0;
        if (!feeAssetIsSpecified) return 0;
        return amount * policy.feeBps / BPS;
    }

    function _settleFees(
        address sender,
        PoolConfig memory p,
        uint256 protocolFee,
        uint256 modeFee
    ) private {
        if (sender.code.length == 0) revert InvalidPolicy();
        if (protocolFee != 0) {
            IPancakeV1FeeSettler(sender).settleHookFee(
                p.quote, protocolVault, protocolFee
            );
            IPancakeV1FeeReceiver(protocolVault).recordFee(p.quote, protocolFee);
            emit ProtocolFeeAccrued(p.quote, protocolVault, protocolFee);
        }
        if (modeFee != 0) {
            Policy memory policy = activePolicy(p.project);
            address asset = policy.mode == FeeMode.BURN_PROJECT ? p.project : p.quote;
            IPancakeV1FeeSettler(sender).settleHookFee(
                asset, policy.destination, modeFee
            );
            if (policy.destination != BURN) {
                IPancakeV1FeeReceiver(policy.destination).recordFee(asset, modeFee);
            }
            emit ModeFeeAccrued(p.project, asset, policy.destination, modeFee);
        }
    }

    function _toInt128(uint256 value) private pure returns (int128) {
        require(value <= uint256(uint128(type(int128).max)), "FEE_OVERFLOW");
        return int128(uint128(value));
    }

    function _validateReceiver(address receiver) private view {
        if (receiver.code.length == 0) revert InvalidPolicy();
        // Keep the compatibility check typed, rather than treating arbitrary
        // destinations as fee sinks. The call itself is made after take().
        IPancakeV1FeeReceiver(receiver);
    }
}