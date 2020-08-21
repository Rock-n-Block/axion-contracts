// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/ISubBalances.sol";

contract Staking is AccessControl {
    using SafeMath for uint256;

    uint256 private _sessionsIds;

    bytes32 public constant EXTERNAL_STAKER_ROLE = keccak256(
        "EXTERNAL_STAKER_ROLE"
    );

    uint256 public delta;

    struct Payout {
        uint256 payout;
        uint256 sharesTotalSupply;
    }

    struct Session {
        uint256 amount;
        uint256 start;
        uint256 end;
        uint256 shares;
        bool sessionIsActive;
    }

    address public mainToken;
    address public subBalances;
    uint256 public shareRate;
    uint256 public sharesTotalSupply;
    uint256 public lastMainTokenBalance;
    uint256 public nextPayoutCall;
    uint256 public constant DAY = 86400;
    bool public init_;

    mapping(address => mapping(uint256 => Session)) public sessionDataOf;
    mapping(address => uint256[]) public sessionsOf;
    Payout[] public payouts;

    constructor() public {
        init_ = false;
    }

    function init(
        address _mainToken,
        address _subBalances,
        address _externalStaker
    ) external {
        require(!init_, "NativeSwap: init is active");
        _setupRole(EXTERNAL_STAKER_ROLE, _externalStaker);
        mainToken = _mainToken;
        subBalances = _subBalances;
        shareRate = 1;
        lastMainTokenBalance = 0;
        nextPayoutCall = now.add(DAY);
        init_ = true;
    }

    function sessionsOf_(address account)
        external
        view
        returns (uint256[] memory)
    {
        return sessionsOf[account];
    }

    function stake(uint256 amount, uint256 stakingDays) external {
        uint256 start = now;
        uint256 end = now.add(stakingDays.mul(86400));

        IERC20(mainToken).transferFrom(msg.sender, address(this), amount);
        _sessionsIds = _sessionsIds.add(1);
        uint256 sessionId = _sessionsIds;
        uint256 shares = _getStakersSharesAmount(amount, start, end);
        sharesTotalSupply = sharesTotalSupply.add(shares);

        sessionDataOf[msg.sender][sessionId] = Session({
            amount: amount,
            start: start,
            end: end,
            shares: shares,
            sessionIsActive: true
        });

        sessionsOf[msg.sender].push(sessionId);

        ISubBalances(subBalances).callIncomeStakerTrigger(
            msg.sender,
            sessionId,
            start,
            end,
            shares
        );
    }

    function externalStake(
        uint256 amount,
        uint256 stakingDays,
        address staker
    ) external {
        require(
            hasRole(EXTERNAL_STAKER_ROLE, msg.sender),
            "Caller is not a external staker"
        );

        uint256 start = now;
        uint256 end = now.add(stakingDays.mul(86400));

        IERC20(mainToken).transferFrom(msg.sender, address(this), amount);
        _sessionsIds = _sessionsIds.add(1);
        uint256 sessionId = _sessionsIds;
        uint256 shares = _getStakersSharesAmount(amount, start, end);
        sharesTotalSupply = sharesTotalSupply.add(shares);

        sessionDataOf[staker][sessionId] = Session({
            amount: amount,
            start: start,
            end: end,
            shares: shares,
            sessionIsActive: true
        });

        sessionsOf[staker].push(sessionId);

        ISubBalances(subBalances).callIncomeStakerTrigger(
            staker,
            sessionId,
            start,
            end,
            shares
        );
    }

    function unstake(uint256 sessionId) external {
        require(
            sessionDataOf[msg.sender][sessionId].sessionIsActive,
            "NativeSwap: Session is not active"
        );

        sessionDataOf[msg.sender][sessionId].sessionIsActive = false;

        uint256 accumulator;

        for (uint256 i = 0; i < payouts.length; i++) {
            uint256 payout = payouts[i]
                .payout
                .mul(sessionDataOf[msg.sender][sessionId].shares)
                .div(payouts[i].sharesTotalSupply);

            accumulator = accumulator.add(payout);
        }

        uint256 newShareRate = _getShareRate(
            sessionDataOf[msg.sender][sessionId].amount,
            sessionId,
            sessionDataOf[msg.sender][sessionId].start,
            sessionDataOf[msg.sender][sessionId].end,
            accumulator
        );

        if (newShareRate > shareRate) {
            shareRate = newShareRate;
        }

        uint256 estimatePeriod = sessionDataOf[msg.sender][sessionId].end.sub(
            sessionDataOf[msg.sender][sessionId].start
        );

        uint256 existingPeriod = now.sub(
            sessionDataOf[msg.sender][sessionId].start
        );

        if (estimatePeriod > existingPeriod) {
            uint256 localDelta = accumulator
                .mul(estimatePeriod.sub(existingPeriod))
                .div(estimatePeriod);

            delta = delta.add(localDelta);

            IERC20(mainToken).transfer(msg.sender, accumulator.sub(localDelta));

            return;
        }

        if (estimatePeriod < existingPeriod) {
            uint256 daysAfterGracePeriod = now.sub(
                sessionDataOf[msg.sender][sessionId].end
            );

            uint256 localDelta = accumulator
                .mul(daysAfterGracePeriod.sub(14))
                .div(700);

            delta = delta.add(localDelta);

            IERC20(mainToken).transfer(msg.sender, accumulator.sub(localDelta));

            return;
        }

        if (estimatePeriod == existingPeriod) {
            IERC20(mainToken).transfer(msg.sender, accumulator);
            return;
        }

        ISubBalances(subBalances).callOutcomeStakerTrigger(
            msg.sender,
            sessionId,
            sessionDataOf[msg.sender][sessionId].start,
            sessionDataOf[msg.sender][sessionId].end,
            sessionDataOf[msg.sender][sessionId].shares
        );
    }

    function makePayout() external {
        require(now >= nextPayoutCall, "NativeSwap: Wrong payout time");
        payouts.push(
            Payout({payout: _getPayout(), sharesTotalSupply: sharesTotalSupply})
        );

        nextPayoutCall = nextPayoutCall.add(DAY);
    }

    function readPayout() external view returns (uint256) {
        uint256 currentTokenBalance = IERC20(mainToken).balanceOf(
            address(this)
        );

        uint256 amountTokenInDay = currentTokenBalance.sub(
            lastMainTokenBalance
        );

        uint256 currentTokenTotalSupply = IERC20(mainToken).totalSupply();

        uint256 inflation = uint256(21087e16).mul(
            currentTokenTotalSupply.add(sharesTotalSupply)
        );

        uint256 finalAmnount = amountTokenInDay.add(inflation).add(delta);

        return finalAmnount;
    }

    function _getPayout() internal returns (uint256) {
        uint256 currentTokenBalance = IERC20(mainToken).balanceOf(
            address(this)
        );

        uint256 amountTokenInDay = currentTokenBalance.sub(
            lastMainTokenBalance
        );

        uint256 currentTokenTotalSupply = IERC20(mainToken).totalSupply();

        uint256 inflation = uint256(21087e16).mul(
            currentTokenTotalSupply.add(sharesTotalSupply)
        );

        IToken(mainToken).mint(address(this), inflation);

        lastMainTokenBalance = currentTokenBalance;

        uint256 finalAmnount = amountTokenInDay.add(inflation).add(delta);

        delta = 0;

        return finalAmnount;
    }

    function _getStakersSharesAmount(
        uint256 amount,
        uint256 start,
        uint256 end
    ) internal view returns (uint256) {
        uint256 coeff = uint256(1).add((end.sub(start).sub(1)).div(1820));
        return amount.mul(coeff).div(shareRate);
    }

    function _getShareRate(
        uint256 amount,
        uint256 sessionId,
        uint256 start,
        uint256 end,
        uint256 accumulator
    ) internal view returns (uint256) {
        return
            (amount.add(accumulator))
                .mul(uint256(1).add(end.sub(start).sub(1)).div(1820))
                .div(sessionDataOf[msg.sender][sessionId].shares);
    }

    // Helper
    function getNow() external view returns (uint256) {
        return now;
    }
}
