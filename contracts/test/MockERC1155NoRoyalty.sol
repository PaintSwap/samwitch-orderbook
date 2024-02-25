// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

contract MockERC1155NoRoyalty is ERC1155 {
  uint64 public nextId = 1;

  constructor() ERC1155("") {}

  function mint(uint _quantity) external {
    _mint(_msgSender(), nextId++, _quantity, "");
  }

  function mintSpecificId(uint _id, uint _quantity) external {
    _mint(_msgSender(), _id, _quantity, "");
  }

  function mintBatch(uint[] memory _amounts) external {
    uint[] memory ids = new uint[](_amounts.length);
    for (uint i = 0; i < _amounts.length; ++i) {
      ids[i] = nextId++;
    }
    _mintBatch(_msgSender(), ids, _amounts, "");
  }
}
