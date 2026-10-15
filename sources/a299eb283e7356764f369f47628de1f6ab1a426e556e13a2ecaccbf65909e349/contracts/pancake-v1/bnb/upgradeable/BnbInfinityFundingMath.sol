// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IBnbFundingFeeHook {
    function quoteInputFee(address project, uint256 net) external view returns (uint256);
}

library BnbInfinityFundingMath {
    error UnrepresentableFunding();

    /// @dev Net + two separately floored fees can skip one or two raw units.
    /// Resolve an exact representable debit; the caller refunds only the
    /// arithmetic remainder BEFORE execution and still requires full execution.
    function resolve(uint256 gross, address hook, address project)
        internal view returns (uint256 net, uint256 debit)
    {
        if (gross == 0) revert UnrepresentableFunding();
        net = gross;
        uint256 previous = type(uint256).max;
        for (uint256 i; i < 256; ++i) {
            uint256 fee = IBnbFundingFeeHook(hook).quoteInputFee(project, net);
            if (fee >= gross) revert UnrepresentableFunding();
            uint256 next = gross - fee;
            if (next == net) break;
            if (next == previous) {
                net = next < net ? next : net;
                break;
            }
            previous = net;
            net = next;
        }
        debit = net + IBnbFundingFeeHook(hook).quoteInputFee(project, net);
        if (net == 0 || debit > gross || gross - debit > 2) revert UnrepresentableFunding();
    }
}
