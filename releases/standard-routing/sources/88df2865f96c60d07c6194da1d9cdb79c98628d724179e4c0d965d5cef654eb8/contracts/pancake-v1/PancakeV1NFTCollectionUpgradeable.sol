// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Per-project, individually upgradeable NFT reward custody.
/// @dev Owner authorizes upgrades ONLY; there is no owner claim or reward sweep.
contract PancakeV1NFTCollectionUpgradeable is ERC721Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant ORIGINAL_SUPPLY = 1_000_000_000 ether;
    uint256 public constant PRECISION = 1e27;
    uint256 public constant MAX_BATCH = 50;

    // Initial economic commitments remain unchanged by this implementation's upgrades.
    // UUPS governance is nevertheless trusted to approve only safe successors.
    address public projectToken;
    address public hook;
    uint256 public maxSupply;
    uint256 public tokenCost;
    uint256 public totalMinted;
    string public baseURI;
    address[] private _assets;
    mapping(address => bool) public registeredAsset;
    mapping(address => uint256) public rewardIndex;
    mapping(address => uint256) public recorded;
    mapping(address => uint256) public paid;
    mapping(address => mapping(address => uint256)) private _index;
    mapping(address => mapping(address => uint256)) private _earned;
    mapping(address => mapping(address => uint256)) private _fraction;
    bool private _minting;
    bool private _entered;

    error InvalidConfiguration();
    error OnlyHook();
    error InvalidAmount();
    error UnsupportedAsset();
    error UnsupportedTransfer();
    error NoRewards();
    error MintInProgress();
    error Reentered();
    event Minted(address indexed account, uint256 firstTokenId, uint256 quantity, uint256 projectBurned);
    event FeeRecorded(address indexed asset, uint256 amount);
    event RewardClaimed(address indexed holder, address indexed asset, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { _disableInitializers(); }

    function initialize(address project_, address hook_, string memory name_, string memory symbol_,
        uint256 maximum_, uint256 cost_, string memory uri_, address[] memory assets_, address upgradeOwner)
        external initializer
    {
        bytes memory uri = bytes(uri_);
        bytes memory suffix = bytes("/metadata/");
        if (project_.code.length == 0 || hook_.code.length == 0 || upgradeOwner == address(0)
            || maximum_ == 0 || cost_ == 0 || maximum_ > (ORIGINAL_SUPPLY - 1) / cost_
            || bytes(name_).length == 0 || bytes(name_).length > 128
            || bytes(symbol_).length == 0 || bytes(symbol_).length > 32
            || uri.length < 18 || uri.length > 256 || assets_.length == 0 || assets_.length > 5)
            revert InvalidConfiguration();
        if (keccak256(_prefix(uri, 8)) != keccak256(bytes("https://"))
            && keccak256(_prefix(uri, 7)) != keccak256(bytes("ipfs://"))) revert InvalidConfiguration();
        for (uint256 i; i < suffix.length; ++i)
            if (uri[uri.length - suffix.length + i] != suffix[i]) revert InvalidConfiguration();
        for (uint256 i; i < uri.length; ++i)
            if (uint8(uri[i]) <= 32 || uri[i] == "?" || uri[i] == "#" || uri[i] == "\\")
                revert InvalidConfiguration();
        __ERC721_init(name_, symbol_);
        __Ownable_init(upgradeOwner);
        projectToken = project_;
        hook = hook_;
        maxSupply = maximum_;
        tokenCost = cost_;
        baseURI = uri_;
        for (uint256 i; i < assets_.length; ++i) {
            address asset = assets_[i];
            if (asset.code.length == 0 || asset == project_ || registeredAsset[asset])
                revert InvalidConfiguration();
            registeredAsset[asset] = true;
            _assets.push(asset);
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
    modifier nonReentrant() {
        if (_entered) revert Reentered();
        _entered = true;
        _;
        _entered = false;
    }

    function _prefix(bytes memory value, uint256 size) private pure returns (bytes memory out) {
        out = new bytes(size);
        for (uint256 i; i < size; ++i) out[i] = value[i];
    }

    function assets() external view returns (address[] memory) { return _assets; }
    function rewardsActive() external view returns (bool) {
        if (_minting) revert MintInProgress();
        return totalMinted != 0;
    }
    function previewURI(uint256 id) public view returns (string memory) {
        if (id == 0 || id > maxSupply) revert InvalidAmount();
        return string.concat(baseURI, Strings.toString(id), ".json");
    }
    function tokenURI(uint256 id) public view override returns (string memory) {
        _requireOwned(id);
        return previewURI(id);
    }

    function mint(uint256 quantity) external nonReentrant {
        if (quantity == 0 || quantity > MAX_BATCH || quantity > maxSupply - totalMinted)
            revert InvalidAmount();
        _minting = true;
        uint256 amount = quantity * tokenCost;
        uint256 beforeDead = IERC20(projectToken).balanceOf(DEAD);
        uint256 beforeUser = IERC20(projectToken).balanceOf(msg.sender);
        IERC20(projectToken).safeTransferFrom(msg.sender, DEAD, amount);
        if (IERC20(projectToken).balanceOf(DEAD) != beforeDead + amount
            || IERC20(projectToken).balanceOf(msg.sender) != beforeUser - amount)
            revert UnsupportedTransfer();
        uint256 first = totalMinted + 1;
        for (uint256 i; i < quantity; ++i) {
            ++totalMinted;
            _safeMint(msg.sender, totalMinted);
        }
        _minting = false;
        emit Minted(msg.sender, first, quantity, amount);
    }

    function recordFee(address asset, uint256 amount) external nonReentrant {
        if (msg.sender != hook) revert OnlyHook();
        if (!registeredAsset[asset]) revert UnsupportedAsset();
        if (_minting || totalMinted == 0 || amount == 0) revert InvalidAmount();
        uint256 next = recorded[asset] + amount;
        if (_backedBalance(asset) < next - paid[asset])
            revert UnsupportedTransfer();
        recorded[asset] = next;
        rewardIndex[asset] += Math.mulDiv(amount, PRECISION, totalMinted);
        emit FeeRecorded(asset, amount);
    }
    function claimable(address holder, address asset) public view returns (uint256) {
        if (!registeredAsset[asset]) revert UnsupportedAsset();
        uint256 delta = rewardIndex[asset] - _index[holder][asset];
        uint256 weight = holder == address(0) ? 0 : balanceOf(holder);
        return _earned[holder][asset] + Math.mulDiv(weight, delta, PRECISION)
            + (mulmod(weight, delta, PRECISION) + _fraction[holder][asset]) / PRECISION;
    }
    function _checkpoint(address holder) private {
        if (holder == address(0)) return;
        uint256 weight = balanceOf(holder);
        for (uint256 i; i < _assets.length; ++i) {
            address asset = _assets[i];
            uint256 index = rewardIndex[asset];
            uint256 delta = index - _index[holder][asset];
            uint256 fraction = mulmod(weight, delta, PRECISION) + _fraction[holder][asset];
            _earned[holder][asset] += Math.mulDiv(weight, delta, PRECISION) + fraction / PRECISION;
            _fraction[holder][asset] = fraction % PRECISION;
            _index[holder][asset] = index;
        }
    }
    function _update(address to, uint256 id, address auth) internal override returns (address from) {
        from = _ownerOf(id);
        if (_minting && from != address(0)) revert MintInProgress();
        if (to == address(0) || to == DEAD || to == address(this)) revert InvalidConfiguration();
        _checkpoint(from);
        if (to != from) _checkpoint(to);
        return super._update(to, id, auth);
    }
    function claim(address[] calldata selected) external nonReentrant {
        if (selected.length == 0 || selected.length > 5) revert InvalidAmount();
        _checkpoint(msg.sender);
        bool any;
        for (uint256 i; i < selected.length; ++i) {
            address asset = selected[i];
            if (!registeredAsset[asset]) revert UnsupportedAsset();
            for (uint256 j; j < i; ++j) if (selected[j] == asset) revert InvalidAmount();
            uint256 amount = _earned[msg.sender][asset];
            if (amount == 0) continue;
            any = true;
            _earned[msg.sender][asset] = 0;
            paid[asset] += amount;
            _beforePayout(asset);
            uint256 beforeVault = IERC20(asset).balanceOf(address(this));
            uint256 beforeHolder = IERC20(asset).balanceOf(msg.sender);
            IERC20(asset).safeTransfer(msg.sender, amount);
            if (IERC20(asset).balanceOf(address(this)) != beforeVault - amount
                || IERC20(asset).balanceOf(msg.sender) != beforeHolder + amount)
                revert UnsupportedTransfer();
            emit RewardClaimed(msg.sender, asset, amount);
        }
        if (!any) revert NoRewards();
    }
    function _backedBalance(address asset) internal view virtual returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
    function _beforePayout(address) internal virtual {}
}