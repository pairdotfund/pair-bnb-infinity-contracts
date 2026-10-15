// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PancakeV1HolderDistributionVault} from "./PancakeV1HolderDistributionVault.sol";

/// @notice Non-upgradeable holder-mode token. The launch factory binds its
/// vault once, then mints the fixed supply; every later balance change is
/// checkpointed before ERC20 state changes.
contract PancakeV1HolderToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    address public immutable launchpad;
    address public immutable factory;
    address public immutable mintRecipient;
    address public immutable poolManager;
    address public immutable positionManager;
    address public immutable locker;
    address public immutable initialBuyRecipient;
    uint256 public immutable launchBlock;
    uint256 public immutable restrictionsEndBlock;
    string private _metadataURI;
    bytes32 public immutable metadataHash;
    PancakeV1HolderDistributionVault public holderVault;
    bool public minted;

    error InvalidConfiguration();
    error VaultAlreadyBound();
    error OnlyLaunchpad();
    error LaunchBlockRestricted();
    error BuyCapExceeded();
    error HoldCapExceeded();

    constructor(
        string memory name_,
        string memory symbol_,
        string memory metadataURI_,
        bytes32 metadataHash_,
        address launchpad_,
        address poolManager_,
        address positionManager_,
        address locker_,
        address initialBuyRecipient_,
        address mintRecipient_,
        uint256 protectionBlocks_
    ) ERC20(name_, symbol_) {
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0 || launchpad_ == address(0)
            || poolManager_ == address(0) || positionManager_ == address(0) || locker_ == address(0)) {
            revert InvalidConfiguration();
        }
        launchpad = launchpad_;
        factory = msg.sender;
        mintRecipient = mintRecipient_;
        poolManager = poolManager_;
        positionManager = positionManager_;
        locker = locker_;
        initialBuyRecipient = initialBuyRecipient_;
        launchBlock = block.number;
        restrictionsEndBlock = block.number + protectionBlocks_;
        _metadataURI = metadataURI_;
        metadataHash = metadataHash_;
    }

    function metadataURI() external view returns (string memory) { return _metadataURI; }
    function tokenURI() external view returns (string memory) { return _metadataURI; }

    function bindVaultAndMint(PancakeV1HolderDistributionVault vault_) external {
        if (msg.sender != launchpad && msg.sender != factory) revert OnlyLaunchpad();
        if (minted || address(vault_) == address(0) || vault_.projectToken() != address(this)) {
            revert VaultAlreadyBound();
        }
        holderVault = vault_;
        minted = true;
        _mint(mintRecipient, TOTAL_SUPPLY);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (address(holderVault) == address(0)) revert InvalidConfiguration();
        holderVault.checkpoint(from, to, value);
        if (restrictionsEndBlock > launchBlock && block.number <= restrictionsEndBlock && from != address(0) && to != address(0)
            && to != poolManager && to != positionManager && to != locker && to != launchpad) {
            if (from == poolManager) {
                if (block.number == launchBlock && to != initialBuyRecipient) revert LaunchBlockRestricted();
                if (value > 55_000_000 ether) revert BuyCapExceeded();
            }
            if (balanceOf(to) + value > 50_000_000 ether) revert HoldCapExceeded();
        }
        super._update(from, to, value);
    }
}