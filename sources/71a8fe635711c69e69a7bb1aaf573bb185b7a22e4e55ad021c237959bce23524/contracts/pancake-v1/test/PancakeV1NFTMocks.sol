// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PancakeV1NFTCollection} from "../PancakeV1NFTCollection.sol";
import {PancakeV1NFTHook} from "../PancakeV1NFTHook.sol";
import {PancakeV1PoolKey,IPancakeV1CLPoolManager,PancakeV1BalanceDelta} from "../PancakeV1InfinityHookTypes.sol";
contract PancakeV1NFTMockToken is ERC20 {
    bool public fail;
    constructor() ERC20("Mock","MOCK") {}
    function mint(address to,uint256 amount) external { _mint(to,amount); }
    function setFail(bool value) external { fail=value; }
    function _update(address from,address to,uint256 amount) internal override {
        if (from != address(0) && fail) revert("HOSTILE_ASSET");
        super._update(from,to,amount);
    }
}
contract PancakeV1NFTMockHook {
    function record(address collection,address asset,uint256 amount) external {
        PancakeV1NFTCollection(collection).recordFee(asset,amount);
    }
}
contract PancakeV1NFTMockManager {
    address public vault = address(this);
    uint160 public price = 79228162514264337593543950336;
    function getSlot0(bytes32) external view returns(uint160,int24,uint24,uint24) { return(price,0,0,0); }
    function swapHook(address hook,address sender,PancakeV1PoolKey calldata key,
        IPancakeV1CLPoolManager.SwapParams calldata params,PancakeV1BalanceDelta delta) external {
        PancakeV1NFTHook(hook).beforeSwap(sender,key,params,"");
        PancakeV1NFTHook(hook).afterSwap(sender,key,params,delta,"");
    }
}
contract PancakeV1NFTMockProtocol {
    address public hook;
    mapping(address => bool) public additionalHook;
    function setHook(address h) external { hook=h; }
    function authorizeAdditionalHook(address h) external { additionalHook[h]=true; }
    uint256 public recorded;
    function recordFee(address,uint256 amount) external { recorded+=amount; }
    function recordFeeFromAdditionalHook(address,uint256 amount) external {
        require(additionalHook[msg.sender],"ONLY_ADDITIONAL_HOOK");
        recorded+=amount;
    }
}
contract PancakeV1NFTMockAdditionalProtocolHook {
    function record(address vault,address asset,uint256 amount) external {
        (bool ok,) = vault.call(abi.encodeWithSignature(
            "recordFeeFromAdditionalHook(address,uint256)",asset,amount));
        require(ok,"RECORD_FAILED");
    }
    function recordLegacy(address vault,address asset,uint256 amount) external {
        (bool ok,) = vault.call(abi.encodeWithSignature("recordFee(address,uint256)",asset,amount));
        require(ok,"RECORD_FAILED");
    }
}
contract PancakeV1NFTMockGraph {
    address public hook;
    address public factory = address(this);
    address public engine = address(this);
    mapping(address=>address) public collectionOf;
    constructor(address h) { hook=h; }
    function verifyVault(address project,uint8 mode,address collection) external view returns(bool) {
        return mode==5 && collectionOf[project]==collection;
    }
    function configure(address project,address collection,uint16 bps) external {
        collectionOf[project]=collection;
        PancakeV1NFTHook(hook).schedulePolicy(project,5,bps,collection,0);
    }
    function register(PancakeV1PoolKey calldata key,address project,address quote,uint160 threshold,bool above) external {
        PancakeV1NFTHook(hook).registerPool(key,project,quote,threshold,above);
    }
}
contract PancakeV1NFTMockSettler {
    function settleHookFee(address token,address destination,uint256 amount) external {
        PancakeV1NFTMockToken(token).mint(destination,amount);
    }
    function settle(address hook) external { PancakeV1NFTHook(hook).settleUnspecifiedFee(); }
}
contract PancakeV1NFTMockReceiver {
    bool public reject;
    bool public sawInactiveDuringCallback;
    function attempt(address nft,address token,bool reject_) external {
        reject=reject_;
        PancakeV1NFTMockToken(token).mint(address(this),100);
        PancakeV1NFTMockToken(token).approve(nft,100);
        PancakeV1NFTCollection(nft).mint(1);
    }
    function onERC721Received(address,address,uint256,bytes calldata) external returns(bytes4) {
        if(reject) revert("REJECT");
        (bool activeRead,) = msg.sender.staticcall(abi.encodeWithSignature("rewardsActive()"));
        require(!activeRead,"CALLBACK_TRADE_ENABLED");
        sawInactiveDuringCallback=true;
        (bool minted,) = msg.sender.call(abi.encodeWithSignature("mint(uint256)",1));
        require(!minted,"REENTRANT_MINT");
        return this.onERC721Received.selector;
    }
}
contract PancakeV1NFTFlashReceiver {
    address public asset;
    bool public captured;
    constructor(address asset_) { asset=asset_; }
    function onERC721Received(address,address from,uint256 id,bytes calldata) external returns(bytes4) {
        address[] memory selected=new address[](1); selected[0]=asset;
        (captured,)=msg.sender.call(abi.encodeWithSignature("claim(address[])",selected));
        PancakeV1NFTCollection(msg.sender).transferFrom(address(this),from,id);
        return this.onERC721Received.selector;
    }
}
contract PancakeV1NFTAtomicMinter {
    function mintThenFee(address nft,address token,address quote,address hook) external {
        PancakeV1NFTMockToken(token).mint(address(this),100);
        PancakeV1NFTMockToken(token).approve(nft,100);
        PancakeV1NFTCollection(nft).mint(1);
        require(PancakeV1NFTCollection(nft).rewardsActive());
        PancakeV1NFTMockToken(quote).mint(nft,123);
        PancakeV1NFTMockHook(hook).record(nft,quote,123);
    }
    function onERC721Received(address,address,uint256,bytes calldata) external pure returns(bytes4) {
        return this.onERC721Received.selector;
    }
}