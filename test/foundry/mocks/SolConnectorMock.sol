// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {SolConnector} from "../../../contracts/SolConnector.sol";
import {WithdrawDataSol, AccountWithdrawSol} from "../../../contracts/interface/ILedger.sol";
import {Utils} from "../../../contracts/library/Utils.sol";
import {MsgCodec} from "../../../contracts/library/MsgCodec.sol";
import {OptionsBuilder} from "../../../contracts/layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingFee} from "../../../contracts/layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppUpgradeable.sol";

contract SolConnectorMock is SolConnector {
    using OptionsBuilder for bytes;

    function mockWithdraw(WithdrawDataSol calldata _withdrawData) external {
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
            msgOptions[uint8(MsgCodec.MsgType.Withdraw)].gas, msgOptions[uint8(MsgCodec.MsgType.Withdraw)].value
        );
        MessagingFee memory _msgFee = _quote(solEid, lzWithdrawMsg, withdrawOptions, false);
        _lzSend(solEid, lzWithdrawMsg, withdrawOptions, _msgFee, address(this));
    }
}
