// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { SolCC } from "../SolCC.sol";
import { ILedger, AccountDepositSol, AccountWithdrawSol, WithdrawDataSol } from "../interface/ILedger.sol";
import { Utils } from "../library/Utils.sol";
import { ISolCC } from "../interface/ISolCC.sol";
import { IOAppComposer } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oapp/interfaces/IOAppComposer.sol";
import { Origin } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppUpgradeable.sol";
import { OFTMsgCodec } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";
import { IOFT, SendParam, OFTLimit, OFTReceipt, OFTFeeDetail, MessagingReceipt, MessagingFee } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import { OptionsBuilder } from "../layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

contract SolCCMock is SolCC, ISolCC {
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

    function withdraw(WithdrawDataSol calldata _withdrawData) external onlyLedger {
        AccountWithdrawSol memory withdrawFinishData = AccountWithdrawSol(
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
        ledger.accountWithDrawSolFinish(withdrawFinishData);
    }
    function deposit(
        bytes32 _solAddress,
        string calldata brokerId,
        string calldata token,
        uint128 tokenAmount
    ) external {
        AccountDepositSol memory depositData = AccountDepositSol(
            Utils.getSolAccountId(_solAddress, brokerId),
            Utils.calculateStringHash(brokerId),
            _solAddress,
            Utils.calculateStringHash(token),
            SOL_CHAIN_ID,
            tokenAmount,
            _newDepositNonce()
        );
        ledger.accountDepositSol(depositData);
    }

    function _newDepositNonce() internal returns (uint64) {
        return ++depositNonce;
    }

    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        require(_from == address(this), "Only receive composeMsg from self");
        require(msg.sender == address(endpoint), "Only endpoint can call lzCompose");
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
        uint32 dstEid;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500000, 0);
        bytes memory message;
        if (block.chainid == ARBITRUM_CHAIN_ID && _origin.srcEid == SOL_EID) {
            // address toAddress = _message.sendTo().bytes32ToAddress();
            // // @dev Credit the amountLD to the recipient and return the ACTUAL amount the recipient received in local decimals
            // uint256 amountReceivedLD = 0;

            // if (_message.isComposed()) {
            //     // @dev Proprietary composeMsg format for the OFT.
            //     bytes memory composeMsg = OFTComposeMsgCodec.encode(
            //         _origin.nonce,
            //         _origin.srcEid,
            //         amountReceivedLD,
            //         _message.composeMsg()
            //     );

            //     // @dev Stores the lzCompose payload that will be executed in a separate tx.
            //     // Standardizes functionality for executing arbitrary contract invocation on some non-evm chains.
            //     // @dev The off-chain executor will listen and process the msg based on the src-chain-callers compose options passed.
            //     // @dev The index is used when a OApp needs to compose multiple msgs on lzReceive.
            //     // For default OFT implementation there is only 1 compose msg per lzReceive, thus its always 0.
            //     endpoint.sendCompose(toAddress, _guid, 0 /* the index of the composed message*/, composeMsg);
            // }
            // relay to orderly chain

            dstEid = ORDERLY_EID;
            MessagingFee memory _msgFee = _quote(dstEid, _message, options, false);
            emit MessageReceived(_msgFee.nativeFee, _msgFee.lzTokenFee, _message);
            MessagingReceipt memory msgReceipt = _lzSend(dstEid, _message, options, _msgFee, address(this));
        } else if (block.chainid == ARBITRUM_CHAIN_ID && _origin.srcEid == ORDERLY_EID) {
            // relay to solana chain
        } else if (block.chainid == ORDERLY_CHAIN_ID && _origin.srcEid == ARBITRUM_CHAIN_ID) {
            // call ledger contract
        }
    }

    function sendNull(bytes calldata _options) public payable {
        uint32 dstEid = ORDERLY_EID;
        string memory message = "Hello World";
        // bytes memory payload = abi.encode(message);
        bytes memory _payload = abi.encode(message);
        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500000, 0);
        MessagingFee memory _msgFee = _quote(dstEid, _payload, _options, false);
        // emit Option(_msgFee, options);

        MessagingReceipt memory receipt = _lzSend(dstEid, _payload, _options, _msgFee, payable(msg.sender));
        // MessagingReceipt memory msgReceipt = _lzSend(dstEid, payload, options, _msgFee, payable(msg.sender));
    }

    fallback() external payable {}

    receive() external payable {}
}
