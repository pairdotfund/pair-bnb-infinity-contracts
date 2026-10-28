// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BnbInfinityNativeRoutingV2} from "../upgradeable/BnbInfinityNativeRoutingV2.sol";
import {BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable,
    IPancakeV1DirectBuyHook, IPancakeV1DirectBuyAdapter, IPancakeV1DirectBuyPermit2}
    from "../upgradeable/BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable.sol";
import {IPancakeV1CLPoolManager, IPancakeV1Hooks, PancakeV1PoolKey, PancakeV1Currency}
    from "../../PancakeV1InfinityHookTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Fresh successor graph only. Gross input is the standard router's
/// inclusive input budget, never a legacy net-pool amount plus fee funding.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityStandardNativeBuy is BnbInfinityNativeRoutingV2 {
    using SafeERC20 for IERC20;
    function standardRoutingVersion() external pure returns(uint8) { return 1; }
    function _buy(address project, address quote, uint256 gross, address recipient,
        uint256 floor, uint256 deadline, bytes32 id, uint256 index) internal override {
        bool p0 = project < quote;
        PancakeV1PoolKey memory key = PancakeV1PoolKey(
            PancakeV1Currency.wrap(p0 ? project : quote), PancakeV1Currency.wrap(p0 ? quote : project),
            IPancakeV1Hooks(address(hook)), poolManager, 10_000,
            bytes32(uint256(hook.getHooksRegistrationBitmap()) | (uint256(200) << 16)));
        if (keccak256(abi.encode(key)) != id) revert InvalidBuy();
        uint256 beforeQuote = IERC20(quote).balanceOf(address(this));
        IERC20(quote).forceApprove(address(adapter), gross);
        adapter.executeExactInput(key, !p0, gross, gross, floor, address(this), recipient, deadline,
            abi.encode(uint8(1), id, index));
        IERC20(quote).forceApprove(address(adapter), 0);
        if (beforeQuote - IERC20(quote).balanceOf(address(this)) != gross
            || IERC20(quote).allowance(address(this), address(adapter)) != 0) revert Residual();
    }
    function _sellAmounts(address, uint256 amountIn) internal pure override
        returns(uint256 net, uint256 debit) { return (amountIn, amountIn); }
}

/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityStandardDirectBuy is BnbInfinityDirectQuoteDeveloperBuyExecutorUpgradeable {
    using SafeERC20 for IERC20;
    function standardRoutingVersion() external pure returns(uint8) { return 1; }
    function _buyLeg(Leg memory leg) internal override {
        if (leg.amount > type(uint128).max || leg.minimum > type(uint128).max
            || leg.deadline > type(uint48).max || IERC20(leg.quote).balanceOf(address(this)) != 0)
            revert InvalidBuy();
        uint256 beforePayer = IERC20(leg.quote).balanceOf(leg.payer);
        uint256 beforeOutput = IERC20(leg.project).balanceOf(leg.recipient);
        IERC20(leg.quote).safeTransferFrom(leg.payer, address(this), leg.amount);
        if (IERC20(leg.quote).balanceOf(address(this)) != leg.amount
            || beforePayer - IERC20(leg.quote).balanceOf(leg.payer) != leg.amount) revert Residual(leg.quote);
        IERC20(leg.quote).forceApprove(address(adapter), leg.amount);
        adapter.executeExactInput(_key(leg.project, leg.quote), leg.project >= leg.quote,
            leg.amount, leg.amount, leg.minimum, address(this), leg.recipient, leg.deadline, "");
        IERC20(leg.quote).forceApprove(address(adapter), 0);
        if (IERC20(leg.project).balanceOf(leg.recipient) - beforeOutput < leg.minimum) revert Slippage();
        if (IERC20(leg.quote).balanceOf(address(this)) != 0
            || IERC20(leg.quote).allowance(address(this), address(adapter)) != 0) revert Residual(leg.quote);
    }
}

interface IStandardNftEntry {
    function launchInfinityNftFor(address creator, bytes calldata encoded) external payable returns(address);
}
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityStandardNftDirectBuy is BnbInfinityStandardDirectBuy {
    address public engine;
    function initializeProxy(address authority, address proxy, address module,
        IPancakeV1CLPoolManager manager, IPancakeV1DirectBuyHook hook_,
        IPancakeV1DirectBuyAdapter adapter_, IPancakeV1DirectBuyPermit2 permit2_) external initializer {
        _initializeDirectQuote(authority, proxy, manager, hook_, adapter_, permit2_);
        if (module == address(0)) revert InvalidBuy();
        engine = module;
    }
    function launchAndBuy(bytes calldata launchData, bytes calldata encodedPlan)
        external payable override returns(address project) {
        project = IStandardNftEntry(launchpad).launchInfinityNftFor{value: msg.value}(msg.sender, launchData);
        this.execute(project, msg.sender, encodedPlan);
    }
}
