// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IAuction.sol";
import "./interfaces/IForeignSwap.sol";
import "./interfaces/IBPD.sol";
import "./interfaces/ISubBalances.sol";


contract SubBalances is ISubBalances, AccessControl {
	using SafeMath for uint256;

	bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

    struct StakeSession {
    	address staker;
    	uint256 shares;
    	// uint256 sessionId;
    	uint256 start;
    	uint256 end;
    	uint256 finishTime;
    	bool withdrawn;
    }

    struct SubBalance {
    	mapping (address => uint256[]) userStakings;
    	mapping (uint256 => StakeSession) stakeSessions;
    	uint256 totalShares;
    	uint256 totalWithdrawAmount;
    	uint256 payDayStart;
    	uint256 payDayEnd;
    	bool minted;
    }

    SubBalance public subBalanceYearOne;
    SubBalance public subBalanceYearTwo;
    SubBalance public subBalanceYearThree;
    SubBalance public subBalanceYearFour;
    SubBalance public subBalanceYearFive;

    SubBalance[5] public subBalanceList;

    address public mainToken;
    address public foreignSwap;
	address public bigPayDayPool;
	address public auction;
	uint256 public startTimestamp;

	uint256 public currentSharesTotalSupply;

    uint256 public constant DAY = 86400;
    uint256 public constant PERIOD = 350;
    uint256[5] public PERIODS = [350, 700, 1050, 1400, 1750];

    modifier onlySetter() {
        require(hasRole(SETTER_ROLE, _msgSender()), "Caller is not a setter");
        _;
    }

    constructor(address _setter) public {
        _setupRole(SETTER_ROLE, _setter);
    }

    function init(
        address _mainToken,
        address _foreignSwap,
        address _bigPayDayPool,
        address _auction
    ) public
      onlySetter
    {
    	require(hasRole(SETTER_ROLE, _msgSender()), "Caller is not a setter role");
        mainToken = _mainToken;
        foreignSwap = _foreignSwap;
        bigPayDayPool = _bigPayDayPool;
        auction = _auction;

    	startTimestamp = now;

    	for (uint256 i = 0; i < subBalanceList.length; i++) {
    		SubBalance storage subBalance = subBalanceList[i];
    		subBalance.payDayStart = _addDays(startTimestamp, PERIODS[i]);
    		subBalance.payDayEnd = subBalance.payDayStart.add(DAY);
    	}
        renounceRole(SETTER_ROLE, _msgSender());
    }

    function getStartTimes() public view returns (uint256[5] memory startTimes) {
        for (uint256 i = 0; i < subBalanceList.length; i ++) {
            startTimes[i] = subBalanceList[i].payDayStart;
        }
    }

    function getPoolsMinted() public view returns (bool[5] memory poolsMinted) {
        for (uint256 i = 0; i < subBalanceList.length; i ++) {
            poolsMinted[i] = subBalanceList[i].minted;
        }
    }

    function getPoolsMintedAmounts() public view returns (uint256[5] memory poolsMintedAmounts) {
        for (uint256 i = 0; i < subBalanceList.length; i ++) {
            poolsMintedAmounts[i] = subBalanceList[i].totalWithdrawAmount;
        }
    }

    function getClosestYearShares() public view returns (uint256 shareAmount) {
        for (uint256 i = 0; i < subBalanceList.length; i++) {
            if (!subBalanceList[i].minted) {
                continue;
            } else {
                shareAmount = subBalanceList[i].totalShares;
                return shareAmount;
            }

            // return 0;
        }
    }

    function calculateSessionPayout(uint256 sessionId) public view returns (uint256 payoutAmount) {
        uint256[5] memory poolYearAmounts = IBPD(bigPayDayPool).getPoolYearAmounts();

        uint256 subBalanceStakerAmount;

        for (uint256 i = 0; i < subBalanceList.length; i++) {
            SubBalance storage subBalance = subBalanceList[i];
            StakeSession storage stakeSession = subBalance.stakeSessions[sessionId];

            if (now > subBalance.payDayStart && stakeSession.start != 0) {
                uint256 currentPoolAmount;
                uint256 addAmount;
                if (subBalance.minted) {
                    currentPoolAmount = subBalance.totalWithdrawAmount;
                } else {
                    (currentPoolAmount, addAmount) = _bpdAmountFromRaw(poolYearAmounts[i]);
                }

                uint256 stakerShare = stakeSession.shares.div(subBalance.totalShares);
                uint256 stakerAmount = currentPoolAmount.mul(stakerShare);

                subBalanceStakerAmount = subBalanceStakerAmount.add(stakerAmount);

            }
        }

        return subBalanceStakerAmount;
    }

    function withdrawPayout(uint256 sessionId) public {
    	uint256 subBalanceStakerAmount;
    	uint256 stakeStart;
    	uint256 stakeEnd;

    	for (uint256 i = 0; i < subBalanceList.length; i++) {
    		SubBalance storage subBalance = subBalanceList[i];
    		StakeSession storage stakeSession = subBalance.stakeSessions[sessionId];

    		if (now > subBalance.payDayStart && stakeSession.start != 0) {
		    	require(stakeSession.finishTime != 0, "cannot withdraw before unclaim");
		    	require(!stakeSession.withdrawn, "already withdrawn");
		    	require(_msgSender() == stakeSession.staker, "caller not matching sessionId");

    			uint256 stakerShare = stakeSession.shares.div(subBalance.totalShares);
    			uint256 stakerAmount = subBalance.totalWithdrawAmount.mul(stakerShare);

    			subBalanceStakerAmount = subBalanceStakerAmount.add(stakerAmount);

    			if (stakeStart == 0 && stakeEnd == 0){
    				stakeStart = stakeSession.start;
    				stakeEnd = stakeSession.end;
    			}
    		}
    	}

        uint256 estimatePeriod = stakeEnd.sub(stakeStart);
        uint256 existingPeriod = now.sub(stakeStart);

        if (estimatePeriod > existingPeriod) {
            uint256 localDelta = subBalanceStakerAmount.mul(estimatePeriod.sub(existingPeriod)).div(estimatePeriod);
            IERC20(mainToken).transfer(_msgSender(), subBalanceStakerAmount.sub(localDelta));
            IERC20(mainToken).transfer(auction, localDelta);
            IAuction(auction).callIncomeDailyTokensTrigger(localDelta);

            _saveWithdrawn(sessionId);
            return;
        }

        if (estimatePeriod < existingPeriod) {
            uint256 daysAfterGracePeriod = now.sub(stakeEnd);
            uint256 localDelta = subBalanceStakerAmount.mul(daysAfterGracePeriod.sub(14)).div(700);

            IERC20(mainToken).transfer(_msgSender(), subBalanceStakerAmount.sub(localDelta));
            IERC20(mainToken).transfer(auction, localDelta);
            IAuction(auction).callIncomeDailyTokensTrigger(localDelta);            

            _saveWithdrawn(sessionId);
            return;
        }

        if (estimatePeriod == existingPeriod) {
   	    	require(IERC20(mainToken).transfer(_msgSender(), subBalanceStakerAmount), "error in transfer tokens");
   	    	_saveWithdrawn(sessionId);
            return;
        }

    }

    function callIncomeStakerTrigger(
        address staker,
        uint256 sessionId,
        uint256 start,
        uint256 end,
        uint256 shares
    ) external override {
    	require(end > start, 'end must be more than start');
    	uint256 userPeriod = end.sub(start);

    	if (userPeriod > DAY && shares > 0) {

    		for (uint256 i = 0; i < subBalanceList.length; i++) {
    			SubBalance storage subBalance = subBalanceList[i];

    			if (end > subBalance.payDayStart) {
    				subBalance.stakeSessions[sessionId] = StakeSession({
    					staker: staker,
    					shares: shares,
    					start: start,
    					end: end,
    					finishTime: 0,
    					withdrawn: false
    					});
    				subBalance.userStakings[staker].push(sessionId);

    				subBalance.totalShares = subBalance.totalShares.add(shares);
    			}
    		}
    	}

    	if (shares > 0) {
	    	currentSharesTotalSupply = currentSharesTotalSupply.add(shares);    		
    	}
	}

    function callOutcomeStakerTrigger(
        address staker,
        uint256 sessionId,
        uint256 start,
        uint256 end,
        uint256 shares
    ) 
        external
        override
    {
 	   	require(end > start, 'end must be more than start');
    	uint256 userPeriod = end.sub(start);

    	if (userPeriod > DAY && shares > 0) {
    		 for (uint256 i = 0; i < subBalanceList.length; i++) {
    		 	SubBalance storage subBalance = subBalanceList[i];

    			if (end > subBalance.payDayStart) {
                    require(subBalance.stakeSessions[sessionId].staker == staker, "staker address does not matching");

    				subBalance.stakeSessions[sessionId].finishTime = now;

    				if (shares > subBalanceYearOne.totalShares) {
    					subBalanceYearOne.totalShares = 0;
    				} else {
    					subBalanceYearOne.totalShares = subBalanceYearOne.totalShares.sub(shares);
    				}
    			}
    		}
    	}

    	if (shares > 0) {
    		shares > currentSharesTotalSupply ? currentSharesTotalSupply = 0 : currentSharesTotalSupply.sub(shares);
    	}
    }

    function generatePool() external returns (bool) {
    	for (uint256 i = 0; i < subBalanceList.length; i++) {
    		SubBalance storage subBalance = subBalanceList[i];

    		if (now > subBalance.payDayStart && !subBalance.minted) {
    			uint256 yearTokens = getPoolFromBPD(i);
    			(uint256 bpdTokens, uint256 addAmount) = _bpdAmountFromRaw(yearTokens);

    			IToken(mainToken).mint(address(this), addAmount);
    			subBalance.totalWithdrawAmount = bpdTokens;
    			subBalance.minted = true;
                return true;
    		}
    	}
    }

    function _saveWithdrawn(uint256 sessionId) internal {
    	for (uint256 i = 0; i < subBalanceList.length; i++) {
    		SubBalance storage subBalance = subBalanceList[i];
			subBalance.stakeSessions[sessionId].withdrawn = true;
		}
    }

    function _addDays(uint256 originalTimestamp, uint256 period) internal pure returns (uint256 newTimestamp) {
    	newTimestamp = originalTimestamp.add(DAY.mul(period));
    }

    function getPoolFromBPD(uint256 poolNumber) internal returns (uint256 poolAmount) {
    	poolAmount = IBPD(bigPayDayPool).transferYearlyPool(poolNumber);
    }

    function _bpdAmountFromRaw(uint256 yearTokenAmount) internal view returns (uint256 totalAmount, uint256 addAmount) {
    	uint256 currentTokenTotalSupply = IERC20(mainToken).totalSupply();

        uint256 inflation = uint256(21087e16).mul(currentTokenTotalSupply.add(currentSharesTotalSupply));

        
        uint256 criticalMassCoeff = IForeignSwap(foreignSwap).getCurrentClaimedAmount().div(
            IForeignSwap(foreignSwap).getTotalSnapshotAmount());

       uint256 viralityCoeff = IForeignSwap(foreignSwap).getCurrentClaimedAddresses().div(
            IForeignSwap(foreignSwap).getTotalSnapshotAddresses());

        uint256 totalUprisingCoeff = uint256(1).add(criticalMassCoeff).add(viralityCoeff);

        totalAmount = yearTokenAmount.add(inflation).mul(totalUprisingCoeff);
        addAmount = totalAmount.sub(yearTokenAmount);
    }

}