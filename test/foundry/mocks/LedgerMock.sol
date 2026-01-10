// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../../contracts/interface/ILedger.sol";
import "../../../contracts/SolConnector.sol";

contract LedgerMock is ILedger {
    SolConnector public solConnector;

    constructor(address _solConnector) {
        solConnector = SolConnector(payable(_solConnector));
    }

    function accountDepositSol(AccountDepositSol calldata data) external override {
        // This function intentionally does nothing
    }

    // New function to mock withdraw
    function mockWithdraw(WithdrawDataSol calldata data) external {
        solConnector.withdraw(data);
    }

    function mockWithdraw2ContractV2(Withdraw2ContractV2 calldata data) external {
        solConnector.withdraw2ContractV2(data);
    }

    // Function to set SolConnector address (in case it needs to be updated)
    function setSolConnector(address _solConnector) external {
        solConnector = SolConnector(payable(_solConnector));
    }
}
