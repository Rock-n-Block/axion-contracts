// SPDX-License-Identifier: MIT

// Rinkeby faucet: https://faucet.rinkeby.io/

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract TERC20L is ERC20 {
    using SafeMath for uint256;

    event Deposit(address indexed dst, uint256 wad, uint256 amountOut);
    event Withdrawal(address indexed src, uint256 wad, uint256 amountOut);

    uint256 public constant LIMIT = 250000000000e18;
    uint256 public constant RATE = 1e6;

    constructor(string memory name, string memory symbol)
        public
        ERC20(name, symbol)
    {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        require(totalSupply() < LIMIT, "limit exceeded");
        uint256 amountOut = msg.value.mul(RATE);
        require(totalSupply().add(amountOut) < LIMIT, "insufficient reserve");
        _mint(msg.sender, amountOut);
        Deposit(msg.sender, msg.value, amountOut);
    }

    function withdraw(uint256 wad) external {
        require(balanceOf(msg.sender) >= wad, "insufficient funds");
        uint256 amountOut = wad.mul(1e18);
        uint256 amountToBurn = amountOut.div(RATE);
        _burn(msg.sender, amountToBurn);
        msg.sender.transfer(amountOut);
        Withdrawal(msg.sender, amountToBurn, amountOut);
    }
}
