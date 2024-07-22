// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { SolCC } from "../SolCC.sol";
import { ILedger, AccountDepositSol, AccountWithdrawSol, WithdrawDataSol } from "../interface/ILedger.sol";
import { Utils } from "../library/Utils.sol";
import { ISolCC } from "../interface/ISolCC.sol";

contract SolCCMock is SolCC, ISolCC {
    uint64 public depositNonce;
    uint256 public constant SOL_CHAIN_ID = 902902902; // solana chain id for devnet

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
            uint128(tokenAmount),
            _newDepositNonce()
        );
        ledger.accountDepositSol(depositData);
    }

    function _newDepositNonce() internal returns (uint64) {
        return ++depositNonce;
    }
}
