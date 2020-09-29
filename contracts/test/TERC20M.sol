// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TERC20M is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 amountToMint
    ) public ERC20(name, symbol) {
        _mint(msg.sender, amountToMint);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
