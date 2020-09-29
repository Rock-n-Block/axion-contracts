// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "../interfaces/IBPD.sol";

contract BPDMock is IBPD {
    function callIncomeTokensTrigger(uint256 incomeAmountToken)
        external
        override
    {}

    function transferYearlyPool(uint256 poolNumber)
        external
        override
        returns (uint256)
    {}

    function getPoolYearAmounts()
        external
        override
        view
        returns (uint256[5] memory poolAmounts)
    {}
}
