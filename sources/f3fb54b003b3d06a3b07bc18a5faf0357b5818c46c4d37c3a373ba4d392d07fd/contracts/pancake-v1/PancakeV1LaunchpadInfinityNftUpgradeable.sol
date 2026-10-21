// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IInfinityNftModule {
    function launchpad() external view returns (address);
    function hook() external view returns (address);
    function factory() external view returns (address);
    function launch(address creator, bytes calldata encoded) external payable returns (address token);
    function launchAndBuy(address creator, bytes calldata encoded) external payable returns (address token, uint256 output);
    function validatePool(address project, address quote, bytes32 id, uint16 weight,
        uint256 positionId, uint256 projectAmount, int24 lower, int24 upper,
        uint256 quotePriceE8, uint8 quoteDecimals) external view returns (bool);
    function validateSupply(address project) external view returns (bool);
}

interface IInfinityNftCoordinator {
    function launchpad() external view returns (address);
    function engine() external view returns (address);
}

/// @notice Thin UUPS dispatcher installed at the EXISTING launchpad proxy.
/// Legacy selectors delegatecall the PINNED prior implementation, retaining
/// its exact behavior/storage. NFT calls use ordinary calls to a new module.
/// @dev Pin the prior runtime and validate its exact layout before deployment:
/// slot 9 is _pools; slot 0x39 is _infinityEngine. No new storage is appended.
contract PancakeV1LaunchpadInfinityNftUpgradeable is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    address public immutable legacyImplementation;
    IInfinityNftModule public immutable nftModule;
    address public immutable nftDirectQuoteCoordinator;
    error InvalidNftRoute();

    constructor(address expectedProxy, address legacy, bytes32 legacyCodeHash,
        IInfinityNftModule module_, address coordinator)
    {
        if (expectedProxy.code.length == 0 || legacy.codehash != legacyCodeHash
            || legacyCodeHash == bytes32(0) || legacy == expectedProxy
            || address(module_).code.length == 0 || module_.launchpad() != expectedProxy
            || module_.hook() == address(0) || module_.factory() == address(0)
            || coordinator.code.length == 0
            || IInfinityNftCoordinator(coordinator).launchpad() != expectedProxy
            || IInfinityNftCoordinator(coordinator).engine() != address(module_))
            revert InvalidNftRoute();
        legacyImplementation = legacy;
        nftModule = module_;
        nftDirectQuoteCoordinator = coordinator;
        _disableInitializers();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function _mode(bytes calldata encoded) private pure returns (uint256 mode) {
        if (encoded.length < 13 * 32) revert InvalidNftRoute();
        uint256 head;
        assembly { head := calldataload(encoded.offset) }
        if (head % 32 != 0 || head > encoded.length - 12 * 32) revert InvalidNftRoute();
        assembly { mode := calldataload(add(add(encoded.offset, head), 224)) }
    }

    function launchInfinity(bytes calldata encoded) external payable returns (address token) {
        uint256 mode = _mode(encoded);
        if (mode == 5) return nftModule.launch{value: msg.value}(msg.sender, encoded);
        if (mode > 4) revert InvalidNftRoute();
        _delegateLegacy();
    }

    function launchInfinityAndBuy(bytes calldata encoded) external payable {
        (bytes memory launchData, bytes memory buyPlan) = abi.decode(encoded, (bytes, bytes));
        // A buy-only call (empty launchData) is a legacy path.
        if (launchData.length != 0) {
            if (launchData.length < 13 * 32) revert InvalidNftRoute();
            uint256 mode;
            uint256 head;
            assembly { head := mload(add(launchData, 32)) }
            if (head % 32 != 0 || head > launchData.length - 12 * 32) revert InvalidNftRoute();
            assembly { mode := mload(add(add(launchData, 32), add(head, 224))) }
            if (mode == 5) {
                if (keccak256(encoded) != keccak256(abi.encode(launchData, buyPlan)))
                    revert InvalidNftRoute();
                nftModule.launchAndBuy{value: msg.value}(msg.sender, encoded);
                return;
            }
            if (mode > 4) revert InvalidNftRoute();
        }
        _delegateLegacy();
    }

    function launchInfinityNftFor(address creator, bytes calldata encoded)
        external payable returns (address token)
    {
        if (msg.sender != nftDirectQuoteCoordinator || creator == address(0)
            || _mode(encoded) != 5) revert InvalidNftRoute();
        token = nftModule.launch{value: msg.value}(creator, encoded);
    }

    /// @dev New factory mints project supply to the existing proxy because
    /// project tokens are permanently bound to that launchpad address.
    function releaseInfinityNftSupply(address project) external {
        if (msg.sender != address(nftModule) || project == address(0)
            || !nftModule.validateSupply(project)) revert InvalidNftRoute();
        IERC20 token = IERC20(project);
        uint256 supply = 1_000_000_000 ether;
        if (token.balanceOf(address(this)) != supply || token.totalSupply() != supply)
            revert InvalidNftRoute();
        token.safeTransfer(msg.sender, supply);
    }

    /// @dev Keccak mapping layout copied from the compiler-verified deployed
    /// predecessor. Only the pinned NFT module can append, and only after its
    /// registered actual manager PoolKey and factory collection checks pass.
    function recordInfinityNftPool(address project, address quote, bytes32 id, uint16 weight,
        uint256 positionId, uint256 projectAmount, int24 lower, int24 upper,
        uint256 quotePriceE8, uint8 quoteDecimals) external
    {
        if (msg.sender != address(nftModule) || project == address(0)
            || quote == address(0) || id == bytes32(0) || weight == 0 || positionId == 0
            || projectAmount == 0 || lower >= upper
            || !nftModule.validatePool(project, quote, id, weight,
                positionId, projectAmount, lower, upper, quotePriceE8, quoteDecimals))
            revert InvalidNftRoute();
        bytes32 arraySlot = keccak256(abi.encode(project, uint256(9)));
        uint256 ticks = uint256(uint24(lower)) | (uint256(uint24(upper)) << 24);
        assembly {
            let length := sload(arraySlot)
            // Five markets maximum. All destinations are fresh storage.
            if iszero(lt(length, 5)) { revert(0, 0) }
            sstore(arraySlot, add(length, 1))
            mstore(0, arraySlot)
            let base := add(keccak256(0, 32), mul(length, 7))
            sstore(base, or(shl(160, weight), quote))
            sstore(add(base, 1), id)
            sstore(add(base, 2), positionId)
            sstore(add(base, 3), projectAmount)
            sstore(add(base, 4), ticks)
            sstore(add(base, 5), quotePriceE8)
            sstore(add(base, 6), quoteDecimals)
        }
    }

    fallback() external payable { _delegateLegacy(); }
    receive() external payable { _delegateLegacy(); }

    function _delegateLegacy() private {
        address target = legacyImplementation;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}