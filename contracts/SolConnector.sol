// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { OptionsBuilder } from "./layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { OAppUpgradeable, MessagingFee, Origin } from "./layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppUpgradeable.sol";
import { MessagingReceipt } from "./layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSenderUpgradeable.sol";
import { ILedger, AccountDepositSol, AccountWithdrawSol, WithdrawDataSol, Withdraw2ContractV2 } from "./interface/ILedger.sol";
import { Utils } from "./library/Utils.sol";
import { ISolConnector } from "./interface/ISolConnector.sol";
import { MsgCodec } from "./library/MsgCodec.sol";

struct LzOptions {
    uint128 gas;
    uint128 value;
}

contract SolConnector is OAppUpgradeable, AccessControlUpgradeable, ISolConnector {
    ILedger public ledger;
    mapping(uint8 => LzOptions) public msgOptions;
    uint32 public solEid;
    uint64 public inboundNonce;
    bool public orderDelivery;
    // Token index
    // 0: PLACEHOLDER
    // 1: USDC
    // 2: USDT
    // 3: WSOL
    // ...
    // 255: SOL
    mapping(bytes32 => uint8) public tokenHash2Index;
    mapping(uint8 => bytes32) public tokenIndex2Hash;
    mapping(bytes32 => uint16) public brokerHash2Index;
    mapping(uint16 => bytes32) public brokerIndex2Hash;
    mapping(bytes32 => uint128) public tokenDecimalsOnSolana;
    mapping(bytes32 => uint128) public tokenDecimalsOnOrderly;
    uint16 public maxBrokerCount; // max broker count, added by broker manager

    // /* ================ Constants ================ */
    uint16 public constant BROKER_MANAGER_INDEX_BASE = 18000; // Broker index for broker manager role starts from 18000 to avoid conflict with the brokers added by owner

    bytes32 public constant SYMBOL_MANAGER_ROLE = keccak256("ORDERLY_MANAGER_SYMBOL_MANAGER_ROLE");

    bytes32 public constant BROKER_MANAGER_ROLE = keccak256("ORDERLY_MANAGER_BROKER_MANAGER_ROLE");

    modifier onlyLedger() {
        require(msg.sender == address(ledger), "Only ledger can call this function");
        _;
    }

    /// @notice check if the caller is the owner or has the role
    modifier onlyOwnerOrRole(bytes32 role) {
        if (!hasRole(role, msg.sender) && msg.sender != owner())
            revert AccessControlUnauthorizedAccount(msg.sender, role);
        _;
    }

    using OptionsBuilder for bytes;

    event UnkonwnMessageType(uint8 msgType);
    event SetOrderDelivery(bool orderDelivery, uint64 inboundNonce);
    event SetTokenHashToIndex(bytes32 indexed tokenHash, uint8 _oldIndex, uint8 _newIndex);
    event SetBrokerHashToIndex(bytes32 indexed brokerHash, uint16 _oldIndex, uint16 _newIndex);
    event SetTokenDecimalsOnSolana(bytes32 indexed tokenHash, uint128 decimals);
    event SetTokenDecimalsOnOrderly(bytes32 indexed tokenHash, uint128 decimals);
    event SetMaxBrokerCount(uint16 _oldMaxBrokerCount, uint16 _newMaxBrokerCount);

    /**
     * @dev Disable the initializer on the implementation contract
     */

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the OrderOFT contract and set the ordered nonce flag
     * @param _lzEndpoint The LayerZero endpoint address
     * @param _delegate The delegate address of this OApp on the endpoint
     */
    function initialize(address _lzEndpoint, address _delegate, uint32 _solEid) external virtual initializer {
        __initializeOApp(_lzEndpoint, _delegate);
        require(_solEid != 0, "Zero eid");
        solEid = _solEid;
        orderDelivery = true;
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal virtual override whenNotPaused {
        if (orderDelivery) {
            require(_origin.nonce == inboundNonce + 1, "Invalid inbound nonce");
        }
        inboundNonce = _origin.nonce;

        (uint8 msgType, bytes memory payload) = MsgCodec.decodeLzMsg(_message);

        if (msgType == uint8(MsgCodec.MsgType.Deposit)) {
            AccountDepositSol memory accountDepositSol = abi.decode(payload, (AccountDepositSol));
            accountDepositSol.tokenAmount = convertDepositDecimals(
                accountDepositSol.tokenHash,
                accountDepositSol.tokenAmount
            );
            ledger.accountDepositSol(accountDepositSol);
        } else {
            emit UnkonwnMessageType(msgType);
        }
    }

    // =========================== Only Ledger functions ===========================

    function withdraw(WithdrawDataSol calldata _withdrawData) external onlyLedger whenNotPaused {
        bytes32 tokenHash = Utils.calculateStringHash(_withdrawData.tokenSymbol);
        uint8 tokenIndex = tokenHash2Index[tokenHash];
        require(tokenIndex != 0, "Token index not set");
        bytes32 brokerHash = Utils.calculateStringHash(_withdrawData.brokerId);
        uint16 brokerIndex = brokerHash2Index[brokerHash];
        require(brokerIndex != 0, "Broker index not set");
        AccountWithdrawSol memory withdrawData = AccountWithdrawSol(
            // Utils.getSolAccountId(_withdrawData.sender, _withdrawData.brokerId),
            _withdrawData.sender,
            _withdrawData.receiver,
            brokerIndex,
            tokenIndex,
            convertWithdrawDecimals(tokenHash, _withdrawData.tokenAmount),
            convertWithdrawDecimals(tokenHash, _withdrawData.fee),
            _withdrawData.chainId,
            _withdrawData.withdrawNonce
        );

        bytes memory payload = MsgCodec.encodeWithdrawPayload(withdrawData);
        bytes memory lzWithdrawMsg = MsgCodec.encodeLzMsg(uint8(MsgCodec.MsgType.Withdraw), payload);
        bytes memory withdrawOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            msgOptions[uint8(MsgCodec.MsgType.Withdraw)].gas,
            msgOptions[uint8(MsgCodec.MsgType.Withdraw)].value
        );
        MessagingFee memory _msgFee = _quote(solEid, lzWithdrawMsg, withdrawOptions, false);
        _lzSend(solEid, lzWithdrawMsg, withdrawOptions, _msgFee, address(this));
    }

    function withdraw2ContractV2(
        Withdraw2ContractV2 calldata _withdraw2ContractV2Data
    ) external onlyLedger whenNotPaused {
        bytes32 tokenHash = _withdraw2ContractV2Data.tokenHash;
        uint8 tokenIndex = tokenHash2Index[tokenHash];
        require(tokenIndex != 0, "Token index not set");
        bytes32 brokerHash = _withdraw2ContractV2Data.brokerHash;
        uint16 brokerIndex = brokerHash2Index[brokerHash];
        require(brokerIndex != 0, "Broker index not set");
        AccountWithdrawSol memory withdrawData = AccountWithdrawSol(
            // Utils.getSolAccountId(_withdrawData.sender, _withdrawData.brokerId),
            _withdraw2ContractV2Data.sender,
            _withdraw2ContractV2Data.receiver,
            brokerIndex,
            tokenIndex,
            convertWithdrawDecimals(tokenHash, _withdraw2ContractV2Data.tokenAmount),
            convertWithdrawDecimals(tokenHash, _withdraw2ContractV2Data.fee),
            _withdraw2ContractV2Data.chainId,
            _withdraw2ContractV2Data.withdrawNonce
        );

        bytes memory payload = MsgCodec.encodeWithdrawPayload(withdrawData);
        bytes memory lzWithdrawMsg = MsgCodec.encodeLzMsg(uint8(MsgCodec.MsgType.Withdraw), payload);
        bytes memory withdrawOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            msgOptions[uint8(MsgCodec.MsgType.Withdraw)].gas,
            msgOptions[uint8(MsgCodec.MsgType.Withdraw)].value
        );
        MessagingFee memory _msgFee = _quote(solEid, lzWithdrawMsg, withdrawOptions, false);
        _lzSend(solEid, lzWithdrawMsg, withdrawOptions, _msgFee, address(this));
    }

    function nextNonce(uint32 /*_srcEid*/, bytes32 /*_sender*/) public view override returns (uint64 nonce) {
        if (orderDelivery) {
            nonce = inboundNonce + 1;
        } else {
            nonce = 0;
        }
    }

    // =========================== Admin functions ===========================

    function setLedger(address _ledger) external onlyOwner {
        require(_ledger != address(0), "Zero address");
        require(_ledger != address(ledger), "Same ledger address");
        ledger = ILedger(_ledger);
    }

    function setSolEid(uint32 _solEid) external onlyOwner {
        require(_solEid != 0, "Zero eid");
        solEid = _solEid;
    }

    function setOptions(uint8 _msgType, uint128 _gas, uint128 _value) external onlyOwner {
        msgOptions[_msgType] = LzOptions(_gas, _value);
    }

    function setOrderDelivery(bool _orderDelivery, uint64 _inboundNonce) external onlyOwner {
        orderDelivery = _orderDelivery;
        inboundNonce = _inboundNonce;
        emit SetOrderDelivery(_orderDelivery, _inboundNonce);
    }

    function setTokenHash2Index(bytes32 _tokenHash, uint8 _index) external onlyOwner {
        require(_tokenHash != bytes32(0) && _index != 0, "Zero token hash or index");
        require(tokenIndex2Hash[_index] == bytes32(0), "Token index already used");
        uint8 oldIndex = tokenHash2Index[_tokenHash];
        tokenHash2Index[_tokenHash] = _index;
        tokenIndex2Hash[_index] = _tokenHash;
        emit SetTokenHashToIndex(_tokenHash, oldIndex, _index);
    }

    // @dev Add broker hash and its index mapping
    // @dev Only owner or broker manager role can call this function
    // @dev For broker manager role, the broker index must be >= BROKER_MANAGER_INDEX_BASE
    // @dev This is to avoid conflict with the brokers added by owner
    function setBrokerHash2Index(bytes32 _brokerHash, uint16 _index) external onlyOwnerOrRole(BROKER_MANAGER_ROLE) {
        require(_brokerHash != bytes32(0) && _index != 0, "Zero broker hash or index");
        require(brokerIndex2Hash[_index] == bytes32(0), "Broker index already used");
        require(brokerHash2Index[_brokerHash] == 0, "Broker already set");
        if (msg.sender != owner()) {
            require(
                _index >= BROKER_MANAGER_INDEX_BASE || _index < BROKER_MANAGER_INDEX_BASE + maxBrokerCount,
                "Broker index out of range"
            );
        }
        brokerHash2Index[_brokerHash] = _index;
        brokerIndex2Hash[_index] = _brokerHash;
        emit SetBrokerHashToIndex(_brokerHash, 0, _index);
    }

    // @dev Reset broker hash and its index, in case of misconfiguration
    // @dev Only owner can call this function
    function resetBrokerHash2Index(bytes32 _brokerHash, uint16 _newIndex) external onlyOwner {
        uint16 oldIndex = brokerHash2Index[_brokerHash];
        brokerHash2Index[_brokerHash] = _newIndex;
        brokerIndex2Hash[_newIndex] = _brokerHash;
        emit SetBrokerHashToIndex(_brokerHash, oldIndex, _newIndex);
    }

    function setMaxBrokerCount(uint16 _maxBrokerCount) external onlyOwner {
        require(_maxBrokerCount != 0, "Zero max broker count");
        uint16 oldMaxBrokerCount = maxBrokerCount;
        maxBrokerCount = _maxBrokerCount;
        emit SetMaxBrokerCount(oldMaxBrokerCount, _maxBrokerCount);
    }

    function setTokenDecimalsOnSolana(bytes32 _tokenHash, uint128 _decimals) external onlyOwner {
        require(_tokenHash != bytes32(0) && _decimals != 0, "Zero token hash or decimals");
        tokenDecimalsOnSolana[_tokenHash] = _decimals;
        emit SetTokenDecimalsOnSolana(_tokenHash, _decimals);
    }

    function setTokenDecimalsOnOrderly(bytes32 _tokenHash, uint128 _decimals) external onlyOwner {
        require(_tokenHash != bytes32(0) && _decimals != 0, "Zero token hash or decimals");
        tokenDecimalsOnOrderly[_tokenHash] = _decimals;
        emit SetTokenDecimalsOnOrderly(_tokenHash, _decimals);
    }

    function withdrawNativeToken(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = to.call{ value: amount }("");
        require(success, "Transfer failed");
    }

    /* ================ Override To Simplify Access Control ================ */

    /// @notice Override grantRole
    function grantRole(bytes32 role, address account) public override onlyOwner {
        _grantRole(role, account);
    }

    /// @notice Override revokeRole
    function revokeRole(bytes32 role, address account) public override onlyOwner {
        _revokeRole(role, account);
    }

    // =========================== Public functions ===========================

    function convertDepositDecimals(bytes32 _tokenHash, uint128 _amount) public view returns (uint128) {
        uint128 srcDecimal = tokenDecimalsOnSolana[_tokenHash];
        uint128 dstDecimal = tokenDecimalsOnOrderly[_tokenHash];
        return convertDecimal(_amount, srcDecimal, dstDecimal);
    }

    function convertWithdrawDecimals(bytes32 _tokenHash, uint128 _amount) public view returns (uint128) {
        uint128 srcDecimal = tokenDecimalsOnOrderly[_tokenHash];
        uint128 dstDecimal = tokenDecimalsOnSolana[_tokenHash];
        return convertDecimal(_amount, srcDecimal, dstDecimal);
    }

    function convertDecimal(uint128 tokenAmount, uint128 srcDecimal, uint128 dstDecimal) public pure returns (uint128) {
        require(srcDecimal != 0 && dstDecimal != 0, "Zero decimals");
        if (srcDecimal == dstDecimal) {
            return tokenAmount;
        } else if (srcDecimal > dstDecimal) {
            return tokenAmount / uint128(10 ** (srcDecimal - dstDecimal));
        } else {
            return tokenAmount * uint128(10 ** (dstDecimal - srcDecimal));
        }
    }

    fallback() external payable {}

    receive() external payable {}
}
