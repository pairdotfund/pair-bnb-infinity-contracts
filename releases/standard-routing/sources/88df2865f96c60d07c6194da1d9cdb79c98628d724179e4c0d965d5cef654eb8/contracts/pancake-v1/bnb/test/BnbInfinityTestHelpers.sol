// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPancakeV1CLPoolManager, IPancakeV1Vault, PancakeV1Currency, PancakeV1PoolKey} from "../../PancakeV1InfinityHookTypes.sol";
import {BnbInfinityLaunchpad} from "../BnbInfinityLaunchpad.sol";
import {PancakeV1NFTCollectionUpgradeable} from "../../PancakeV1NFTCollectionUpgradeable.sol";

contract BnbInfinityTestHelpers {
    function price(int24 tick) external pure returns (uint160) { return TickMath.getSqrtPriceAtTick(tick); }
}
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityLaunchpadV2Test is BnbInfinityLaunchpad {
    function candidateVersion() external pure returns (uint256) { return 2; }
}
/// @custom:oz-upgrades-unsafe-allow missing-initializer
contract BnbInfinityCollectionV2Test is PancakeV1NFTCollectionUpgradeable {
    function implementationVersion() external pure returns (uint256) { return 2; }
}
/// An untrusted locker that intentionally does NOT settle any hook fees.
contract BnbInfinityMaliciousLocker {
    IPancakeV1CLPoolManager public immutable manager;
    IPancakeV1Vault public immutable vault;
    constructor(IPancakeV1CLPoolManager m) { manager = m; vault = IPancakeV1Vault(m.vault()); }
    function swap(PancakeV1PoolKey calldata key, bool zeroForOne, uint256 amount, address recipient) external {
        address asset = PancakeV1Currency.unwrap(zeroForOne ? key.currency0 : key.currency1);
        require(IERC20(asset).transferFrom(msg.sender, address(this), amount));
        vault.lock(abi.encode(key, zeroForOne, amount, recipient));
    }
    function lockAcquired(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(vault));
        (PancakeV1PoolKey memory key, bool direction, uint256 amount, address recipient) =
            abi.decode(data, (PancakeV1PoolKey, bool, uint256, address));
        PancakeV1Currency input = direction ? key.currency0 : key.currency1;
        vault.sync(input);
        require(IERC20(PancakeV1Currency.unwrap(input)).transfer(address(vault), amount));
        vault.settleFor(address(this));
        manager.swap(key, IPancakeV1CLPoolManager.SwapParams(direction, -int256(amount),
            direction ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1), "");
        int256 a = vault.currencyDelta(address(this), key.currency0);
        int256 b = vault.currencyDelta(address(this), key.currency1);
        if (a > 0) vault.take(key.currency0, recipient, uint256(a));
        if (b > 0) vault.take(key.currency1, recipient, uint256(b));
        return "";
    }
    function settleHookFee(address, address, uint256) external {}
}
