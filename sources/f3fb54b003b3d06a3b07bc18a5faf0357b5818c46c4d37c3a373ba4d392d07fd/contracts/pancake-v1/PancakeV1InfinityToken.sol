// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract PancakeV1InfinityToken is ERC20 {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;
    address public immutable launchpad;
    address public immutable poolManager;
    address public immutable positionManager;
    address public immutable locker;
    address public immutable initialBuyRecipient;
    uint256 public immutable launchBlock;
    uint256 public immutable restrictionsEndBlock;
    string private _metadataURI;
    bytes32 public immutable metadataHash;
    constructor(string memory n,string memory s,string memory u,bytes32 h,address lp,address pm,address pos,
        address l,address recipient,address mintTo,uint256 blocks_) ERC20(n,s) {
        launchpad=lp; poolManager=pm; positionManager=pos; locker=l; initialBuyRecipient=recipient;
        launchBlock=block.number; restrictionsEndBlock=block.number+blocks_; _metadataURI=u; metadataHash=h;
        _mint(mintTo,TOTAL_SUPPLY);
    }
    function metadataURI() external view returns(string memory){return _metadataURI;}
    function tokenURI() external view returns(string memory){return _metadataURI;}
    function _update(address from,address to,uint256 value) internal override {
        if(restrictionsEndBlock > launchBlock && block.number<=restrictionsEndBlock&&from!=address(0)&&to!=address(0)
            &&to!=poolManager&&to!=positionManager&&to!=locker&&to!=launchpad) {
            if(from==poolManager){if(block.number==launchBlock&&to!=initialBuyRecipient)revert("LAUNCH_BLOCK");if(value>55_000_000 ether)revert("BUY_CAP");}
            if(balanceOf(to)+value>50_000_000 ether)revert("HOLD_CAP");
        }
        super._update(from,to,value);
    }
}