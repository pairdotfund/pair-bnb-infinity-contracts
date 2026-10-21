// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    PancakeV1InfinityDirectQuoteDeveloperBuyExecutor,
    IPancakeV1DirectBuyHook,
    IPancakeV1DirectBuyAdapter,
    IPancakeV1DirectBuyPermit2
} from "./PancakeV1InfinityDirectQuoteDeveloperBuyExecutor.sol";
import {IPancakeV1CLPoolManager} from "./PancakeV1InfinityHookTypes.sol";

interface IInfinityNftDirectSource {
    function launchInfinityNftFor(address creator, bytes calldata encoded)
        external payable returns (address project);
}

/// @notice Existing-proxy NFT counterpart of the authenticated direct quote
/// coordinator. Reuses the legacy exact-input adapter/route checks unchanged;
/// only its launch entrypoint differs.
contract PancakeV1InfinityNftDirectQuoteCoordinator is PancakeV1InfinityDirectQuoteDeveloperBuyExecutor {
    address public immutable engine;
    constructor(address proxy, address module, IPancakeV1CLPoolManager manager_, IPancakeV1DirectBuyHook hook_,
        IPancakeV1DirectBuyAdapter adapter_, IPancakeV1DirectBuyPermit2 permit2_)
        PancakeV1InfinityDirectQuoteDeveloperBuyExecutor(
            proxy, manager_, hook_, adapter_, permit2_
        )
    {
        if (module == address(0)) revert InvalidBuy();
        engine = module;
    }

    function launchAndBuy(bytes calldata launchData, bytes calldata encodedPlan)
        external payable override returns (address project)
    {
        project = IInfinityNftDirectSource(launchpad).launchInfinityNftFor{value: msg.value}(
            msg.sender, launchData
        );
        this.execute(project, msg.sender, encodedPlan);
    }
}