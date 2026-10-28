// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Narrow, compatible view of the existing V5 stock registry.
/// Provenance: contracts/v5/interfaces/IPairV4.sol (ABI is intentionally
/// repeated here so this release has no runtime dependency on retired code).
interface IStockTokenRegistryV5Compatible {
    struct StockConfig {
        bool enabled;
        uint8 decimals;
        bytes32 symbol;
        address priceFeed;
        uint256 graduationTargetUsdE8;
        bool ethRouteEnabled;
    }
    function isEnabled(address token) external view returns (bool);
    function getConfig(address token) external view returns (StockConfig memory);
}

interface IPancakeV1Feed {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80,int256,uint256,uint256,uint80);
}

type V1Currency is address;
type V1PoolId is bytes32;
interface IV1Hooks {}
interface IV1PoolManager {
    function vault() external view returns (address);
    function initialize(V1PoolKey calldata key, uint160 sqrtPriceX96) external returns (int24);
}
interface IV1Vault {
    function manager() external view returns (address);
}
struct V1PoolKey {
    V1Currency currency0;
    V1Currency currency1;
    IV1Hooks hooks;
    IV1PoolManager poolManager;
    uint24 fee;
    bytes32 parameters;
}
interface IV1Permit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    function pull(address token, address owner, address to, uint256 amount) external;
}
interface IV1CLPositionManager {
    function vault() external view returns (address);
    function clPoolManager() external view returns (IV1PoolManager);
    function permit2() external view returns (address);
    function nextTokenId() external view returns (uint256);
    function modifyLiquidities(bytes calldata payload, uint256 deadline) external payable;
}