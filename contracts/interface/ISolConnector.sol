// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import { AccountDepositSol, AccountWithdrawSol, WithdrawDataSol, Withdraw2ContractV2 } from "./ILedger.sol";

interface ISolConnector {
    // ================== Only Ledger ==================
    function withdraw(WithdrawDataSol calldata data) external;
    function withdraw2ContractV2(Withdraw2ContractV2 calldata data) external;
    function setBrokerFromLedger(address brokerManager, bytes32 brokerHash, uint16 brokerIndex) external;

    // ================== Only Owner ==================
    function setTokenHash2Index(bytes32 _tokenHash, uint8 _index) external;
    function setBrokerHash2Index(bytes32 _brokerHash, uint16 _index) external;
    function setTokenDecimalsOnSolana(bytes32 _tokenHash, uint128 _decimals) external;
    function setTokenDecimalsOnOrderly(bytes32 _tokenHash, uint128 _decimals) external;

    // ================== Public functions ==================
    function convertDepositDecimals(bytes32 _tokenHash, uint128 _amount) external view returns (uint128);
    function convertWithdrawDecimals(bytes32 _tokenHash, uint128 _amount) external view returns (uint128);
    function convertDecimal(
        uint128 tokenAmount,
        uint128 srcDecimal,
        uint128 dstDecimal
    ) external view returns (uint128);
}
