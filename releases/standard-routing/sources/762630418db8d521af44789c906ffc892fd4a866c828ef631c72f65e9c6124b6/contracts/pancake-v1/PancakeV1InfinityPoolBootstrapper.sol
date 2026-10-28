// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IV1PoolManager, IV1Permit2, IV1CLPositionManager, IV1Hooks, V1Currency, V1PoolKey} from "./PancakeV1Interfaces.sol";

contract PancakeV1InfinityPoolBootstrapper {
    using SafeERC20 for IERC20;
    IV1PoolManager public immutable manager;
    IV1CLPositionManager public immutable positions;
    IV1Permit2 public immutable permit2;
    IV1Hooks public immutable hook;
    uint24 public constant FEE = 10_000;
    int24 public constant SPACING = 200;

    constructor(IV1PoolManager manager_, IV1CLPositionManager positions_, IV1Permit2 permit2_, IV1Hooks hook_) {
        if (address(manager_).code.length == 0 || address(positions_).code.length == 0
            || address(permit2_).code.length == 0 || address(hook_).code.length == 0
            || address(manager_.vault()).code.length == 0) revert();
        manager = manager_; positions = positions_; permit2 = permit2_; hook = hook_;
    }

    function initializePool(address token, address quote, uint256 amount, uint256 deadline, address lock,
        uint160 opening, int24 lower, int24 upper, uint16 bitmap)
        external returns (bytes32 pid, uint256 positionId) {
        (bool registrarOk, bytes memory registrarData) = address(hook).staticcall(
            abi.encodeWithSignature("registrar()"));
        if (!registrarOk || registrarData.length < 32
            || abi.decode(registrarData, (address)) != msg.sender) revert("CALLER");
        uint256 beforeBalance = IERC20(token).balanceOf(address(this));
        if (beforeBalance != amount) revert("FUNDING");
        permit2.approve(token, address(positions), uint160(amount), uint48(deadline));
        IERC20(token).forceApprove(address(permit2), amount);
        bool projectIs0 = token < quote;
        bytes32 parameters = bytes32((uint256(bitmap)) | (uint256(uint24(uint24(SPACING))) << 16));
        V1PoolKey memory key = V1PoolKey(
            V1Currency.wrap(projectIs0 ? token : quote), V1Currency.wrap(projectIs0 ? quote : token),
            hook, manager, FEE, parameters);
        manager.initialize(key, opening);
        positionId = positions.nextTokenId();
        uint160 lo = TickMath.getSqrtPriceAtTick(lower);
        uint160 hi = TickMath.getSqrtPriceAtTick(upper);
        uint256 liq = projectIs0
            ? LiquidityAmounts.getLiquidityForAmount0(lo, hi, amount)
            : LiquidityAmounts.getLiquidityForAmount1(lo, hi, amount);
        require(liq != 0 && liq <= type(uint128).max, "LIQUIDITY");
        bytes[] memory p = new bytes[](2);
        p[0] = abi.encode(key, lower, upper, uint128(liq),
            uint128(projectIs0 ? amount : 0), uint128(projectIs0 ? 0 : amount), lock, bytes(""));
        p[1] = abi.encode(key.currency0, key.currency1);
        positions.modifyLiquidities(abi.encode(hex"020d", p), deadline);
        permit2.approve(token, address(positions), 0, 0);
        IERC20(token).forceApprove(address(permit2), 0);
        uint256 residue = IERC20(token).balanceOf(address(this));
        if (residue != 0) {
            // Infinity position minting can round liquidity down by a few
            // units. Return that remainder to the launchpad rather than
            // leaving an unrecoverable balance on the bootstrapper.
            IERC20(token).safeTransfer(msg.sender, residue);
        }
        if (IERC20(token).balanceOf(address(this)) != 0) revert("RESIDUE");
        pid = keccak256(abi.encode(key));
    }
}