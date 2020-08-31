pragma solidity >=0.4.25 <0.7.0;

import "../interfaces/IStaking.sol";

contract StakingMock is IStaking {
	function externalStake(
        address account,
        uint256 amount,
        uint256 stakingDays
    ) external
	  override
	{}
}
