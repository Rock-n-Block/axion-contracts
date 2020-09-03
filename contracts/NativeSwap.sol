// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IAuction.sol";

contract NativeSwap {
    using SafeMath for uint256;

    uint256 private start;
    uint256 private stepTimestamp;
    address private swapToken;
    address private mainToken;
    address private dailyAuction;

    bool public init_;

    mapping(address => uint256) private swapTokenBalanceOf;

    constructor() public {
        init_ = false;
    }

    function init(
        uint256 _stepTimestamp,
        address _swapToken,
        address _mainToken,
        address _dailyAuction
    ) external {
        require(!init_, "init is active");
        stepTimestamp = _stepTimestamp;
        swapToken = _swapToken;
        mainToken = _mainToken;
        dailyAuction = _dailyAuction;
        start = now;
        init_ = true;
    }

    function getStart() external view returns (uint256) {
        return start;
    }

    function getStepTimestamp() external view returns (uint256) {
        return stepTimestamp;
    }

    function getSwapToken() external view returns (address) {
        return swapToken;
    }

    function getMainToken() external view returns (address) {
        return mainToken;
    }

    function getDailyAuction() external view returns (address) {
        return dailyAuction;
    }

    function getSwapTokenBalanceOf(address account)
        external
        view
        returns (uint256)
    {
        return swapTokenBalanceOf[account];
    }

    function deposit(uint256 _amount) external {
        IERC20(swapToken).transferFrom(msg.sender, address(this), _amount);
        swapTokenBalanceOf[msg.sender] = swapTokenBalanceOf[msg.sender].add(
            _amount
        );
    }

    function withdraw(uint256 _amount) external {
        require(_amount >= swapTokenBalanceOf[msg.sender], "balance < amount");
        swapTokenBalanceOf[msg.sender] = swapTokenBalanceOf[msg.sender].sub(
            _amount
        );
        IERC20(swapToken).transfer(msg.sender, _amount);
    }

    function swapNativeToken() external {
        uint256 amount = swapTokenBalanceOf[msg.sender];
        uint256 deltaPenalty = calculateDeltaPenalty(amount);
        uint256 amountOut = amount.sub(deltaPenalty);
        require(amount > 0, "swapNativeToken: amount == 0");
        swapTokenBalanceOf[msg.sender] = 0;
        IToken(mainToken).mint(dailyAuction, deltaPenalty);
        IAuction(dailyAuction).callIncomeDailyTokensTrigger(deltaPenalty);
        IToken(mainToken).mint(msg.sender, amountOut);
    }

    function readSwapNativeToken(address account)
        external
        view
        returns (uint256, uint256)
    {
        uint256 amount = swapTokenBalanceOf[account];
        if (amount == 0) return (0, 0);
        uint256 deltaPenalty = calculateDeltaPenalty(amount);
        uint256 amountOut = amount.sub(deltaPenalty);
        return (amountOut, deltaPenalty);
    }

    function calculateDeltaPenalty(uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 stepsFromStart = (now.sub(start)).div(stepTimestamp);
        if (stepsFromStart > 350) return amount;
        return amount.mul(stepsFromStart).div(350);
    }
}
