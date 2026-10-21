// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PancakeV1InfinityLaunchEngine} from "../PancakeV1InfinityLaunchEngine.sol";
import {PancakeV1FeeSharingVault} from "../PancakeV1FeeSharingVault.sol";
import {V1PoolId} from "../PancakeV1Interfaces.sol";
import {IInfinityNftModule} from "../PancakeV1LaunchpadInfinityNftUpgradeable.sol";

interface IBnbGraph {
    function launchpad() external view returns (address);
    function engine() external view returns (address);
}

/// @notice Fresh BNB UUPS entrypoint, NOT an upgrade for a Robinhood proxy.
/// Standard and upgradeable NFT rewards share this entrypoint and protocol vault.
/// No no-hook, V1/V2, oracle, USDG, or Robinhood entrypoints are inherited.
contract BnbInfinityLaunchpad is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    struct PoolRecord {
        address quoteToken; uint16 weightBps; V1PoolId poolId; uint256 positionId;
        uint256 projectAmount; int24 tickLower; int24 tickUpper; uint256 quotePriceE8; uint8 quoteDecimals;
    }
    struct Allocation { address quoteToken; uint16 weightBps; }
    struct Params {
        bytes identityData; Allocation[] allocations; bytes[] openingData;
        uint256 deadline; bytes32 userSalt; bool sniperProtection; uint256 protectionBlocks;
        uint8 mode; uint16 feeBps; bytes modeData; uint64 policyEffectiveAt; address[] holderExcluded;
    }

    mapping(address => PoolRecord[]) private _pools;
    uint256 public launchFee;
    address public launchFeeRecipient;
    address public socialVerifier;
    address public infinityEngine;
    IInfinityNftModule public nftModule;
    address public directQuoteCoordinator;
    address public nftDirectQuoteCoordinator;
    bool public graphFrozen;
    bool public paused;
    uint256 private _entered;

    error InvalidConfiguration();
    error Unavailable();
    event GraphFrozen(address engine, address nftModule);
    event PauseChanged(bool paused);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }
    function initialize(address admin, address treasury, address verifier, uint256 fee) external initializer {
        if (block.chainid != 56 || admin == address(0) || treasury == address(0)
            || verifier == address(0)) revert InvalidConfiguration();
        __Ownable_init(admin);
        launchFee = fee; launchFeeRecipient = treasury; socialVerifier = verifier;
        paused = true;
    }
    function _authorizeUpgrade(address) internal override onlyOwner {}
    function poolManager() external pure returns (address) {
        return 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    }
    function pools(address token) external view returns (PoolRecord[] memory) { return _pools[token]; }

    /// Bind only after reciprocal factory/hook/adapters have been frozen.
    function finalizeGraph(address engine, IInfinityNftModule module,
        address direct, address nftDirect) external onlyOwner {
        if (graphFrozen || engine.code.length == 0
            || !PancakeV1InfinityLaunchEngine(engine).validateLaunchpad(address(this))
            || direct.code.length == 0 || IBnbGraph(direct).launchpad() != address(this))
            revert InvalidConfiguration();
        if (address(module) != address(0)) {
            if (address(module).code.length == 0 || module.launchpad() != address(this)
                || nftDirect.code.length == 0 || IBnbGraph(nftDirect).launchpad() != address(this)
                || IBnbGraph(nftDirect).engine() != address(module)) revert InvalidConfiguration();
        } else if (nftDirect != address(0)) revert InvalidConfiguration();
        infinityEngine = engine; nftModule = module; directQuoteCoordinator = direct;
        nftDirectQuoteCoordinator = nftDirect; graphFrozen = true;
        emit GraphFrozen(engine, address(module));
    }
    function setPaused(bool value) external onlyOwner {
        if (!value && !graphFrozen) revert InvalidConfiguration();
        paused = value; emit PauseChanged(value);
    }
    modifier available() {
        if (paused || !graphFrozen || _entered != 0) revert Unavailable();
        _entered = 1; _; _entered = 0;
    }
    function _validate(bytes memory encoded) private view returns (uint8 mode) {
        Params memory p = abi.decode(encoded, (Params));
        if (keccak256(encoded) != keccak256(abi.encode(p)) || p.mode > 5
            || p.sniperProtection || p.protectionBlocks != 0 || p.policyEffectiveAt != 0
            || p.deadline < block.timestamp || p.deadline > type(uint48).max)
            revert InvalidConfiguration();
        if (p.mode == 3) {
            (, address verifier) = abi.decode(p.modeData, (PancakeV1FeeSharingVault.Recipient[], address));
            if (verifier != socialVerifier) revert InvalidConfiguration();
        }
        if (p.mode == 5 && address(nftModule) == address(0)) revert Unavailable();
        return p.mode;
    }
    function launchInfinity(bytes calldata encoded) external payable available returns (address token) {
        token = _launch(msg.sender, encoded);
    }
    function launchInfinityFor(address creator, bytes calldata encoded)
        external payable available returns (address token) {
        if (msg.sender != directQuoteCoordinator || creator == address(0) || _validate(encoded) == 5)
            revert InvalidConfiguration();
        token = _launch(creator, encoded);
    }
    function launchInfinityNftFor(address creator, bytes calldata encoded)
        external payable available returns (address token) {
        if (msg.sender != nftDirectQuoteCoordinator || creator == address(0) || _validate(encoded) != 5)
            revert InvalidConfiguration();
        token = _launch(creator, encoded);
    }
    function _launch(address creator, bytes memory encoded) private returns (address token) {
        if (_validate(encoded) == 5) return nftModule.launch{value: msg.value}(creator, encoded);
        return PancakeV1InfinityLaunchEngine(infinityEngine).launch{value: msg.value}(creator, encoded);
    }
    function launchInfinityAndBuy(bytes calldata encoded)
        external payable available returns (address token, uint256 output) {
        (bytes memory launchData,) = abi.decode(encoded, (bytes, bytes));
        // Buy-only operation is deliberately not a launch entrypoint.
        if (launchData.length == 0) revert InvalidConfiguration();
        if (_validate(launchData) == 5) return nftModule.launchAndBuy{value: msg.value}(msg.sender, encoded);
        return PancakeV1InfinityLaunchEngine(infinityEngine).launchAndBuy{value: msg.value}(msg.sender, encoded);
    }
    function recordInfinityPool(address token, address quote, bytes32 id, uint16 weight) external {
        if (msg.sender != infinityEngine || _entered == 0 || _pools[token].length >= 5)
            revert InvalidConfiguration();
        _pools[token].push(PoolRecord(quote, weight, V1PoolId.wrap(id), 0, 0, 0, 0, 0, 0));
    }
    function releaseInfinityNftSupply(address project) external {
        if (msg.sender != address(nftModule) || _entered == 0 || !nftModule.validateSupply(project))
            revert InvalidConfiguration();
        uint256 amount = 1_000_000_000 ether;
        if (IERC20(project).balanceOf(address(this)) != amount || IERC20(project).totalSupply() != amount)
            revert InvalidConfiguration();
        IERC20(project).safeTransfer(msg.sender, amount);
    }
    function recordInfinityNftPool(address project, address quote, bytes32 id, uint16 weight,
        uint256 positionId, uint256 amount, int24 lower, int24 upper, uint256 price, uint8 decimals) external {
        if (msg.sender != address(nftModule) || _entered == 0 || _pools[project].length >= 5
            || !nftModule.validatePool(project, quote, id, weight, positionId, amount, lower, upper, price, decimals))
            revert InvalidConfiguration();
        _pools[project].push(PoolRecord(quote, weight, V1PoolId.wrap(id), positionId, amount, lower, upper, price, decimals));
    }
}
