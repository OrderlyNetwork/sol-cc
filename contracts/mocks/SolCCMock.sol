// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { SolCC } from "./SolCC.sol";
import { ILedger, AccountDepositSol, AccountWithdrawSol, WithdrawDataSol } from "../interface/ILedger.sol";
import { Utils } from "../library/Utils.sol";
import { ISolConnector } from "../interface/ISolConnector.sol";
import { IOAppComposer } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppComposer.sol";
import { Origin } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppUpgradeable.sol";
import { OFTMsgCodec } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail, MessagingReceipt, MessagingFee } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import { MsgCodec } from "../library/MsgCodec.sol";

struct OCCWithdrawData {
    bytes32 accountId;
    bytes32 sender;
    bytes32 receiver;
    bytes32 brokerHash;
    uint64 tokenAmount;
    uint64 fee;
    uint64 chainId;
    uint64 withdrawNonce;
}

struct OCCDepositData {
    bytes32 accountId;
    bytes32 brokerHash;
    bytes32 solAddress;
    bytes32 tokenHash;
    uint64 chainId;
    uint64 tokenAmount;
    uint64 depositNonce;
}

enum MsgType {
    Deposit,
    Withdraw,
    RebalanceBurn,
    RebalanceMint
}

uint8 constant MSG_TYPE_OFFSET = 1;

contract SolCCMock is SolCC, ISolConnector {
    uint64 public depositNonce;
    uint256 public constant SOL_CHAIN_ID = 902902902; // solana chain id for devnet
    uint256 public constant ORDERLY_CHAIN_ID = 4460;
    uint256 public constant ARBITRUM_CHAIN_ID = 421614;
    uint32 public constant SOL_EID = 40168;
    uint32 public constant ORDERLY_EID = 40200;
    uint32 public constant ARBITRUM_EID = 40231;
    using OFTMsgCodec for bytes;
    using OFTMsgCodec for bytes32;
    using OptionsBuilder for bytes;

    event MessageReceived(uint256 natveFee, uint256 lzFee, bytes message);
    event Option(MessagingFee, bytes option);
    event UnkonwnMessageType(uint8 msgType);

    function withdraw(WithdrawDataSol calldata _withdrawData) external onlyLedger {
        AccountWithdrawSol memory withdrawData = AccountWithdrawSol(
            Utils.getSolAccountId(_withdrawData.sender, _withdrawData.brokerId),
            _withdrawData.sender,
            _withdrawData.receiver,
            Utils.calculateStringHash(_withdrawData.brokerId),
            Utils.calculateStringHash(_withdrawData.tokenSymbol),
            _withdrawData.tokenAmount,
            _withdrawData.fee,
            _withdrawData.chainId,
            _withdrawData.withdrawNonce
        );

        bytes memory payload = MsgCodec.encodeWithdrawPayload(withdrawData);
        bytes memory lzWithdrawMsg = MsgCodec.encodeLzMsg(uint8(MsgType.Withdraw), payload);
        uint32 dstEid = SOL_EID;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500000, 0); // .addExecutorOrderedExecutionOption()
        MessagingFee memory _msgFee = _quote(dstEid, lzWithdrawMsg, options, false);
        emit MessageReceived(_msgFee.nativeFee, _msgFee.lzTokenFee, payload);
        MessagingReceipt memory msgReceipt = _lzSend(dstEid, lzWithdrawMsg, options, _msgFee, address(this));
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address /*_executor*/, // @dev unused in the default implementation.
        bytes calldata /*_extraData*/ // @dev unused in the default implementation.
    ) internal virtual override whenNotPaused {
        // @dev The src sending chain doesnt know the address length on this chain (potentially non-evm)
        // Thus everything is bytes32() encoded in flight.

        (uint8 msgType, bytes memory payload) = MsgCodec.decodeLzMsg(_message);

        if (msgType == uint8(MsgType.Deposit)) {
            AccountDepositSol memory accountDepositSol = abi.decode(payload, (AccountDepositSol));
            ledger.accountDepositSol(accountDepositSol);
        } else {
            emit UnkonwnMessageType(msgType);
        }
    }
}
