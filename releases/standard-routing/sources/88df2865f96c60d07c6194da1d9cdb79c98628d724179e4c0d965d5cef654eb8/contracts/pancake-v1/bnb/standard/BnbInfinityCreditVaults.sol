// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PancakeV1CreatorFeeVault} from "../../PancakeV1CreatorFeeVault.sol";
import {PancakeV1FeeSharingVault} from "../../PancakeV1FeeSharingVault.sol";
import {PancakeV1HolderDistributionVault} from "../../PancakeV1HolderDistributionVault.sol";
import {PancakeV1NFTCollectionUpgradeable} from "../../PancakeV1NFTCollectionUpgradeable.sol";
import {BnbInfinityProtocolVault} from "../BnbInfinityProtocolVault.sol";

interface IInfinityFeeCredits {
    function pendingFee(address destination, address asset) external view returns (uint256);
    function distributeFees(address destination, address asset, uint256 maximum) external returns (uint256);
    function protocolVault() external view returns (address);
    function feeAccountingVersion() external pure returns (uint8);
}

/// @dev Accounting is credited DURING the swap, when policies and holder/NFT
/// ownership apply. Later permissionless redemption changes custody only, not
/// entitlement. No user-provided destination is used for an end-user payout.
library InfinityCreditBacking {
    function balance(address hook, address asset) internal view returns (uint256) {
        return IERC20(asset).balanceOf(address(this))
            + IInfinityFeeCredits(hook).pendingFee(address(this), asset);
    }
    function settle(address hook, address asset) internal {
        if (IInfinityFeeCredits(hook).pendingFee(address(this), asset) != 0)
            IInfinityFeeCredits(hook).distributeFees(address(this), asset, type(uint256).max);
    }
}

contract BnbInfinityCreditCreatorVault is PancakeV1CreatorFeeVault {
    constructor(address project_, address hook_, address admin_, address recipient_, uint16 fee_)
        PancakeV1CreatorFeeVault(project_, hook_, admin_, recipient_, fee_) {}
    function _backedBalance(address asset) internal view override returns (uint256) {
        return InfinityCreditBacking.balance(hook, asset);
    }
    function _beforePayout(address asset) internal override { InfinityCreditBacking.settle(hook, asset); }
}

contract BnbInfinityCreditSharingVault is PancakeV1FeeSharingVault {
    constructor(address project_, address hook_, address admin_, address verifier_,
        Recipient[] memory recipients_, uint16 fee_)
        PancakeV1FeeSharingVault(project_, hook_, admin_, verifier_, recipients_, fee_) {}
    function _backedBalance(address asset) internal view override returns (uint256) {
        return InfinityCreditBacking.balance(hook, asset);
    }
    function _beforePayout(address asset) internal override { InfinityCreditBacking.settle(hook, asset); }
}

contract BnbInfinityCreditHolderVault is PancakeV1HolderDistributionVault {
    constructor(address project_, address hook_, address registrar_, address[] memory excluded_)
        PancakeV1HolderDistributionVault(project_, hook_, registrar_, excluded_) {}
    function _backedBalance(address asset) internal view override returns (uint256) {
        return InfinityCreditBacking.balance(hook, asset);
    }
    function _beforePayout(address asset) internal override { InfinityCreditBacking.settle(hook, asset); }
}

/// @notice Deploy as the implementation for NEW collections only.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityCreditNftCollection is PancakeV1NFTCollectionUpgradeable {
    function _backedBalance(address asset) internal view override returns (uint256) {
        return InfinityCreditBacking.balance(hook, asset);
    }
    function _beforePayout(address asset) internal override { InfinityCreditBacking.settle(hook, asset); }
}

/// @notice Fresh shared protocol vault candidate, not a production upgrade.
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityCreditProtocolVault is BnbInfinityProtocolVault {
    address[] private _creditHooks;
    mapping(address => bool) public creditHook;

    function registerCreditHook(address candidate) external onlyOwner {
        if (_creditHooks.length >= 8 || creditHook[candidate]
            || (candidate != hook && !additionalHook[candidate])
            || IInfinityFeeCredits(candidate).protocolVault() != address(this)
            || IInfinityFeeCredits(candidate).feeAccountingVersion() != 2)
            revert InvalidConfiguration();
        creditHook[candidate] = true;
        _creditHooks.push(candidate);
    }
    function _backedBalance(address asset) internal view override returns (uint256 amount) {
        amount = IERC20(asset).balanceOf(address(this));
        for (uint256 i; i < _creditHooks.length; ++i)
            amount += IInfinityFeeCredits(_creditHooks[i]).pendingFee(address(this), asset);
    }
    function _beforePayout(address asset) internal override {
        for (uint256 i; i < _creditHooks.length; ++i)
            InfinityCreditBacking.settle(_creditHooks[i], asset);
    }
}
