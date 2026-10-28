// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice ERC721 receiver with intentionally no transfer, decrease, or
/// principal withdrawal surface. Once sent here, a position is permanent.
contract PancakeV1PermanentPositionLock {
    address public immutable positionManager;
    constructor(address manager_) { positionManager = manager_; }
    function onERC721Received(address, address, uint256, bytes calldata)
        external view returns (bytes4) {
        require(msg.sender == positionManager, "UNEXPECTED_NFT");
        return this.onERC721Received.selector;
    }
}