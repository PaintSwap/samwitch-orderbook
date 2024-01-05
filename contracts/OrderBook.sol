// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IBrushToken} from "./interfaces/IBrushToken.sol";

import {BokkyPooBahsRedBlackTreeLibrary} from "./BokkyPooBahsRedBlackTreeLibrary.sol";

contract OrderBook is ERC1155Holder, UUPSUpgradeable, OwnableUpgradeable {
  using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;

  event OrdersPlaced(LimitOrder[] orders, address from);
  // TODO: Bulk this event
  event OrderMatched(address maker, address taker, uint tokenId, uint quantity, uint price);
  event OrdersCancelled(uint[] ids);
  event AddedToBook(bool isBuy, OrderBookEntry orderBookEntry, uint price);
  event RemovedFromBook(uint id);
  event PartialRemovedFromBook(uint id, uint quantityRemoved);
  event ClaimedTokens(address maker, uint amount);
  event ClaimedNFTs(address maker, uint[] tokenIds, uint[] amounts);
  event SetTokenIdInfos(uint[] tokenIds, TokenIdInfo[] _tokenIdInfos);

  error NotERC1155();
  error NoQuantity();
  error OrderNotFound();
  error PriceNotMultipleOfTick(uint tick);
  error TokenDoesntExist(uint tokenId);
  error PriceZero();
  error LengthMismatch();
  error QuantityRemainingTooLow();
  error NotMaker();
  error NothingToClaim();

  enum OrderSide {
    Buy,
    Sell
  }

  struct LimitOrder {
    OrderSide side;
    uint tokenId;
    uint64 price;
    uint32 quantity;
  }

  struct OrderBookEntry {
    address maker;
    uint32 quantity;
    uint64 id;
  }

  struct TokenIdInfo {
    uint128 tick;
    uint128 minQuantity;
  }

  struct CancelOrderInfo {
    OrderSide side;
    uint tokenId;
    uint64 price;
  }

  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) public asks;
  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) public bids;

  IERC1155 public nft;
  IBrushToken public token;

  address public devAddr;
  uint8 public devFee; // Base 10000, max 2.55%
  uint8 public burntFee;
  uint16 public maxOrdersPerPrice;
  bool public supportsERC2981;
  uint64 public nextOrderEntryId;

  mapping(uint tokenId => TokenIdInfo tokenIdInfo) public tokenIdInfos;

  mapping(uint tokenId => mapping(uint price => OrderBookEntry[])) public askValues;
  mapping(uint tokenId => mapping(uint price => OrderBookEntry[])) public bidValues;

  // Check has much gas changes if actually just transferring the tokens.
  mapping(address user => uint amount) private brushClaimable;
  mapping(address user => mapping(uint tokenId => uint amount)) private tokenIdsClaimable;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _nft, address _token, address _devAddr) external initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(msg.sender);

    nft = IERC1155(_nft);
    if (!nft.supportsInterface(type(IERC1155).interfaceId)) {
      revert NotERC1155();
    }
    token = IBrushToken(_token);
    supportsERC2981 = IERC1155(_nft).supportsInterface(type(IERC2981).interfaceId);

    devFee = 30; // 30 = 0.3% fee,
    devAddr = _devAddr;
    burntFee = 30; // 30 = 0.3% fee,
    maxOrdersPerPrice = 100;

    nextOrderEntryId = 1;
  }

  function limitOrders(LimitOrder[] calldata _limitOrders) external {
    uint royalty;
    uint dev;
    uint burn;
    uint brushTransferToUs;
    uint brushTransferFromUs;
    uint lengthToUs;
    uint[] memory idsToUs = new uint[](_limitOrders.length);
    uint[] memory amountsToUs = new uint[](_limitOrders.length);
    uint lengthFromUs;
    uint[] memory idsFromUs = new uint[](_limitOrders.length);
    uint[] memory amountsFromUs = new uint[](_limitOrders.length);
    for (uint i = 0; i < _limitOrders.length; ++i) {
      OrderSide side = _limitOrders[i].side;
      uint tokenId = _limitOrders[i].tokenId;
      uint quantity = _limitOrders[i].quantity;
      uint price = _limitOrders[i].price;
      (uint32 quantityRemaining, uint cost) = _limitOrder(_limitOrders[i]);

      if (side == OrderSide.Buy) {
        brushTransferToUs += cost + uint(price) * quantityRemaining;
        (, uint _royalty, uint _dev, uint _burn) = _calcFees(tokenId, cost);
        royalty += _royalty;
        dev += _dev;
        burn += _burn;
        // Transfer the NFTs straight to the user
        if (cost > 0) {
          idsFromUs[lengthFromUs] = tokenId;
          amountsFromUs[lengthFromUs++] = quantity - quantityRemaining;
        }
      } else {
        // Selling, transfer all NFTs to us
        idsToUs[lengthToUs] = tokenId;
        amountsToUs[lengthToUs++] = quantity;

        // Transfer tokens to the seller if any have sold
        if (cost > 0) {
          (, uint _royalty, uint _dev, uint _burn) = _calcFees(tokenId, cost);
          royalty += _royalty;
          dev += _dev;
          burn += _burn;
          uint fees = _royalty + _dev + _burn;
          brushTransferFromUs += cost - fees;
        }
      }
    }

    assembly ("memory-safe") {
      mstore(idsToUs, lengthToUs)
      mstore(amountsToUs, lengthToUs)
      mstore(idsFromUs, lengthFromUs)
      mstore(amountsFromUs, lengthFromUs)
    }

    if (brushTransferToUs > 0) {
      token.transferFrom(msg.sender, address(this), brushTransferToUs);
    }

    if (brushTransferFromUs > 0) {
      _safeTransferFromUs(msg.sender, brushTransferFromUs);
    }

    if (idsToUs.length > 0) {
      nft.safeBatchTransferFrom(msg.sender, address(this), idsToUs, amountsToUs, "");
    }

    if (idsFromUs.length > 0) {
      _safeBatchTransferNFTsFromUs(msg.sender, idsFromUs, amountsFromUs);
    }

    _sendFees(royalty, dev, burn);
    emit OrdersPlaced(_limitOrders, msg.sender);
  }

  // function batchLimitOrder

  // TODO, require minimums so that we can limit the amount of orders in the book?
  function buyTakeFromOrderBook(
    uint _tokenId,
    uint80 _price,
    uint32 _quantity
  ) private returns (uint32 quantityRemaining, uint cost) {
    quantityRemaining = _quantity;
    while (quantityRemaining > 0) {
      uint64 lowestAsk = getLowestAsk(_tokenId);
      if (lowestAsk == 0 || lowestAsk > _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numFullyConsumed = 0;

      for (uint i = asks[_tokenId].getNode(lowestAsk).tombstoneOffset; i < askValues[_tokenId][lowestAsk].length; ++i) {
        uint32 quantityL3 = askValues[_tokenId][lowestAsk][i].quantity;
        uint quantityNFTClaimable = 0;
        address maker = askValues[_tokenId][lowestAsk][i].maker;
        if (quantityRemaining >= quantityL3) {
          // Consume this whole order
          quantityRemaining -= quantityL3;
          ++numFullyConsumed;
          quantityNFTClaimable = quantityL3;
        } else {
          // Eat into the order
          askValues[_tokenId][lowestAsk][i].quantity -= quantityRemaining;
          quantityNFTClaimable = quantityRemaining;
          quantityRemaining = 0;
        }
        cost += quantityNFTClaimable * lowestAsk;

        brushClaimable[maker] += quantityNFTClaimable * lowestAsk;
        emit OrderMatched(maker, msg.sender, _tokenId, quantityNFTClaimable, lowestAsk);
      }
      // We consumed all orders at this price, so remove all
      if (
        numFullyConsumed == askValues[_tokenId][lowestAsk].length - asks[_tokenId].getNode(lowestAsk).tombstoneOffset
      ) {
        asks[_tokenId].remove(lowestAsk);
        delete askValues[_tokenId][lowestAsk];
      } else {
        // Increase tombstone offset of this price for gas efficiency
        asks[_tokenId].edit(lowestAsk, uint32(numFullyConsumed));
      }
    }
  }

  function sellTakeFromOrderBook(
    uint _tokenId,
    uint _price,
    uint32 _quantity
  ) private returns (uint32 quantityRemaining, uint cost) {
    quantityRemaining = _quantity;

    // Selling
    while (quantityRemaining > 0) {
      uint64 highestBid = getHighestBid(_tokenId);
      if (highestBid == 0 || highestBid < _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numFullyConsumed = 0;
      for (
        uint i = bids[_tokenId].getNode(highestBid).tombstoneOffset;
        i < bidValues[_tokenId][highestBid].length;
        ++i
      ) {
        uint32 quantityL3 = bidValues[_tokenId][highestBid][i].quantity;
        uint amountBrushClaimable = 0;
        bool consumeWholeOrder = quantityRemaining >= quantityL3;
        uint quantityMatched;
        if (consumeWholeOrder) {
          quantityRemaining -= quantityL3;
          quantityMatched = quantityL3;
          ++numFullyConsumed;

          amountBrushClaimable = quantityL3 * highestBid;
        } else {
          // Eat into the order
          bidValues[_tokenId][highestBid][i].quantity -= quantityRemaining;
          amountBrushClaimable = quantityRemaining * highestBid;
          quantityMatched = quantityRemaining;
          quantityRemaining = 0;
        }

        cost += amountBrushClaimable;
        address maker = bidValues[_tokenId][highestBid][i].maker;
        tokenIdsClaimable[maker][_tokenId] += quantityMatched;
        emit OrderMatched(maker, msg.sender, _tokenId, quantityMatched, highestBid);
      }
      // We consumed all orders at this price level, so remove all
      if (
        numFullyConsumed == bidValues[_tokenId][highestBid].length - bids[_tokenId].getNode(highestBid).tombstoneOffset
      ) {
        bids[_tokenId].remove(highestBid); // TODO: A ranged delete would be nice
        delete bidValues[_tokenId][highestBid];
      } else {
        // Increase tombstone offset of this price for gas efficiency
        bids[_tokenId].edit(highestBid, uint32(numFullyConsumed));
      }
    }
  }

  function takeFromOrderBook(
    bool _isBuy,
    uint _tokenId,
    uint64 _price,
    uint32 _quantity
  ) private returns (uint32 quantityRemaining, uint cost) {
    // Take as much as possible from the order book
    if (_isBuy) {
      (quantityRemaining, cost) = buyTakeFromOrderBook(_tokenId, _price, _quantity);
    } else {
      (quantityRemaining, cost) = sellTakeFromOrderBook(_tokenId, _price, _quantity);
    }
  }

  function addToBook(bool _isBuy, uint _tokenId, uint64 _price, uint32 _quantity) private {
    OrderBookEntry memory orderBookEntry = OrderBookEntry(msg.sender, _quantity, nextOrderEntryId++);
    uint64 price = _price;
    if (_isBuy) {
      // Add to the bids section
      if (!bids[_tokenId].exists(price)) {
        bids[_tokenId].insert(price);
      } else {
        uint tombstoneOffset = bids[_tokenId].getNode(price).tombstoneOffset;
        // Check if this would go over the max number of orders allowed at this price level
        if ((bidValues[_tokenId][price].length - tombstoneOffset) >= maxOrdersPerPrice) {
          // Loop until we find a suitable place to put this
          uint tick = tokenIdInfos[_tokenId].tick;
          while (true) {
            price = uint64(price - tick);
            if (!bids[_tokenId].exists(price)) {
              bids[_tokenId].insert(price);
              break;
            } else if ((bidValues[_tokenId][price].length - tombstoneOffset) >= maxOrdersPerPrice) {
              break;
            }
          }
        }
      }

      bidValues[_tokenId][price].push(orderBookEntry); // push to existing price entry
    } else {
      // Add to the asks section
      if (!asks[_tokenId].exists(price)) {
        asks[_tokenId].insert(price);
      } else {
        uint tombstoneOffset = asks[_tokenId].getNode(price).tombstoneOffset;
        // Check if this would go over the max number of orders allowed at this price level
        if ((askValues[_tokenId][price].length - tombstoneOffset) >= maxOrdersPerPrice) {
          uint tick = tokenIdInfos[_tokenId].tick;
          // Loop until we find a suitable place to put this
          while (true) {
            price = uint64(price + tick);
            if (!asks[_tokenId].exists(price)) {
              asks[_tokenId].insert(price);
              break;
            } else if ((askValues[_tokenId][price].length - tombstoneOffset) < maxOrdersPerPrice) {
              break;
            }
          }
        }
      }
      askValues[_tokenId][price].push(orderBookEntry); // push to existing price entry
    }
    emit AddedToBook(_isBuy, orderBookEntry, price);
  }

  function claimAll(uint[] calldata _tokenIds) external {
    claimTokens();
    claimNFTs(_tokenIds);
  }

  function claimTokens() public {
    uint amount = brushClaimable[msg.sender];
    if (amount == 0) {
      revert NothingToClaim();
    }
    brushClaimable[msg.sender] = 0;
    (address recipient, uint royalty, uint dev, uint burn) = _calcFees(1, amount);
    uint fees = royalty + dev + burn;
    uint amountExclFees;
    if (amount > fees) {
      amountExclFees = amount - fees;
      _safeTransferFromUs(msg.sender, amountExclFees);
    }
    emit ClaimedTokens(msg.sender, amountExclFees);
  }

  function claimNFTs(uint[] calldata _tokenIds) public {
    uint[] memory amounts = new uint[](_tokenIds.length);
    for (uint i = 0; i < _tokenIds.length; ++i) {
      uint tokenId = _tokenIds[i];
      uint amount = tokenIdsClaimable[msg.sender][tokenId];
      if (amount == 0) {
        revert NothingToClaim();
      }
      amounts[i] = amount;
      tokenIdsClaimable[msg.sender][tokenId] = 0;
    }

    emit ClaimedNFTs(msg.sender, _tokenIds, amounts);

    _safeBatchTransferNFTsFromUs(msg.sender, _tokenIds, amounts);
  }

  function cancelOrders(uint[] calldata _orderIds, CancelOrderInfo[] calldata _cancelOrderInfos) external {
    if (_orderIds.length != _cancelOrderInfos.length) {
      revert LengthMismatch();
    }

    for (uint i = 0; i < _cancelOrderInfos.length; ++i) {
      uint orderId = _orderIds[i];
      OrderSide side = _cancelOrderInfos[i].side;
      uint tokenId = _cancelOrderInfos[i].tokenId;
      uint64 price = _cancelOrderInfos[i].price;

      // Loop through all of them until we hit ours.
      if (side == OrderSide.Buy) {
        if (!bids[tokenId].exists(price)) {
          revert OrderNotFound();
        }

        OrderBookEntry[] storage orderBookEntries = bidValues[tokenId][price];
        uint tombstoneOffset = bids[tokenId].getNode(price).tombstoneOffset;
        uint index = _find(orderBookEntries, tombstoneOffset, orderBookEntries.length, orderId);
        if (index == type(uint).max) {
          revert OrderNotFound();
        }

        // Send the remaining token back to them
        OrderBookEntry memory entry = orderBookEntries[index];
        _cancelOrder(orderBookEntries, price, index, tombstoneOffset, bids[tokenId]);
        _safeTransferFromUs(msg.sender, uint(entry.quantity) * price);
      } else {
        if (!asks[tokenId].exists(price)) {
          revert OrderNotFound();
        }

        OrderBookEntry[] storage orderBookEntries = askValues[tokenId][price];
        uint tombstoneOffset = asks[tokenId].getNode(price).tombstoneOffset;
        uint index = _find(orderBookEntries, tombstoneOffset, orderBookEntries.length, orderId);
        if (index == type(uint).max) {
          revert OrderNotFound();
        }
        OrderBookEntry memory entry = orderBookEntries[index];
        _cancelOrder(orderBookEntries, price, index, tombstoneOffset, asks[tokenId]);
        // Send the remaining NFTs back to them
        _safeTransferNFTsFromUs(msg.sender, tokenId, entry.quantity);
      }
    }

    emit OrdersCancelled(_orderIds);
  }

  // TODO: editOrder

  function allOrdersAtPrice(
    OrderSide _side,
    uint _tokenId,
    uint64 _price
  ) external view returns (OrderBookEntry[] memory orderBookEntries) {
    if (_side == OrderSide.Buy) {
      if (!bids[_tokenId].exists(_price)) {
        return orderBookEntries;
      }
      uint tombstoneOffset = bids[_tokenId].getNode(_price).tombstoneOffset;
      orderBookEntries = new OrderBookEntry[](bidValues[_tokenId][_price].length - tombstoneOffset);
      for (uint i; i < orderBookEntries.length; ++i) {
        orderBookEntries[i] = bidValues[_tokenId][_price][i + tombstoneOffset];
      }
    } else {
      if (!asks[_tokenId].exists(_price)) {
        return orderBookEntries;
      }
      uint tombstoneOffset = asks[_tokenId].getNode(_price).tombstoneOffset;
      orderBookEntries = new OrderBookEntry[](askValues[_tokenId][_price].length - tombstoneOffset);
      for (uint i; i < orderBookEntries.length; ++i) {
        orderBookEntries[i] = askValues[_tokenId][_price][i + tombstoneOffset];
      }
    }
  }

  function _limitOrder(LimitOrder calldata _limitOrder) private returns (uint32 quantityRemaining, uint cost) {
    if (_limitOrder.quantity == 0) {
      revert NoQuantity();
    }

    if (_limitOrder.price == 0) {
      revert PriceZero();
    }

    TokenIdInfo memory tokenIdInfo = tokenIdInfos[_limitOrder.tokenId];
    uint tick = tokenIdInfo.tick;
    if (_limitOrder.price % tick != 0) {
      revert PriceNotMultipleOfTick(tick);
    }

    if (tokenIdInfos[_limitOrder.tokenId].tick == 0) {
      revert TokenDoesntExist(_limitOrder.tokenId);
    }

    bool isBuy = _limitOrder.side == OrderSide.Buy;
    (quantityRemaining, cost) = takeFromOrderBook(isBuy, _limitOrder.tokenId, _limitOrder.price, _limitOrder.quantity);

    if (quantityRemaining != 0 && quantityRemaining < tokenIdInfo.minQuantity) {
      revert QuantityRemainingTooLow();
    }

    // Add the rest to the order book
    if (quantityRemaining > 0) {
      addToBook(isBuy, _limitOrder.tokenId, _limitOrder.price, quantityRemaining);
    }
  }

  function _calcFees(
    uint _tokenId,
    uint _cost
  ) private view returns (address recipient, uint royalty, uint dev, uint burn) {
    if (supportsERC2981) {
      (recipient, royalty) = IERC2981(address(nft)).royaltyInfo(_tokenId, _cost);
    }

    dev = (_cost * devFee) / 10000;
    burn = (_cost * burntFee) / 10000;
  }

  function _sendFees(uint _royalty, uint _dev, uint _burn) private {
    if (_royalty > 0) {
      (address royaltyRecipient, ) = IERC2981(address(nft)).royaltyInfo(0, 0);
      _safeTransferFromUs(royaltyRecipient, _royalty);
    }

    if (_dev > 0) {
      _safeTransferFromUs(devAddr, _dev);
    }

    if (_burn > 0) {
      token.burn(_burn);
    }
  }

  // TODO: See if iteration is less gas intensive
  function _find(OrderBookEntry[] storage data, uint begin, uint end, uint value) internal returns (uint) {
    uint len = end - begin;
    if (len == 0 || (len == 1 && data[begin].id != value)) {
      return type(uint).max;
    }
    uint mid = begin + len / 2;
    uint v = data[mid].id;
    if (value < v) {
      return _find(data, begin, mid, value);
    } else if (value > v) {
      return _find(data, mid + 1, end, value);
    }

    return mid;
  }

  function _cancelOrder(
    OrderBookEntry[] storage orderBookEntries,
    uint64 _price,
    uint _index,
    uint _tombstoneOffset,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private {
    if (orderBookEntries[_index].maker != msg.sender) {
      revert NotMaker();
    }
    // Remove it by shifting everything else to the left
    uint length = orderBookEntries.length;
    for (uint i = _index; i < length - 1; ++i) {
      orderBookEntries[i] = orderBookEntries[i + 1];
    }
    orderBookEntries.pop();

    if (orderBookEntries.length - _tombstoneOffset == 0) {
      // Last one at this price level so trash it
      _tree.remove(_price);
    }
  }

  function _safeTransferFromUs(address _to, uint _amount) private {
    token.transfer(_to, _amount);
  }

  function _safeTransferNFTsFromUs(address _to, uint _tokenId, uint _amount) private {
    nft.safeTransferFrom(address(this), _to, _tokenId, _amount, "");
  }

  function _safeBatchTransferNFTsFromUs(address _to, uint[] memory _tokenIds, uint[] memory _amounts) private {
    nft.safeBatchTransferFrom(address(this), _to, _tokenIds, _amounts, "");
  }

  function tokensClaimable(address _account, bool takeAwayFees) external view returns (uint amount) {
    amount = brushClaimable[_account];
    if (takeAwayFees) {
      (, uint royalty, uint dev, uint burn) = _calcFees(1, amount);
      amount -= royalty + dev + burn;
    }
  }

  function nftClaimable(address _account, uint _tokenId) external view returns (uint) {
    return tokenIdsClaimable[_account][_tokenId];
  }

  function getHighestBid(uint _tokenId) public view returns (uint64) {
    return bids[_tokenId].last();
  }

  function getLowestAsk(uint _tokenId) public view returns (uint64) {
    return asks[_tokenId].first();
  }

  function getNode(
    OrderSide _side,
    uint _tokenId,
    uint64 _price
  ) external view returns (BokkyPooBahsRedBlackTreeLibrary.Node memory) {
    if (_side == OrderSide.Buy) {
      return bids[_tokenId].getNode(_price);
    } else {
      return asks[_tokenId].getNode(_price);
    }
  }

  function setMaxOrdersPerPrice(uint16 _maxOrdersPerPrice) external onlyOwner {
    maxOrdersPerPrice = _maxOrdersPerPrice;
  }

  function setTokenIdInfos(uint[] calldata _tokenIds, TokenIdInfo[] calldata _tokenIdInfos) external onlyOwner {
    if (_tokenIds.length != _tokenIdInfos.length) {
      revert LengthMismatch();
    }

    for (uint i = 0; i < _tokenIds.length; ++i) {
      tokenIdInfos[_tokenIds[i]] = _tokenIdInfos[i];
    }

    emit SetTokenIdInfos(_tokenIds, _tokenIdInfos);
  }

  function getTick(uint _tokenId) external view returns (uint) {
    return tokenIdInfos[_tokenId].tick;
  }

  function getMinAmount(uint _tokenId) external view returns (uint) {
    return tokenIdInfos[_tokenId].minQuantity;
  }

  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
