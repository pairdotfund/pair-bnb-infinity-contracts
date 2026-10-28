// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BnbInfinityStandardHook} from "./BnbInfinityStandardHook.sol";
import {IPancakeV1CLPoolManager} from "../../PancakeV1InfinityHookTypes.sol";

interface IStandardNftRewards { function rewardsActive() external view returns (bool); }

/// @notice Same permissionless Infinity accounting; NFT fees activate only after
/// the collection enables rewards. No post-registration NFT policy amendment.
contract BnbInfinityStandardNftHook is BnbInfinityStandardHook {
    constructor(IPancakeV1CLPoolManager manager_, address admin, address protocol_)
        BnbInfinityStandardHook(manager_, admin, protocol_) {}

    function schedulePolicy(address project, FeeMode mode, uint16 feeBps, address destination,
        uint64 effectiveAt) external override returns (uint64) {
        if (!frozen || msg.sender != registrar) revert Unauthorized();
        if (mode != FeeMode.NFT_QUOTE || tokenStates[project].currentEpoch != 0 || effectiveAt != 0)
            revert InvalidPolicy();
        return _schedulePolicy(project, mode, feeBps, destination, effectiveAt);
    }

    function effectiveFeeBps(address project) external view returns (uint16) {
        return _feePolicy(project).feeBps;
    }

    function _feePolicy(address project) internal view override returns (Policy memory p) {
        p = activePolicy(project);
        if (p.destination == address(0)) revert InvalidPolicy();
        if (!IStandardNftRewards(p.destination).rewardsActive()) p.feeBps = 0;
    }
}
