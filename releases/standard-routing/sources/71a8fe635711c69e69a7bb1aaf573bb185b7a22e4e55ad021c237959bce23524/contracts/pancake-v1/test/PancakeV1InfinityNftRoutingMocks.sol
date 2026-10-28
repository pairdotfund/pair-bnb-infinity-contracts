// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract PancakeV1InfinityRoutingDecoder {
    struct Allocation { address quote; uint16 weight; }
    struct Params {
        bytes identity; Allocation[] allocations; bytes[] opening; uint256 deadline;
        bytes32 salt; bool protection; uint256 protectionBlocks; uint8 mode;
        uint16 fee; bytes modeData; uint64 policyAt; address[] excluded;
    }
    function _decode(bytes calldata encoded) internal pure returns (uint8) {
        Params memory p = abi.decode(encoded, (Params));
        return p.mode;
    }
}
contract PancakeV1InfinityRoutingLegacy is OwnableUpgradeable, UUPSUpgradeable, PancakeV1InfinityRoutingDecoder {
    address public lastCreator;
    bytes32 public lastPayload;
    uint256 public lastValue;
    uint256 public legacyBuyCount;

    constructor() { _disableInitializers(); }
    function initialize() external initializer { __Ownable_init(msg.sender); }
    function _authorizeUpgrade(address) internal override onlyOwner {}
    function launchInfinity(bytes calldata encoded) external payable returns (address) {
        require(_decode(encoded) <= 4, "LEGACY_MODE");
        lastCreator = msg.sender;
        lastPayload = keccak256(encoded);
        lastValue = msg.value;
        return address(0x1111);
    }
    function launchInfinityAndBuy(bytes calldata encoded) external payable {
        (bytes memory launchData,) = abi.decode(encoded, (bytes, bytes));
        if (launchData.length != 0) {
            Params memory p = abi.decode(launchData, (Params));
            require(p.mode <= 4, "LEGACY_MODE");
        }
        legacyBuyCount++;
    }
    function launchInfinityFor(address creator, bytes calldata encoded) external payable returns (address) {
        require(_decode(encoded) <= 4, "LEGACY_MODE");
        lastCreator = creator;
        lastPayload = keccak256(encoded);
        return address(0x1111);
    }
}

contract PancakeV1InfinityRoutingModule is PancakeV1InfinityRoutingDecoder {
    address public immutable launchpad;
    address public immutable hook;
    address public immutable factory;
    address public lastCreator;
    bytes32 public lastPayload;
    uint256 public lastValue;
    uint256 public buyCount;
    constructor(address launchpad_) {
        launchpad = launchpad_; hook = address(0x1111); factory = address(0x2222);
    }
    function launch(address creator, bytes calldata encoded) external payable returns (address) {
        require(msg.sender == launchpad, "PROXY");
        Params memory p = abi.decode(encoded, (Params));
        require(p.mode == 5 && keccak256(encoded) == keccak256(abi.encode(p)), "NFT_MODE");
        lastCreator = creator; lastPayload = keccak256(encoded); lastValue = msg.value;
        return address(0x3333);
    }
    function launchAndBuy(address creator, bytes calldata encoded) external payable returns (address, uint256) {
        require(msg.sender == launchpad, "PROXY");
        (bytes memory launchData,) = abi.decode(encoded, (bytes, bytes));
        Params memory p = abi.decode(launchData, (Params));
        require(p.mode == 5 && keccak256(launchData) == keccak256(abi.encode(p)), "NFT_MODE");
        lastCreator = creator; lastPayload = keccak256(encoded); lastValue = msg.value;
        buyCount++;
        return (address(0x3333), 7);
    }
    function validatePool(address, address, bytes32, uint16, uint256, uint256,
        int24, int24, uint256, uint8) external view returns (bool) {
        return msg.sender == launchpad;
    }
    function validateSupply(address) external view returns (bool) {
        return msg.sender == launchpad;
    }
    function record(address project, address quote, bytes32 id, uint16 weight,
        uint256 positionId, uint256 projectAmount, int24 lower, int24 upper,
        uint256 quotePriceE8, uint8 quoteDecimals) external {
        (bool ok,) = launchpad.call(
            abi.encodeWithSignature(
                "recordInfinityNftPool(address,address,bytes32,uint16,uint256,uint256,int24,int24,uint256,uint8)",
                project, quote, id, weight, positionId, projectAmount,
                lower, upper, quotePriceE8, quoteDecimals)
        );
        require(ok, "RECORD");
    }
}

contract PancakeV1InfinityRoutingCoordinator {
    address public immutable launchpad;
    address public immutable engine;
    constructor(address proxy_, address module_) {
        launchpad = proxy_; engine = module_;
    }
    function route(address proxy_, address creator, bytes calldata encoded) external payable returns (address) {
        (bool ok, bytes memory result) = proxy_.call{value: msg.value}(
            abi.encodeWithSignature("launchInfinityNftFor(address,bytes)", creator, encoded)
        );
        require(ok, "ROUTE");
        return abi.decode(result, (address));
    }
}