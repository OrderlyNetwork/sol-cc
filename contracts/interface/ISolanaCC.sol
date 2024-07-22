// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { AccountDepositSol, AccountWithdrawSol, WithdrawDataSol } from "./ILedger.sol";

interface ILedger {
    function withdraw(WithdrawDataSol calldata data) external;
}
