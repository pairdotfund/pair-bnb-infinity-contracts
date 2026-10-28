// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    PancakeV1Currency,
    PancakeV1BalanceDelta,
    PancakeV1BeforeSwapDelta,
    PancakeV1PoolKey,
    IPancakeV1CLPoolManager,
    IPancakeV1Vault
} from "../PancakeV1InfinityHookTypes.sol";

interface IPancakeV1InfinityHookTest {
    function beforeSwap(address, PancakeV1PoolKey calldata,
        IPancakeV1CLPoolManager.SwapParams calldata, bytes calldata)
        external returns (bytes4, PancakeV1BeforeSwapDelta, uint24);
    function afterSwap(address, PancakeV1PoolKey calldata,
        IPancakeV1CLPoolManager.SwapParams calldata, PancakeV1BalanceDelta, bytes calldata)
        external returns (bytes4, int128);
}

contract PancakeV1InfinityHookMockVault is IPancakeV1Vault {
    address public immutable manager;
    event Taken(address indexed currency, address indexed to, uint256 amount);
    constructor(address manager_) { manager = manager_; }
    function take(PancakeV1Currency currency, address to, uint256 amount) external {
        emit Taken(PancakeV1Currency.unwrap(currency), to, amount);
    }
    function lock(bytes calldata) external pure returns (bytes memory) { return ""; }
    function currencyDelta(address, PancakeV1Currency) external pure returns (int256) { return 0; }
    function getUnsettledDeltasCount() external pure returns (uint256) { return 0; }
    function sync(PancakeV1Currency) external {}
    function settleFor(address) external payable returns (uint256) { return 0; }
}

contract PancakeV1InfinityHookMockFeeReceiver {
    event FeeRecorded(address indexed asset, uint256 amount);
    function recordFee(address asset, uint256 amount) external {
        emit FeeRecorded(asset, amount);
    }
}

contract PancakeV1InfinityGraphEngineMock {
    address public immutable hook;
    address public factory;
    constructor(address hook_, address factory_) {
        hook = hook_;
        factory = factory_;
    }
    function setFactory(address factory_) external {
        require(factory == address(0));
        factory = factory_;
    }
    function registerPool(bytes calldata encoded) external {
        (bool ok,) = hook.call(encoded);
        require(ok);
    }
    function forward(address target, bytes calldata encoded) external returns (bytes memory out) {
        (bool ok, bytes memory data) = target.call(encoded);
        require(ok);
        return data;
    }
}

contract PancakeV1AtomicMigrationEngineMock {
    bool public valid = true;
    function setValid(bool value) external { valid = value; }
    function validateLaunchpad(address) external view returns (bool) { return valid; }
}

contract PancakeV1AtomicMigrationProxyMock {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    address public owner;
    constructor(address owner_, address currentEngine) {
        owner = owner_;
        assembly { sstore(57, currentEngine) }
    }
    function engine() external view returns (address value) {
        assembly { value := sload(57) }
    }
    function implementation() external view returns (address value) {
        assembly { value := sload(IMPLEMENTATION_SLOT) }
    }
    function arm(address migrator) external {
        require(msg.sender == owner);
        assembly { sstore(IMPLEMENTATION_SLOT, migrator) }
    }
    function execute(address migrator) external {
        require(msg.sender == owner);
        assembly { sstore(IMPLEMENTATION_SLOT, migrator) }
        (bool ok, bytes memory data) = migrator.delegatecall(abi.encodeWithSignature("migrate()"));
        if (!ok) assembly { revert(add(data, 32), mload(data)) }
    }
}

contract PancakeV1InfinityGraphFactoryMock {
    address public immutable hook;
    address public engine;
    constructor(address hook_, address engine_) {
        hook = hook_;
        engine = engine_;
    }
    function verifyVault(address, uint8, address) external pure returns (bool) {
        return true;
    }
}

contract PancakeV1InfinityHookMockManager is IPancakeV1CLPoolManager {
    error HookFundedTransfer(address currency, uint256 amount);

    uint160 public sqrtPriceX96 = 1 << 96;
    address public immutable vaultAddress;

    constructor() {
        vaultAddress = address(new PancakeV1InfinityHookMockVault(address(this)));
    }
    function setSqrtPrice(uint160 value) external { sqrtPriceX96 = value; }
    function vault() external view returns (address) { return vaultAddress; }

    function getSlot0(bytes32)
        external view returns (uint160, int24, uint24, uint24) {
        return (sqrtPriceX96, 0, 0, 10_000);
    }
    function swap(PancakeV1PoolKey calldata, IPancakeV1CLPoolManager.SwapParams calldata, bytes calldata)
        external pure returns (PancakeV1BalanceDelta) {
        return PancakeV1BalanceDelta.wrap(0);
    }

    function invokeBefore(address hook, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params)
        external returns (bytes4, PancakeV1BeforeSwapDelta, uint24) {
        return IPancakeV1InfinityHookTest(hook).beforeSwap(msg.sender, key, params, "");
    }

    /// @dev Models the relevant Infinity Vault boundary: a positive
    /// specified delta makes the hook owe the specified currency, while a
    /// negative delta is funded by the swapper's input.
    function settleBeforeSwap(address hook, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params)
        external returns (int128 specifiedDelta) {
        (, PancakeV1BeforeSwapDelta beforeDelta,) =
            IPancakeV1InfinityHookTest(hook).beforeSwap(msg.sender, key, params, "");
        int256 packed = PancakeV1BeforeSwapDelta.unwrap(beforeDelta);
        specifiedDelta = int128(packed >> 128);
        if (specifiedDelta > 0) {
            address specifiedCurrency = params.zeroForOne
                ? PancakeV1Currency.unwrap(key.currency0)
                : PancakeV1Currency.unwrap(key.currency1);
            revert HookFundedTransfer(specifiedCurrency, uint256(int256(specifiedDelta)));
        }
    }

    function invokeAfter(address hook, PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params, PancakeV1BalanceDelta delta)
        external returns (bytes4, int128) {
        return IPancakeV1InfinityHookTest(hook).afterSwap(address(this), key, params, delta, "");
    }
    function settleHookFee(address asset, address destination, uint256 amount) external {
        IPancakeV1Vault(vaultAddress).take(PancakeV1Currency.wrap(asset), destination, amount);
    }
}