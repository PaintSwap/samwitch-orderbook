// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract TestERC1155NoRoyalty is ERC1155 {
  uint64 public nextId = 1;

  constructor() ERC1155("") {}

  function mint(uint256 quantity) external {
    _mint(_msgSender(), nextId++, quantity, "");
  }

  function mintSpecificId(uint256 id, uint256 quantity) external {
    _mint(_msgSender(), id, quantity, "");
  }

  function mintBatch(uint256[] memory amounts) external {
    uint256[] memory ids = new uint256[](amounts.length);
    for (uint256 i = 0; i < amounts.length; ++i) {
      ids[i] = nextId++;
    }
    _mintBatch(_msgSender(), ids, amounts, "");
  }
}
