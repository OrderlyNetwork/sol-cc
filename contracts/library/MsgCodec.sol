// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum CrossChainMethod {
    Deposit,
    Withdraw,
    WidhtrawFinish,
    RebalanceBurn, // burn request from ledger to vault
    RebalanceBurnFinish, // burn request finish from vault to ledger
    RebalanceMint, // mint request from ledger to vault
    RebalanceMintFinish
}

enum PayloadType {
    EventTypesWithdrawData,
    AccountTypesAccountDeposit,
    AccountTypesAccountWithdraw,
    VaultTypesVaultDeposit,
    VaultTypesVaultWithdraw,
    RebalanceBurnCCData,
    RebalanceBurnCCFinishData,
    RebalanceMintCCData,
    RebalanceMintCCFinishData
}

library OFTMsgCodec {}
