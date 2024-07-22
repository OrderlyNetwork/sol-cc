// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

contract EndpointV2Mock {
    function setDelegate(address _delegate) external returns (bool) {
        return true;
    }
    function mockDeposit() external {}

    function mockWithdraw() external {}
}
