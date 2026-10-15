// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Direct final vault for up to five wallet or social recipients.
/// @dev Social identities are opaque provider-scoped keys. The verifier binds
/// an identity to a wallet only at claim time; the vault never calls a social API.
contract PancakeV1FeeSharingVault {
    using SafeERC20 for IERC20;

    uint16 public constant BPS = 10_000;
    uint16 public constant MAX_FEE_BPS = BPS;
    uint8 public constant MAX_RECIPIENTS = 5;
    uint8 public constant MAX_EPOCHS = 64;
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "Claim(bytes32 provider,bytes32 identityHash,address wallet,bytes32 assetsHash,uint256 nonce,uint256 deadline)"
    );
    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    enum Kind { Wallet, Social }
    struct Recipient {
        Kind kind;
        address wallet;
        bytes32 provider;
        bytes32 identityHash;
        uint16 shareBps;
    }
    struct Policy { uint64 activatesAt; uint16 feeBps; uint8 count; }
    address public immutable projectToken;
    address public immutable hook;
    address public immutable admin;
    address public immutable verifier;
    bytes32 private immutable _domainName;
    bytes32 private immutable _domainVersion;
    uint64 public activeEpoch;
    mapping(uint64 => Policy) public policies;
    mapping(uint64 => Recipient[5]) private _recipients;
    mapping(bytes32 => bool) public knownIdentity;
    mapping(uint64 => mapping(address => mapping(address => uint256))) public walletClaimable;
    mapping(uint64 => mapping(bytes32 => mapping(address => uint256))) public socialClaimable;
    mapping(bytes32 => uint256) public nonces;
    mapping(address => uint256) public accrued;
    mapping(address => uint256) public claimed;

    error OnlyHook();
    error OnlyAdmin();
    error InvalidConfiguration();
    error InvalidAuthorization();
    error ExpiredAuthorization();
    error NoClaim();
    error InsufficientRecordedBalance();

    event PolicyAppended(uint64 indexed epoch, uint64 activatesAt, uint16 feeBps);
    event FeeRecorded(uint64 indexed epoch, address indexed asset, uint256 amount);
    event FeeClaimed(address indexed recipient, address indexed asset, uint256 amount);
    event SocialClaimed(
        bytes32 indexed provider, bytes32 indexed identityHash, address indexed wallet,
        address asset, uint256 amount, uint256 nonce
    );

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    constructor(address project_, address hook_, address admin_, address verifier_,
        Recipient[] memory recipients_, uint16 feeBps_) {
        if (project_ == address(0) || hook_ == address(0) || admin_ == address(0)
            || verifier_ == address(0) || recipients_.length == 0 || recipients_.length > MAX_RECIPIENTS
            || feeBps_ > MAX_FEE_BPS) revert InvalidConfiguration();
        projectToken = project_;
        hook = hook_;
        admin = admin_;
        verifier = verifier_;
        _domainName = keccak256("PAIR Pancake V1 Fee Sharing");
        _domainVersion = keccak256("1");
        _append(0, recipients_, feeBps_);
    }

    function recipientCount(uint64 epoch) external view returns (uint256) { return policies[epoch].count; }
    function recipient(uint64 epoch, uint256 index) external view returns (Recipient memory) {
        return _recipients[epoch][index];
    }
    function policy(uint64 epoch) external view returns (Policy memory) { return policies[epoch]; }
    function identityNonce(bytes32 provider, bytes32 identityHash) external view returns (uint256) {
        return nonces[_identityKey(provider, identityHash)];
    }

    function appendPolicy(Recipient[] calldata recipients_, uint16 feeBps_, uint64 activatesAt)
        external onlyAdmin {
        // A matured queued policy must become the active epoch before selecting
        // the next slot, otherwise a second append could overwrite it.
        _sync();
        if (activeEpoch >= MAX_EPOCHS || policies[activeEpoch + 1].count != 0) revert InvalidConfiguration();
        if (feeBps_ > MAX_FEE_BPS || recipients_.length == 0 || recipients_.length > MAX_RECIPIENTS) {
            revert InvalidConfiguration();
        }
        if (activatesAt < policies[activeEpoch].activatesAt) revert InvalidConfiguration();
        _append(activatesAt, recipients_, feeBps_);
    }

    function _append(uint64 activatesAt, Recipient[] memory recipients_, uint16 feeBps_) private {
        uint64 epoch = uint64(activeEpoch + 1);
        uint256 total;
        for (uint256 i; i < recipients_.length; ++i) {
            Recipient memory r = recipients_[i];
            bytes32 key = _validateRecipient(r);
            if (_hasDuplicate(recipients_, i, r.kind, key)) revert InvalidConfiguration();
            if (r.kind == Kind.Social) knownIdentity[key] = true;
            _recipients[epoch][i] = r;
            total += r.shareBps;
        }
        if (total != BPS) revert InvalidConfiguration();
        policies[epoch] = Policy(activatesAt, feeBps_, uint8(recipients_.length));
        if (activatesAt <= block.timestamp) activeEpoch = epoch;
        emit PolicyAppended(epoch, activatesAt, feeBps_);
    }

    function _validateRecipient(Recipient memory r) private pure returns (bytes32 key) {
        if (r.kind == Kind.Wallet) {
            if (r.wallet == address(0) || r.shareBps == 0) revert InvalidConfiguration();
            return bytes32(uint256(uint160(r.wallet)));
        }
        key = _identityKey(r.provider, r.identityHash);
        if (r.shareBps == 0) revert InvalidConfiguration();
    }

    function _hasDuplicate(Recipient[] memory recipients_, uint256 index, Kind kind, bytes32 key)
        private pure returns (bool) {
        for (uint256 j; j < index; ++j) {
            Recipient memory prior = recipients_[j];
            bytes32 priorKey = prior.kind == Kind.Wallet
                ? bytes32(uint256(uint160(prior.wallet)))
                : keccak256(abi.encode(prior.provider, prior.identityHash));
            if (prior.kind == kind && priorKey == key) return true;
        }
        return false;
    }

    function _sync() private returns (uint64 epoch) {
        epoch = activeEpoch;
        uint64 next = epoch + 1;
        while (next <= MAX_EPOCHS && policies[next].count != 0 && policies[next].activatesAt <= block.timestamp) {
            epoch = next++;
        }
        activeEpoch = epoch;
    }

    function currentPolicy() external view returns (uint64 epoch, uint16 feeBps) {
        epoch = activeEpoch;
        uint64 next = epoch + 1;
        while (next <= MAX_EPOCHS && policies[next].count != 0 && policies[next].activatesAt <= block.timestamp) ++next;
        return (next - 1, policies[next - 1].feeBps);
    }

    function recordFee(address asset, uint256 amount) external {
        if (msg.sender != hook) revert OnlyHook();
        if (asset == address(0) || amount == 0) revert InvalidConfiguration();
        uint256 outstanding = accrued[asset] - claimed[asset];
        if (IERC20(asset).balanceOf(address(this)) < outstanding + amount) revert InsufficientRecordedBalance();
        uint64 epoch = _sync();
        Policy memory p = policies[epoch];
        uint256 allocated;
        for (uint256 i; i < p.count; ++i) {
            Recipient memory r = _recipients[epoch][i];
            uint256 share = i + 1 == p.count ? amount - allocated : amount * r.shareBps / BPS;
            allocated += share;
            if (r.kind == Kind.Wallet) walletClaimable[epoch][r.wallet][asset] += share;
            else socialClaimable[epoch][_identityKey(r.provider, r.identityHash)][asset] += share;
        }
        accrued[asset] += amount;
        emit FeeRecorded(epoch, asset, amount);
    }

    function claimWallet(address[] calldata assets) external returns (uint256 total) {
        if (assets.length == 0 || assets.length > 20) revert InvalidConfiguration();
        for (uint256 a; a < assets.length; ++a) {
            address asset = assets[a];
            if (asset == address(0)) revert InvalidConfiguration();
            uint256 amount = _takeWallet(msg.sender, asset);
            if (amount != 0) {
                claimed[asset] += amount;
                IERC20(asset).safeTransfer(msg.sender, amount);
                emit FeeClaimed(msg.sender, asset, amount);
                total += amount;
            }
        }
        if (total == 0) revert NoClaim();
    }

    function claimSocial(bytes32 provider, bytes32 identityHash, address wallet, address[] calldata assets,
        uint256 deadline, bytes calldata signature) external returns (uint256 total) {
        bytes32 identityKey = _identityKey(provider, identityHash);
        if (!knownIdentity[identityKey] || wallet == address(0) || assets.length == 0 || assets.length > 20) {
            revert InvalidConfiguration();
        }
        if (block.timestamp > deadline) revert ExpiredAuthorization();
        uint256 nonce = _consumeAuthorization(provider, identityHash, wallet, assets, deadline, signature);
        for (uint256 a; a < assets.length; ++a) {
            address asset = assets[a];
            uint256 amount = _takeSocial(identityKey, asset);
            if (amount != 0) {
                claimed[asset] += amount;
                IERC20(asset).safeTransfer(wallet, amount);
                emit SocialClaimed(provider, identityHash, wallet, asset, amount, nonce);
                total += amount;
            }
        }
        if (total == 0) revert NoClaim();
    }

    function _consumeAuthorization(bytes32 provider, bytes32 identityHash, address wallet, address[] calldata assets,
        uint256 deadline, bytes calldata signature) private returns (uint256 nonce) {
        bytes32 identityKey = _identityKey(provider, identityHash);
        nonce = nonces[identityKey];
        bytes32 assetsHash = keccak256(abi.encode(assets));
        bytes32 structHash = keccak256(
            abi.encode(CLAIM_TYPEHASH, provider, identityHash, wallet, assetsHash, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        if (ECDSA.recover(digest, signature) != verifier) revert InvalidAuthorization();
        nonces[identityKey] = nonce + 1;
    }

    function _takeWallet(address wallet, address asset) private returns (uint256 amount) {
        for (uint64 e = 1; e <= MAX_EPOCHS; ++e) {
            amount += walletClaimable[e][wallet][asset];
            walletClaimable[e][wallet][asset] = 0;
        }
    }

    function _takeSocial(bytes32 identityKey, address asset) private returns (uint256 amount) {
        for (uint64 e = 1; e <= MAX_EPOCHS; ++e) {
            amount += socialClaimable[e][identityKey][asset];
            socialClaimable[e][identityKey][asset] = 0;
        }
    }

    function _identityKey(bytes32 provider, bytes32 identityHash) private pure returns (bytes32) {
        if (provider == bytes32(0) || identityHash == bytes32(0)) revert InvalidConfiguration();
        return keccak256(abi.encode(provider, identityHash));
    }

    function _domainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, _domainName, _domainVersion, block.chainid, address(this)));
    }
}