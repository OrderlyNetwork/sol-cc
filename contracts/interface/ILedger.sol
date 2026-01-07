// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

// AccountTypes
struct AccountDepositSol {
    bytes32 accountId;
    bytes32 brokerHash;
    bytes32 userAddress;
    bytes32 tokenHash;
    uint256 srcChainId;
    uint128 tokenAmount;
    uint64 srcChainDepositNonce;
}

// AccountTypes
struct AccountWithdrawSol {
    // bytes32 accountId;
    bytes32 sender;
    bytes32 receiver;
    uint16 brokerIndex;
    uint8 tokenIndex; // previous was bytes32 tokenHash, which could result in exceeding the solana tx size limit
    uint128 tokenAmount;
    uint128 fee;
    uint256 chainId;
    uint64 withdrawNonce;
}
// EventTypes

struct WithdrawDataSol {
    uint128 tokenAmount;
    uint128 fee;
    uint256 chainId; // target withdraw chain
    bytes32 accountId;
    bytes32 r;
    bytes32 s;
    bytes32 sender;
    bytes32 receiver;
    uint64 withdrawNonce;
    uint64 timestamp;
    string brokerId; // only this field is string, others should be bytes32 hashedBrokerId
    string tokenSymbol; // only this field is string, others should be bytes32 hashedTokenSymbol
}

enum ChainType {
    EVM,
    SOL
}

enum VaultEnum {
    ProtocolVault,
    UserVault,
    Ceffu
}

struct Withdraw2ContractV2 {
    uint128 tokenAmount;
    uint128 fee;
    ChainType senderChainType;
    ChainType receiverChainType;
    uint256 chainId; // target withdraw chain
    bytes32 accountId;
    VaultEnum vaultType;
    bytes32 sender; // Support Solana account and EVM address
    uint64 withdrawNonce;
    bytes32 receiver;
    uint64 timestamp;
    bytes32 brokerHash;
    bytes32 tokenHash;
    uint256 clientId;
}

interface ILedger {
    function accountDepositSol(AccountDepositSol calldata data) external;
}
