// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Narrow ABI-compatible Pancake Infinity CL types.  These are
/// intentionally vendored because the application does not pin the upstream
/// Infinity package as a Solidity dependency.
type PancakeV1Currency is address;
type PancakeV1BeforeSwapDelta is int256;
type PancakeV1BalanceDelta is int256;

interface IPancakeV1Hooks {
    function getHooksRegistrationBitmap() external view returns (uint16);
}

interface IPancakeV1CLPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    function vault() external view returns (address);
    function getSlot0(bytes32 poolId)
        external view returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
    function swap(
        PancakeV1PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata hookData
    ) external returns (PancakeV1BalanceDelta delta);
}

interface IPancakeV1Vault {
    function manager() external view returns (address);
    function lock(bytes calldata data) external returns (bytes memory);
    function currencyDelta(address settler, PancakeV1Currency currency) external view returns (int256);
    function getUnsettledDeltasCount() external view returns (uint256);
    function sync(PancakeV1Currency currency) external;
    function settleFor(address recipient) external payable returns (uint256);
    function take(PancakeV1Currency currency, address to, uint256 amount) external;
}

interface IPancakeV1LockCallback {
    function lockAcquired(bytes calldata data) external returns (bytes memory);
}

interface IPancakeV1FeeReceiver {
    function recordFee(address asset, uint256 amount) external;
}

struct PancakeV1PoolKey {
    PancakeV1Currency currency0;
    PancakeV1Currency currency1;
    IPancakeV1Hooks hooks;
    IPancakeV1CLPoolManager poolManager;
    uint24 fee;
    bytes32 parameters;
}

library PancakeV1BalanceDeltaLib {
    function amount0(PancakeV1BalanceDelta delta) internal pure returns (int128 value) {
        assembly ("memory-safe") { value := sar(128, delta) }
    }

    function amount1(PancakeV1BalanceDelta delta) internal pure returns (int128 value) {
        assembly ("memory-safe") { value := signextend(15, delta) }
    }
}

library PancakeV1BeforeSwapDeltaLib {
    function toDelta(int128 specified, int128 unspecified)
        internal pure returns (PancakeV1BeforeSwapDelta value) {
        assembly ("memory-safe") {
            value := or(shl(128, specified), and(sub(shl(128, 1), 1), unspecified))
        }
    }
}