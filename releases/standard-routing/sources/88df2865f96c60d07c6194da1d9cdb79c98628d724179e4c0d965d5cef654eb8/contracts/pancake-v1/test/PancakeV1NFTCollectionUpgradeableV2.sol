// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {PancakeV1NFTCollectionUpgradeable} from "../PancakeV1NFTCollectionUpgradeable.sol";

contract PancakeV1NFTCollectionUpgradeableV2 is PancakeV1NFTCollectionUpgradeable {
    function implementationVersion() external pure returns (uint256) { return 2; }
}