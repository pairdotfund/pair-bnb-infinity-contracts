// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    PancakeV1Currency,
    PancakeV1BalanceDelta,
    PancakeV1PoolKey,
    IPancakeV1CLPoolManager,
    IPancakeV1Vault,
    IPancakeV1LockCallback
} from "../PancakeV1InfinityHookTypes.sol";
import {V1PoolId} from "../PancakeV1Interfaces.sol";

contract PancakeV1InfinityAdapterMockToken is ERC20 {
    constructor(string memory name_) ERC20(name_, name_) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}
contract PancakeV1InfinityAdapterMockToken6 is ERC20 {
    constructor(string memory name_) ERC20(name_, name_) {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract PancakeV1InfinityAdapterMockHook {
    function getHooksRegistrationBitmap() external pure returns (uint16) { return 3264; }
    function quoteInputFee(address, uint256) external pure returns (uint256) { return 0; }
    function settle(address adapter, address asset, address destination, uint256 amount) external {
        (bool ok,) = adapter.call(abi.encodeWithSignature(
            "settleHookFee(address,address,uint256)", asset, destination, amount
        ));
        require(ok);
    }
    function settleUnspecifiedFee() external {}
}

contract PancakeV1InfinityAdapterMockVault is IPancakeV1Vault {
    address public manager;
    address public currencyA;
    address public currencyB;
    address public synced;
    address[] public setters;
    mapping(address => mapping(address => bool)) public active;
    uint256 public activeCount;
    mapping(address => mapping(address => int256)) public deltas;
    mapping(address => uint256) public reserves;
    constructor() {}
    function setManager(address manager_) external { require(manager == address(0)); manager = manager_; }
    function lock(bytes calldata data) external returns (bytes memory) {
        return IPancakeV1LockCallback(msg.sender).lockAcquired(data);
    }
    function currencyDelta(address settler, PancakeV1Currency currency)
        external view returns (int256) {
        return deltas[settler][PancakeV1Currency.unwrap(currency)];
    }
    function setDelta(address settler, address currency, int256 value) external {
        require(msg.sender == manager);
        _setDelta(settler, currency, value);
    }
    function adjustDelta(address settler, address currency, int256 change) external {
        require(msg.sender == manager);
        _setDelta(settler, currency, deltas[settler][currency] + change);
    }
    function fundOutput(address currency, uint256 amount) external {
        require(msg.sender == manager);
        PancakeV1InfinityAdapterMockToken(currency).mint(address(this), amount);
        reserves[currency] += amount;
    }
    function _setDelta(address settler, address currency, int256 value) private {
        if (!active[settler][currency] && value != 0) {
            active[settler][currency] = true;
            ++activeCount;
            setters.push(settler);
        }
        if (active[settler][currency] && value == 0) {
            active[settler][currency] = false;
            --activeCount;
        }
        if (currencyA == address(0)) currencyA = currency;
        else if (currencyB == address(0) && currency != currencyA) currencyB = currency;
        deltas[settler][currency] = value;
    }
    function netHook(address hook, address currency, address destination, uint256 amount) external {
        require(msg.sender == manager);
        require(deltas[hook][currency] >= int256(amount) && reserves[currency] >= amount);
        _setDelta(hook, currency, deltas[hook][currency] - int256(amount));
        reserves[currency] -= amount;
        PancakeV1InfinityAdapterMockToken(currency).transfer(destination, amount);
    }
    function getUnsettledDeltasCount() external view returns (uint256 count) {
        // The production Vault performs this check against transient storage.
        // Tests assert the persistent mirror through allDeltasZero().
        count;
        return 0;
    }
    function allDeltasZero() external view returns (bool) {
        for (uint256 i; i < setters.length; ++i) {
            if (deltas[setters[i]][currencyA] != 0 || deltas[setters[i]][currencyB] != 0) return false;
        }
        return true;
    }
    function sync(PancakeV1Currency currency) external { synced = PancakeV1Currency.unwrap(currency); }
    function settleFor(address recipient) external payable returns (uint256 paid) {
        uint256 balance = IERC20(synced).balanceOf(address(this));
        paid = balance - reserves[synced];
        reserves[synced] = balance;
        _setDelta(recipient, synced, deltas[recipient][synced] + int256(paid));
    }
    function take(PancakeV1Currency currency, address to, uint256 amount) external {
        address c = PancakeV1Currency.unwrap(currency);
        require(deltas[msg.sender][c] >= int256(amount) && reserves[c] >= amount);
        _setDelta(msg.sender, c, deltas[msg.sender][c] - int256(amount));
        reserves[c] -= amount;
        PancakeV1InfinityAdapterMockToken(c).transfer(to, amount);
    }
    function _clear(address settler, address currency) private {
        if (active[settler][currency]) {
            active[settler][currency] = false;
            --activeCount;
        }
        deltas[settler][currency] = 0;
    }
}

contract PancakeV1InfinityAdapterMockManager is IPancakeV1CLPoolManager {
    address public immutable vaultAddress;
    address public immutable output;
    address public immutable hookAddress;
    constructor(address vault_, address output_, address hook_) {
        vaultAddress = vault_;
        output = output_;
        hookAddress = hook_;
    }
    function vault() external view returns (address) { return vaultAddress; }
    function getSlot0(bytes32) external pure returns (uint160, int24, uint24, uint24) {
        return (1 << 96, 0, 0, 0);
    }
    function swap(PancakeV1PoolKey calldata key, SwapParams calldata params, bytes calldata)
        external returns (PancakeV1BalanceDelta) {
        address input = params.zeroForOne
            ? PancakeV1Currency.unwrap(key.currency0) : PancakeV1Currency.unwrap(key.currency1);
        address out = params.zeroForOne
            ? PancakeV1Currency.unwrap(key.currency1) : PancakeV1Currency.unwrap(key.currency0);
        uint256 principal = uint256(params.amountSpecified < 0
            ? -params.amountSpecified : params.amountSpecified);
        uint256 fee = principal * 30 / 10_000;
        PancakeV1InfinityAdapterMockVault(vaultAddress).adjustDelta(
            msg.sender, input, -int256(principal));
        PancakeV1InfinityAdapterMockHook(hookAddress).settle(
            msg.sender, input, address(0x0000000000000000000000000000000000000002), fee);
        PancakeV1InfinityAdapterMockVault(vaultAddress).fundOutput(out, principal);
        PancakeV1InfinityAdapterMockVault(vaultAddress).adjustDelta(msg.sender, out, int256(principal));
        return PancakeV1BalanceDelta.wrap(0);
    }
}

contract PancakeV1DirectBuyMockLaunchpad {
    struct PoolRecord {
        address quoteToken; uint16 weightBps; V1PoolId poolId; uint256 positionId;
        uint256 projectAmount; int24 tickLower; int24 tickUpper; uint256 quotePriceE8; uint8 quoteDecimals;
    }
    mapping(address => PoolRecord[]) private _pools;
    address public immutable project;
    address public coordinator;
    constructor(address project_) { project = project_; }
    function setCoordinator(address coordinator_) external { require(coordinator == address(0)); coordinator = coordinator_; }
    function setPool(address project_, address quote, bytes32 poolId, uint16 weight) external {
        _pools[project_].push(PoolRecord(quote, weight, V1PoolId.wrap(poolId), 0, 0, 0, 0, 0, 0));
    }
    function pools(address project_) external view returns (PoolRecord[] memory) { return _pools[project_]; }
    function launchInfinityFor(address creator, bytes calldata) external payable returns (address) {
        require(msg.sender == coordinator && creator != address(0));
        return project;
    }
    function callExecute(address executor, address payer, bytes calldata plan) external {
        (bool ok, bytes memory data) = executor.call(
            abi.encodeWithSignature("execute(address,address,bytes)", project, payer, plan)
        );
        if (!ok) assembly { revert(add(data, 32), mload(data)) }
    }
}

contract PancakeV1DirectBuyMockPermit2 {
    function approve(address, address, uint160, uint48) external {}
}

contract PancakeV1DirectBuyMockRouter {
    struct PoolKey { address currency0; address currency1; address hooks; address poolManager; uint24 fee; bytes32 parameters; }
    struct SwapParams { PoolKey poolKey; bool zeroForOne; uint128 amountIn; uint128 amountOutMinimum; bytes hookData; }
    function execute(bytes calldata, bytes[] calldata inputs, uint256) external {
        (, bytes[] memory actions) = abi.decode(inputs[0], (bytes, bytes[]));
        SwapParams memory p = abi.decode(actions[0], (SwapParams));
        address input = p.zeroForOne ? p.poolKey.currency0 : p.poolKey.currency1;
        (address output, uint256 minimum) = abi.decode(actions[actions.length - 1], (address, uint256));
        IERC20(input).transferFrom(msg.sender, address(this), p.amountIn);
        require(p.amountIn >= minimum);
        PancakeV1InfinityAdapterMockToken(output).mint(msg.sender, p.amountIn);
    }

    function executeExactInput(
        PancakeV1PoolKey calldata key,
        bool zeroForOne,
        uint256 amountIn,
        uint256 inputMaximum,
        uint256 amountOutMinimum,
        address payer,
        address recipient,
        uint256,
        bytes calldata
    ) external returns (uint256 amountOut) {
        address input = zeroForOne
            ? PancakeV1Currency.unwrap(key.currency0)
            : PancakeV1Currency.unwrap(key.currency1);
        address output = zeroForOne
            ? PancakeV1Currency.unwrap(key.currency1)
            : PancakeV1Currency.unwrap(key.currency0);
        IERC20(input).transferFrom(payer, address(this), inputMaximum);
        require(amountIn >= amountOutMinimum);
        PancakeV1InfinityAdapterMockToken(output).mint(recipient, amountIn);
        return amountIn;
    }
}