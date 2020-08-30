// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

interface IStaking {
    function externalStake(
        address account,
        uint256 amount,
        uint256 stakingDays
    ) external;
}
