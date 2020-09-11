// SPDX-License-Identifier: MIT

pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IToken.sol";
import "./interfaces/IAuction.sol";

contract NativeSwap {
    using SafeMath for uint256;

    uint256 public start;
    uint256 public stepTimestamp;
    IERC20 public swapToken;
    IToken public mainToken;
    IAuction public auction;

    bool public init_;

    mapping(address => uint256) public swapTokenBalanceOf;

    constructor() public {
        init_ = false;
    }

    function init(
        uint256 _stepTimestamp,
        address _swapToken,
        address _mainToken,
        address _auction
    ) external {
        require(!init_, "init is active");
        stepTimestamp = _stepTimestamp;
        swapToken = IERC20(_swapToken);
        mainToken = IToken(_mainToken);
        auction = IAuction(_auction);
        start = now;
        init_ = true;
    }

    function deposit(uint256 _amount) external {
        require(
            swapToken.transferFrom(msg.sender, address(this), _amount),
            "NativeSwap: transferFrom error"
        );
        swapTokenBalanceOf[msg.sender] = swapTokenBalanceOf[msg.sender].add(
            _amount
        );
    }

    function withdraw(uint256 _amount) external {
        require(_amount >= swapTokenBalanceOf[msg.sender], "balance < amount");
        swapTokenBalanceOf[msg.sender] = swapTokenBalanceOf[msg.sender].sub(
            _amount
        );
        swapToken.transfer(msg.sender, _amount);
    }

    function swapNativeToken() external {
        uint256 amount = swapTokenBalanceOf[msg.sender];
        uint256 deltaPenalty = calculateDeltaPenalty(amount);
        uint256 amountOut = amount.sub(deltaPenalty);
        require(amount > 0, "swapNativeToken: amount == 0");
        swapTokenBalanceOf[msg.sender] = 0;
        mainToken.mint(address(auction), deltaPenalty);
        auction.callIncomeDailyTokensTrigger(deltaPenalty);
        mainToken.mint(msg.sender, amountOut);
    }

    function calculateDeltaPenalty(uint256 amount)
        public
        view
        returns (uint256)
    {
        uint256 stepsFromStart = calculateStepsFromStart();
        if (stepsFromStart > 350) return amount;
        return amount.mul(stepsFromStart).div(350);
    }

    function calculateStepsFromStart() public view returns (uint256) {
        return now.sub(start).div(stepTimestamp);
    }
}
