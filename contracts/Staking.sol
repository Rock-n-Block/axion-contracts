// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IAuction.sol";
import "./interfaces/IStaking.sol";
import "./interfaces/ISubBalances.sol";

contract Staking is IStaking, AccessControl {
    using SafeMath for uint256;

    uint256 private _sessionsIds;

    bytes32 public constant EXTERNAL_STAKER_ROLE = keccak256(
        "EXTERNAL_STAKER_ROLE"
    );

    struct Payout {
        uint256 payout;
        uint256 sharesTotalSupply;
    }

    struct Session {
        uint256 amount;
        uint256 start;
        uint256 end;
        uint256 shares;
    }

    address public mainToken;
    address public auction;
    address public subBalances;
    uint256 public shareRate;
    uint256 public sharesTotalSupply;
    uint256 public lastMainTokenBalance;
    uint256 public nextPayoutCall;
    uint256 public stepTimestamp;
    uint256 public startContract;
    bool public init_;

    mapping(address => mapping(uint256 => Session)) public sessionDataOf;
    mapping(address => uint256[]) public sessionsOf;
    Payout[] public payouts;

    modifier onlyExternalStaker() {
        require(
            hasRole(EXTERNAL_STAKER_ROLE, _msgSender()),
            "Caller is not a external staker"
        );
        _;
    }

    constructor() public {
        init_ = false;
    }

    function init(
        address _mainToken,
        address _auction,
        address _subBalances,
        address _externalStaker,
        uint256 _stepTimestamp
    ) external {
        require(!init_, "NativeSwap: init is active");
        _setupRole(EXTERNAL_STAKER_ROLE, _externalStaker);
        mainToken = _mainToken;
        auction = _auction;
        subBalances = _subBalances;
        shareRate = 1e18;
        lastMainTokenBalance = 0;
        stepTimestamp = _stepTimestamp;
        nextPayoutCall = now.add(_stepTimestamp);
        startContract = now;
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
        require(stakingDays > 0, "stakingDays < 1");

        uint256 start = now;
        uint256 end = now.add(stakingDays.mul(stepTimestamp));

        IToken(mainToken).burn(msg.sender, amount);
        _sessionsIds = _sessionsIds.add(1);
        uint256 sessionId = _sessionsIds;
        uint256 shares = _getStakersSharesAmount(amount, start, end);
        sharesTotalSupply = sharesTotalSupply.add(shares);

        sessionDataOf[msg.sender][sessionId] = Session({
            amount: amount,
            start: start,
            end: end,
            shares: shares
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
        address account,
        uint256 amount,
        uint256 stakingDays
    ) external override onlyExternalStaker {
        require(stakingDays > 0, "stakingDays < 1");

        uint256 start = now;
        uint256 end = now.add(stakingDays.mul(stepTimestamp));

        IToken(mainToken).burn(account, amount);
        _sessionsIds = _sessionsIds.add(1);
        uint256 sessionId = _sessionsIds;
        uint256 shares = _getStakersSharesAmount(amount, start, end);
        sharesTotalSupply = sharesTotalSupply.add(shares);

        sessionDataOf[account][sessionId] = Session({
            amount: amount,
            start: start,
            end: end,
            shares: shares
        });

        sessionsOf[account].push(sessionId);

        ISubBalances(subBalances).callIncomeStakerTrigger(
            account,
            sessionId,
            start,
            end,
            shares
        );
    }

    function unstake(uint256 sessionId) external {
        require(
            sessionDataOf[msg.sender][sessionId].shares > 0,
            "NativeSwap: Shares balance is empty"
        );

        IToken(mainToken).mint(
            address(this),
            sessionDataOf[msg.sender][sessionId].amount
        );

        uint256 stakingInterest;

        for (uint256 i = 0; i < payouts.length; i++) {
            uint256 payout = payouts[i]
                .payout
                .mul(sessionDataOf[msg.sender][sessionId].shares)
                .div(payouts[i].sharesTotalSupply);

            stakingInterest = stakingInterest.add(payout);
        }

        uint256 newShareRate = _getShareRate(
            sessionDataOf[msg.sender][sessionId].amount,
            sessionId,
            sessionDataOf[msg.sender][sessionId].start,
            sessionDataOf[msg.sender][sessionId].end,
            stakingInterest
        );

        if (newShareRate > shareRate) {
            shareRate = newShareRate;
        }

        sharesTotalSupply = sharesTotalSupply.sub(
            sessionDataOf[msg.sender][sessionId].shares
        );

        uint256 stakingDays = (
            sessionDataOf[msg.sender][sessionId].end.sub(
                sessionDataOf[msg.sender][sessionId].start
            )
        )
            .div(stepTimestamp);

        uint256 daysStaked = (
            now.sub(sessionDataOf[msg.sender][sessionId].start)
        )
            .div(stepTimestamp);

        uint256 amountAndInterest = sessionDataOf[msg.sender][sessionId]
            .amount
            .add(stakingInterest);

        // Early
        if (stakingDays > daysStaked) {
            uint256 payOutAmount = amountAndInterest.mul(daysStaked).div(
                stakingDays
            );

            uint256 earlyUnstakePenalty = amountAndInterest.sub(payOutAmount);

            uint256 finalPayotAmount = amountAndInterest.sub(
                earlyUnstakePenalty
            );

            uint256 currentMainTokenBalanceOfContract = IERC20(mainToken)
                .balanceOf(address(this));

            if (finalPayotAmount > currentMainTokenBalanceOfContract) {
                IToken(mainToken).mint(
                    address(this),
                    finalPayotAmount.sub(currentMainTokenBalanceOfContract)
                );
            }

            // To auction
            IERC20(mainToken).transfer(auction, earlyUnstakePenalty);
            IAuction(auction).callIncomeWeeklyTokensTrigger(
                earlyUnstakePenalty
            );

            // To account
            IERC20(mainToken).transfer(msg.sender, finalPayotAmount);

            return;
        }

        // In time
        if (stakingDays <= daysStaked && daysStaked < stakingDays.add(14)) {
            uint256 finalPayotAmount = amountAndInterest;

            uint256 currentMainTokenBalanceOfContract = IERC20(mainToken)
                .balanceOf(address(this));

            // IAuction(auction).callIncomeTokensTrigger();
            if (finalPayotAmount > currentMainTokenBalanceOfContract) {
                IToken(mainToken).mint(
                    address(this),
                    finalPayotAmount.sub(currentMainTokenBalanceOfContract)
                );
            }

            IERC20(mainToken).transfer(msg.sender, finalPayotAmount);
            return;
        }

        // Late
        if (
            stakingDays.add(14) <= daysStaked &&
            daysStaked < stakingDays.add(714)
        ) {
            uint256 daysAfterStaking = daysStaked.sub(stakingDays);

            uint256 payOutAmount = amountAndInterest
                .mul(uint256(714).sub(daysAfterStaking))
                .div(700);

            uint256 lateUnstakePenalty = amountAndInterest.sub(payOutAmount);

            uint256 finalPayotAmount = amountAndInterest.sub(
                lateUnstakePenalty
            );

            uint256 currentMainTokenBalanceOfContract = IERC20(mainToken)
                .balanceOf(address(this));

            // IAuction(auction).callIncomeTokensTrigger();
            if (finalPayotAmount > currentMainTokenBalanceOfContract) {
                IToken(mainToken).mint(
                    address(this),
                    finalPayotAmount.sub(currentMainTokenBalanceOfContract)
                );
            }

            // To auction
            IERC20(mainToken).transfer(auction, lateUnstakePenalty);
            IAuction(auction).callIncomeWeeklyTokensTrigger(lateUnstakePenalty);

            // IAuction(auction).callIncomeTokensTrigger();

            // To account
            IERC20(mainToken).transfer(
                msg.sender,
                amountAndInterest.sub(finalPayotAmount)
            );

            return;
        }

        // Nothing
        if (stakingDays.add(714) <= daysStaked) {
            // To auction
            IERC20(mainToken).transfer(auction, amountAndInterest);
            IAuction(auction).callIncomeWeeklyTokensTrigger(amountAndInterest);

            return;
        }

        ISubBalances(subBalances).callOutcomeStakerTrigger(
            msg.sender,
            sessionId,
            sessionDataOf[msg.sender][sessionId].start,
            sessionDataOf[msg.sender][sessionId].end,
            sessionDataOf[msg.sender][sessionId].shares
        );

        sessionDataOf[msg.sender][sessionId].shares = 0;
    }

    function readUnstake(address account, uint256 sessionId)
        external
        view
        returns (uint256, uint256)
    {
        if (sessionDataOf[account][sessionId].shares == 0) return (0, 0);

        uint256 stakingInterest;

        for (uint256 i = 0; i < payouts.length; i++) {
            uint256 payout = payouts[i]
                .payout
                .mul(sessionDataOf[account][sessionId].shares)
                .div(payouts[i].sharesTotalSupply);

            stakingInterest = stakingInterest.add(payout);
        }

        uint256 stakingDays = (
            sessionDataOf[account][sessionId].end.sub(
                sessionDataOf[account][sessionId].start
            )
        )
            .div(stepTimestamp);

        uint256 daysStaked = (now.sub(sessionDataOf[account][sessionId].start))
            .div(stepTimestamp);

        uint256 amountAndInterest = sessionDataOf[account][sessionId]
            .amount
            .add(stakingInterest);

        // Early
        if (stakingDays > daysStaked) {
            uint256 payOutAmount = amountAndInterest.mul(
                daysStaked.div(stakingDays)
            );

            uint256 earlyUnstakePenalty = amountAndInterest.sub(payOutAmount);

            return (
                amountAndInterest.sub(earlyUnstakePenalty),
                earlyUnstakePenalty
            );
        }

        // In time
        if (stakingDays <= daysStaked && daysStaked < stakingDays.add(14)) {
            return (amountAndInterest, 0);
        }

        // Late
        if (
            stakingDays.add(14) <= daysStaked &&
            daysStaked < stakingDays.add(714)
        ) {
            uint256 daysAfterStaking = daysStaked.sub(stakingDays);

            uint256 payOutAmount = amountAndInterest
                .mul(uint256(686).add(daysAfterStaking))
                .div(700);

            uint256 lateUnstakePenalty = amountAndInterest.sub(payOutAmount);

            return (
                amountAndInterest.sub(lateUnstakePenalty),
                lateUnstakePenalty
            );
        }

        // Nothing
        if (stakingDays.add(714) <= daysStaked) {
            return (0, amountAndInterest);
        }
    }

    function makePayout() external {
        require(now >= nextPayoutCall, "NativeSwap: Wrong payout time");
        payouts.push(
            Payout({payout: _getPayout(), sharesTotalSupply: sharesTotalSupply})
        );

        nextPayoutCall = nextPayoutCall.add(stepTimestamp);
    }

    function readPayout() external view returns (uint256) {
        uint256 currentTokenBalance = IERC20(mainToken).balanceOf(
            address(this)
        );

        uint256 amountTokenInDay = currentTokenBalance.sub(
            lastMainTokenBalance
        );

        uint256 currentTokenTotalSupply = IERC20(mainToken).totalSupply();

        uint256 inflation = uint256(8)
            .mul(currentTokenTotalSupply.add(sharesTotalSupply))
            .div(365);

        uint256 finalAmnount = amountTokenInDay.add(inflation);

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

        uint256 inflation = uint256(8)
            .mul(currentTokenTotalSupply.add(sharesTotalSupply))
            .div(365);

        IToken(mainToken).mint(address(this), inflation);

        lastMainTokenBalance = currentTokenBalance;

        uint256 finalAmnount = amountTokenInDay.add(inflation);

        return finalAmnount;
    }

    function _getStakersSharesAmount(
        uint256 amount,
        uint256 start,
        uint256 end
    ) internal view returns (uint256) {
        uint256 stakingDays = (end.sub(start)).div(stepTimestamp);
        uint256 numerator = amount.mul(uint256(1819).add(stakingDays));
        uint256 denominator = uint256(1820).mul(shareRate);

        return (numerator).mul(1e18).div(denominator);
    }

    function _getShareRate(
        uint256 amount,
        uint256 sessionId,
        uint256 start,
        uint256 end,
        uint256 stakingInterest
    ) internal view returns (uint256) {
        uint256 stakingDays = (end.sub(start)).div(stepTimestamp);

        uint256 numerator = (amount.add(stakingInterest)).mul(
            uint256(1819).add(stakingDays)
        );

        uint256 denominator = uint256(1820).mul(
            sessionDataOf[msg.sender][sessionId].shares
        );

        return (numerator).mul(1e18).div(denominator);
    }

    // Helper
    function getNow0x() external view returns (uint256) {
        return now;
    }
}
