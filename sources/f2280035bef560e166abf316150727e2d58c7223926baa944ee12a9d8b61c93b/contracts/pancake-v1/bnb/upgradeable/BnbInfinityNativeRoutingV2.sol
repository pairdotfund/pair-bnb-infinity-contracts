// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BnbInfinityNativeBuyExecutorUpgradeable, IWBNB, IBnbV3Router, IBnbV3Factory} from "./BnbInfinityNativeBuyExecutorUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPancakeV1InfinityBuySource} from "../../PancakeV1InfinityDeveloperBuyExecutor.sol";
import {PancakeV1PoolKey, PancakeV1Currency, IPancakeV1Hooks} from "../../PancakeV1InfinityHookTypes.sol";
import {V1PoolId} from "../../PancakeV1Interfaces.sol";

interface IBnbWithdraw { function withdraw(uint256) external; }
interface IBnbActivePolicy {
    struct Policy {uint8 mode; uint16 feeBps; address destination; uint64 effectiveAt;}
    function activePolicy(address) external view returns (Policy memory);
}

/// @notice Append-only successor for the existing standard and NFT executors.
/// Routes are owner-reviewed canonical Pancake V3 paths, at most two hops.
/// Both developer buys and selected-market trades settle fully or revert.
contract BnbInfinityNativeRoutingV2 is BnbInfinityNativeBuyExecutorUpgradeable {
    using SafeERC20 for IERC20;
    address public constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    // Appended after the complete deployed executor layout; no existing field
    // is repurposed. routeFee continues to hold the terminal fee.
    mapping(address => uint24) public bridgeFee;
    struct FundingRoute {address quote; uint24 bridge; uint24 terminal;}
    event FundingRouteConfigured(address indexed quote, uint24 bridge, uint24 terminal);
    event NativeTrade(address indexed project,address indexed quote,address indexed trader,bool buy,uint256 amountIn,uint256 amountOut);
    function nativeRoutingVersion() external pure returns(uint8) {return 2;}

    function configureFundingRoutes(FundingRoute[] calldata routes) external onlyOwner {
        if (!routesFrozen || routes.length == 0 || routes.length > 40) revert InvalidBuy();
        for (uint256 i; i<routes.length; ++i) {
            FundingRoute calldata r = routes[i];
            if (r.quote == address(0) || r.quote == WBNB || r.quote.code.length == 0
                || !_validFee(r.terminal) || (r.bridge != 0 && (!_validFee(r.bridge) || r.quote == USDT))) revert InvalidBuy();
            if (r.bridge == 0) _pool(WBNB,r.quote,r.terminal);
            else {_pool(WBNB,USDT,r.bridge); _pool(USDT,r.quote,r.terminal);}
            routeFee[r.quote] = r.terminal;
            bridgeFee[r.quote] = r.bridge;
            emit FundingRouteConfigured(r.quote,r.bridge,r.terminal);
        }
    }
    function _validFee(uint24 f) private pure returns(bool) {return f==100 || f==500 || f==2500 || f==10000;}
    function _pool(address a,address b,uint24 f) private view {
        if (IBnbV3Factory(V3_FACTORY).getPool(a,b,f).code.length==0) revert InvalidBuy();
    }
    function fundingPath(address quote,bool reverse) public view returns(bytes memory) {
        if (quote == WBNB) return abi.encodePacked(WBNB);
        uint24 terminal = routeFee[quote]; uint24 bridge = bridgeFee[quote];
        if (terminal == 0) revert InvalidBuy();
        if (bridge == 0) return reverse ? abi.encodePacked(quote,terminal,WBNB) : abi.encodePacked(WBNB,terminal,quote);
        return reverse ? abi.encodePacked(quote,terminal,USDT,bridge,WBNB) : abi.encodePacked(WBNB,bridge,USDT,terminal,quote);
    }
    function _convert(address input,address output,bytes memory path,uint256 amount,uint256 floor,uint256 deadline) private returns(uint256 received) {
        if (input == output) {if (amount<floor) revert InvalidBuy();return amount;}
        uint256 beforeInput=IERC20(input).balanceOf(address(this));
        uint256 beforeOutput=IERC20(output).balanceOf(address(this));
        IERC20(input).forceApprove(V3_ROUTER,amount);
        if(deadline<block.timestamp) revert InvalidBuy();
        received=IBnbV3Router(V3_ROUTER).exactInput(IBnbV3Router.ExactInputParams(path,address(this),deadline,amount,floor));
        IERC20(input).forceApprove(V3_ROUTER,0);
        if (received<floor || IERC20(output).balanceOf(address(this))-beforeOutput!=received
            || beforeInput-IERC20(input).balanceOf(address(this))!=amount
            || IERC20(input).allowance(address(this),V3_ROUTER)!=0) revert Residual();
    }
    function _fund(address quote,uint256 amount,uint256 floor,uint256 deadline) internal override returns(uint256) {
        return _convert(WBNB,quote,fundingPath(quote,false),amount,floor,deadline);
    }
    function _record(address project,address quote) private view returns(bytes32 id,uint256 index) {
        IPancakeV1InfinityBuySource.PoolRecord[] memory records=IPancakeV1InfinityBuySource(launchpad).pools(project);
        if (records.length==0 || records.length>5) revert InvalidBuy();
        for (uint256 i;i<records.length;++i) if(records[i].quoteToken==quote) return(V1PoolId.unwrap(records[i].poolId),i);
        revert InvalidBuy();
    }
    function _key(address project,address quote,bytes32 id) private view returns(PancakeV1PoolKey memory key) {
        bool p0=project<quote;
        key=PancakeV1PoolKey(PancakeV1Currency.wrap(p0?project:quote),PancakeV1Currency.wrap(p0?quote:project),
            IPancakeV1Hooks(address(hook)),poolManager,10000,bytes32(uint256(hook.getHooksRegistrationBitmap())|(uint256(200)<<16)));
        if (keccak256(abi.encode(key))!=id) revert InvalidBuy();
    }
    function swapNative(address project,address quote,bool buy,uint256 amountIn,uint256 minFundingOut,uint256 minOutput,uint256 deadline)
        external payable returns(uint256 amountOut,uint256 fundingOut) {
        if (!routesFrozen || entered!=0 || project==address(0) || amountIn==0 || deadline<block.timestamp
            || deadline>block.timestamp+30 minutes || (buy?msg.value!=amountIn:msg.value!=0)) revert InvalidBuy();
        entered=1;
        (bytes32 id,uint256 index)=_record(project,quote);
        uint256 wbnbBefore=IERC20(WBNB).balanceOf(address(this));
        uint256 quoteBefore=IERC20(quote).balanceOf(address(this));
        if (buy) {
            uint256 beforeProject=IERC20(project).balanceOf(msg.sender);
            IWBNB(WBNB).deposit{value:amountIn}();
            if(IERC20(WBNB).balanceOf(address(this))!=wbnbBefore+amountIn) revert Residual();
            fundingOut=_fund(quote,amountIn,minFundingOut,deadline);
            _buy(project,quote,fundingOut,msg.sender,minOutput,deadline,id,index);
            amountOut=IERC20(project).balanceOf(msg.sender)-beforeProject;
        } else {
            uint256 beforeProject=IERC20(project).balanceOf(address(this));
            IERC20(project).safeTransferFrom(msg.sender,address(this),amountIn);
            if (IERC20(project).balanceOf(address(this))!=beforeProject+amountIn) revert Residual();
            IBnbActivePolicy.Policy memory policy=IBnbActivePolicy(address(hook)).activePolicy(project);
            uint256 net=amountIn;uint256 debit=amountIn;
            // Burn mode charges project-token input on sells. Other modes
            // charge the quote output, already settled by the trusted adapter.
            if(policy.mode==2) {
                net=amountIn*10000/(10000+policy.feeBps);
                debit=net+net*policy.feeBps/10000;
                if(net==0 || debit>amountIn || amountIn-debit>1) revert InvalidBuy();
                if(debit<amountIn) IERC20(project).safeTransfer(msg.sender,amountIn-debit);
            }
            IERC20(project).forceApprove(address(adapter),debit);
            adapter.executeExactInput(_key(project,quote,id),project<quote,net,debit,minFundingOut,address(this),address(this),deadline,abi.encode(uint8(1),id,index));
            IERC20(project).forceApprove(address(adapter),0);
            if(IERC20(project).balanceOf(address(this))!=beforeProject || IERC20(project).allowance(address(this),address(adapter))!=0) revert Residual();
            fundingOut=IERC20(quote).balanceOf(address(this))-quoteBefore;
            amountOut=_convert(quote,WBNB,fundingPath(quote,true),fundingOut,minOutput,deadline);
            IBnbWithdraw(WBNB).withdraw(amountOut);
            (bool sent,)=msg.sender.call{value:amountOut}("");if(!sent) revert Residual();
        }
        if(amountOut<minOutput || IERC20(WBNB).balanceOf(address(this))!=wbnbBefore || IERC20(quote).balanceOf(address(this))!=quoteBefore) revert Residual();
        entered=0;
        emit NativeTrade(project,quote,msg.sender,buy,amountIn,amountOut);
    }
    receive() external payable {if(msg.sender!=WBNB) revert InvalidBuy();}
}
