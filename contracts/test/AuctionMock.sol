pragma solidity >=0.4.25 <0.7.0;

import "../interfaces/IAuction.sol";

contract AuctionMock is IAuction {
    function callIncomeTokensTrigger(uint256 incomeAmountToken)
        external
        override
    {}
}
