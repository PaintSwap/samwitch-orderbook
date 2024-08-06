// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IBrushToken} from "../interfaces/IBrushToken.sol";

contract MockBrushToken is ERC20("PaintSwap Token", "BRUSH"), IBrushToken {
  uint256 public amountBurnt;

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function burn(uint256 amount) external {
    amountBurnt += amount;
    _burn(msg.sender, amount);
  }
}
