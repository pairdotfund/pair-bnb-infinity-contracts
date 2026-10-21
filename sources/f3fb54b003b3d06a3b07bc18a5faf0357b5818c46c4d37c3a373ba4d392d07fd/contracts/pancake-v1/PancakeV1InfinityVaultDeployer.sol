// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {PancakeV1CreatorFeeVault} from "./PancakeV1CreatorFeeVault.sol";
import {PancakeV1FeeSharingVault} from "./PancakeV1FeeSharingVault.sol";
contract PancakeV1InfinityVaultDeployer {
    address public immutable admin;
    address public engine;
    address public immutable hook;
    error Unauthorized();
    constructor(address admin_, address hook_) {
        require(admin_ != address(0) && hook_ != address(0));
        admin = admin_; hook = hook_;
    }
    function bindEngine(address engine_) external {
        if (msg.sender != admin || engine != address(0) || engine_ == address(0)) revert Unauthorized();
        engine = engine_;
    }
    function creator(address project,address recipient,uint16 bps) external returns(address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new PancakeV1CreatorFeeVault(project,hook,engine,recipient,bps));
    }
    function sharing(address project,PancakeV1FeeSharingVault.Recipient[] calldata r,address verifier,uint16 bps)
        external returns(address) {
        if (msg.sender != engine || engine == address(0)) revert Unauthorized();
        return address(new PancakeV1FeeSharingVault(project,hook,engine,verifier,r,bps));
    }
}