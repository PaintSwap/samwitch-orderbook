// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {BokkyPooBahsRedBlackTreeLibrary} from "../BokkyPooBahsRedBlackTreeLibrary.sol";

interface ISamWitchOrderBook is IERC1155Receiver {
  enum OrderSide {
    Buy,
    Sell
  }

  struct LimitOrder {
    OrderSide side;
    uint tokenId;
    uint72 price;
    uint24 quantity;
  }

  struct OrderBookEntryHelper {
    address maker;
    uint24 quantity;
    uint40 id;
  }

  struct TokenIdInfo {
    uint128 tick;
    uint128 minQuantity;
  }

  struct CancelOrderInfo {
    OrderSide side;
    uint tokenId;
    uint72 price;
  }

  event OrdersMatched(address taker, uint[] orderIds, uint[] quantities);
  event OrdersCancelled(address maker, uint[] orderIds);
  event FailedToAddToBook(address maker, OrderSide side, uint tokenId, uint price, uint quantity);
  event AddedToBook(address maker, OrderSide side, uint orderId, uint price, uint quantity);
  event ClaimedTokens(address maker, uint[] orderIds, uint amount);
  event ClaimedNFTs(address maker, uint[] orderIds, uint[] tokenIds, uint[] amounts);
  event SetTokenIdInfos(uint[] tokenIds, TokenIdInfo[] tokenIdInfos);
  event SetMaxOrdersPerPriceLevel(uint maxOrdersPerPrice);

  error ZeroAddress();
  error DevFeeNotSet();
  error NotERC1155();
  error NoQuantity();
  error OrderNotFound(uint orderId, uint price);
  error OrderNotFoundInTree(uint orderId, uint price);
  error PriceNotMultipleOfTick(uint tick);
  error TokenDoesntExist(uint tokenId);
  error PriceZero();
  error LengthMismatch();
  error NotMaker();
  error NothingToClaim();
  error TooManyOrdersHit();

  error DeadlineExpired(uint deadline);
  error InvalidNonce(uint invalid, uint nonce);
  error InvalidSignature(address sender, address recoveredAddress);

  function limitOrders(LimitOrder[] calldata _orders) external;

  function cancelOrders(uint[] calldata _orderIds, CancelOrderInfo[] calldata _cancelOrderInfos) external;

  function claimTokens(uint[] calldata _orderIds) external;

  function claimNFTs(uint[] calldata _orderIds, uint[] calldata _tokenIds) external;

  function claimAll(uint[] calldata _brushOrderIds, uint[] calldata _nftOrderIds, uint[] calldata _tokenIds) external;

  function tokensClaimable(uint40[] calldata _orderIds, bool takeAwayFees) external view returns (uint amount);

  function nftsClaimable(
    uint40[] calldata _orderIds,
    uint[] calldata _tokenIds
  ) external view returns (uint[] memory amounts);

  function getHighestBid(uint _tokenId) external view returns (uint72);

  function getLowestAsk(uint _tokenId) external view returns (uint72);

  function getNode(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view returns (BokkyPooBahsRedBlackTreeLibrary.Node memory);

  function nodeExists(OrderSide _side, uint _tokenId, uint72 _price) external view returns (bool);

  function getTick(uint _tokenId) external view returns (uint);

  function getMinAmount(uint _tokenId) external view returns (uint);

  function allOrdersAtPrice(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view returns (OrderBookEntryHelper[] memory orderBookEntries);
}
