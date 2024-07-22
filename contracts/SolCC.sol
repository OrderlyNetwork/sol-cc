// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { OAppUpgradeable, MessagingFee, Origin } from "./layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppUpgradeable.sol";
import { MessagingReceipt } from "./layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSenderUpgradeable.sol";
import { ILedger, AccountDepositSol, AccountWithdrawSol, WithdrawDataSol } from "./interface/ILedger.sol";

contract SolCC is OAppUpgradeable {
    mapping(uint256 => uint32) public chinIdToEid;
    mapping(uint32 => uint256) public eidToChainId;
    mapping(address => bool) public trustCaller;
    ILedger public ledger;
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
    function initialize(address _lzEndpoint, address _delegate) external virtual initializer {
        __initializeOApp(_lzEndpoint, _delegate);
    }

    /**
     * @notice Sends a message from the source chain to a destination chain.
     * @param _dstEid The endpoint ID of the destination chain.
     * @param _message The message string to be sent.
     * @param _options Additional options for message execution.
     * @dev Encodes the message as bytes and sends it using the `_lzSend` internal function.
     * @return receipt A `MessagingReceipt` struct containing details of the message sent.
     */
    function send(
        uint32 _dstEid,
        string memory _message,
        bytes calldata _options
    ) external payable returns (MessagingReceipt memory receipt) {
        bytes memory _payload = abi.encode(_message);
        receipt = _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
    }

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction in native gas or ZRO token.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _message The message.
     * @param _options Message execution options (e.g., for sending gas to destination).
     * @param _payInLzToken Whether to return fee in ZRO token.
     * @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function quote(
        uint32 _dstEid,
        string memory _message,
        bytes memory _options,
        bool _payInLzToken
    ) public view returns (MessagingFee memory fee) {
        bytes memory payload = abi.encode(_message);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    /**
     * @dev Internal function override to handle incoming messages from another chain.
     * @dev _origin A struct containing information about the message sender.
     * @dev _guid A unique global packet identifier for the message.
     * @param payload The encoded message payload being received.
     *
     * @dev The following params are unused in the current implementation of the OApp.
     * @dev _executor The address of the Executor responsible for processing the message.
     * @dev _extraData Arbitrary data appended by the Executor to the message.
     *
     * Decodes the received payload and processes it as per the business logic defined in the function.
     */
    function _lzReceive(
        Origin calldata /*_origin*/,
        bytes32 /*_guid*/,
        bytes calldata payload,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) internal override {}

    // =========================== Admin functions ===========================

    function setEids(uint256[] calldata _chainIds, uint32[] calldata _eids) external onlyOwner {
        require(_chainIds.length == _eids.length, "Length mismatch");
        require(_chainIds.length > 0, "Empty input");
        for (uint256 i = 0; i < _chainIds.length; i++) {
            require(_chainIds[i] > 0, "Zero chainid");
            require(_eids[i] > 0, "Zero eid");
            chinIdToEid[_chainIds[i]] = _eids[i];
            eidToChainId[_eids[i]] = _chainIds[i];
        }
    }

    function setLedger(address _ledger) external onlyOwner {
        require(_ledger != address(0), "Zero address");
        require(_ledger != address(ledger), "Same ledger address");
        ledger = ILedger(_ledger);
    }
}
