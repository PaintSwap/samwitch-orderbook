// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UnsafeMath} from "@0xdoublesharp/unsafe-math/contracts/UnsafeMath.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IBrushToken} from "./interfaces/IBrushToken.sol";

import {BokkyPooBahsRedBlackTreeLibrary} from "./BokkyPooBahsRedBlackTreeLibrary.sol";

/// @title SamWitchOrderBook
/// @author Sam Witch (PaintSwap & Estfor Kingdom)
/// @notice This efficient ERC1155 order book is an upgradeable UUPS proxy contract. It has functions for bulk placing
///         limit orders, cancelling limit orders, and claiming NFTs and tokens from filled or partially filled orders.
///         It suppports ERC2981 royalties, and optional dev & burn fees on successful trades.
contract SamWitchOrderBook is ERC1155Holder, UUPSUpgradeable, OwnableUpgradeable {
  using BokkyPooBahsRedBlackTreeLibrary for BokkyPooBahsRedBlackTreeLibrary.Tree;
  using UnsafeMath for uint;

  event OrdersMatched(address taker, uint[] orderIds, uint[] quantities);
  event OrdersCancelled(address maker, uint[] orderIds);
  event FailedToAddToBook(address maker, OrderSide side, uint tokenId, uint price, uint quantity);
  event AddedToBook(address maker, OrderSide side, uint orderId, uint price, uint quantity);
  event ClaimedTokens(address maker, uint[] orderIds, uint amount);
  event ClaimedNFTs(address maker, uint[] orderIds, uint[] tokenIds, uint[] amounts);
  event SetTokenIdInfos(uint[] tokenIds, TokenIdInfo[] tokenIdInfos);
  event SetMaxOrdersPerPriceLevel(uint maxOrdersPerPrice);

  error ZeroAddress();
  error NotERC1155();
  error NoQuantity();
  error OrderNotFound();
  error PriceNotMultipleOfTick(uint tick);
  error TokenDoesntExist(uint tokenId);
  error PriceZero();
  error LengthMismatch();
  error NotMaker();
  error NothingToClaim();
  error TooManyOrdersHit();
  error TransferToUsFailed();
  error TransferFromUsFailed();

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

  IERC1155 public nft;
  IBrushToken public token;

  address private devAddr;
  uint8 private devFee; // Base 10000, max 2.55%
  uint8 private burntFee;
  uint16 private royaltyFee;
  uint16 private maxOrdersPerPrice;
  uint40 private nextOrderId;
  address private royaltyRecipient;

  mapping(uint tokenId => TokenIdInfo tokenIdInfo) public tokenIdInfos;

  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) private asks;
  mapping(uint tokenId => BokkyPooBahsRedBlackTreeLibrary.Tree) private bids;
  mapping(uint tokenId => mapping(uint price => bytes32[] packedOrders)) private askValues; // quantity (uint24), id (uint40) 4x packed of these
  mapping(uint tokenId => mapping(uint price => bytes32[] packedOrders)) private bidValues; // quantity (uint24), id (uint40) 4x packed of these
  mapping(uint orderId => address maker) private orderBookIdToMaker;
  uint80[1_099_511_627_776] private brushClaimable; // Can pack 3 brush claimables into 1 word
  mapping(uint40 orderId => mapping(uint tokenId => uint amount)) private tokenIdsClaimable;

  uint private constant MAX_ORDERS_HIT = 500;
  uint private constant NUM_ORDERS_PER_SEGMENT = 4;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initialize the contract as part of the proxy contract deployment
  /// @param _nft Address of the nft
  /// @param _token The quote token
  /// @param _devAddr The address to receive trade fees
  /// @param _devFee The fee to send to the dev address (max 2.55%)
  /// @param _burntFee The fee to burn (max 2.55%)
  /// @param _maxOrdersPerPrice The maximum number of orders allowed at each price level
  function initialize(
    IERC1155 _nft,
    address _token,
    address _devAddr,
    uint8 _devFee,
    uint8 _burntFee,
    uint16 _maxOrdersPerPrice
  ) external initializer {
    __UUPSUpgradeable_init();
    __Ownable_init(_msgSender());

    // make sure dev address is set
    if (_devAddr == address(0)) {
      revert ZeroAddress();
    }

    // nft must be an ERC1155 via ERC165
    if (!_nft.supportsInterface(type(IERC1155).interfaceId)) {
      revert NotERC1155();
    }

    nft = _nft;
    token = IBrushToken(_token);
    updateRoyaltyFee();

    devFee = _devFee; // 30 = 0.3% fee,
    devAddr = _devAddr;
    burntFee = _burntFee; // 30 = 0.3% fee,
    setMaxOrdersPerPrice(_maxOrdersPerPrice); // This includes inside segments, so num segments = maxOrdersPrice / NUM_ORDERS_PER_SEGMENT
    nextOrderId = 1;
  }

  /// @notice Place multiple limit orders in the order book
  /// @param _orders Array of limit orders to be placed
  function limitOrders(LimitOrder[] calldata _orders) external {
    uint royalty;
    uint dev;
    uint burn;
    uint brushTransferToUs;
    uint brushTransferFromUs;
    uint lengthToUs;
    uint ordersLength = _orders.length;
    uint[] memory idsToUs = new uint[](ordersLength);
    uint[] memory amountsToUs = new uint[](ordersLength);
    uint lengthFromUs;
    uint[] memory idsFromUs = new uint[](ordersLength);
    uint[] memory amountsFromUs = new uint[](ordersLength);

    // This is done here so that it can be used in many limit orders without wasting too much space
    uint[] memory orderIdsPool = new uint[](MAX_ORDERS_HIT);
    uint[] memory quantitiesPool = new uint[](MAX_ORDERS_HIT);

    for (uint i = 0; i < ordersLength; ++i) {
      LimitOrder calldata limitOrder = _orders[i];
      OrderSide side = limitOrder.side;
      uint tokenId = limitOrder.tokenId;
      uint quantity = limitOrder.quantity;
      uint price = limitOrder.price;
      (uint24 quantityAddedToBook, uint24 failedQuantity, uint cost) = _makeLimitOrder(
        limitOrder,
        orderIdsPool,
        quantitiesPool
      );

      if (side == OrderSide.Buy) {
        brushTransferToUs += cost + uint(price) * quantityAddedToBook;
        if (cost != 0) {
          (uint _royalty, uint _dev, uint _burn) = _calcFees(cost);
          royalty = royalty.add(_royalty);
          dev = dev.add(_dev);
          burn = burn.add(_burn);

          // Transfer the NFTs straight to the user
          idsFromUs[lengthFromUs] = tokenId;
          amountsFromUs[lengthFromUs] = quantity.sub(quantityAddedToBook);
          lengthFromUs = lengthFromUs.inc();
        }
      } else {
        // Selling, transfer all NFTs to us
        uint amount = quantity - failedQuantity;
        if (amount != 0) {
          idsToUs[lengthToUs] = tokenId;
          amountsToUs[lengthToUs] = amount;
          lengthToUs = lengthToUs.inc();
        }

        // Transfer tokens to the seller if any have sold
        if (cost != 0) {
          (uint _royalty, uint _dev, uint _burn) = _calcFees(cost);
          royalty = royalty.add(_royalty);
          dev = dev.add(_dev);
          burn = burn.add(_burn);

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

    if (brushTransferToUs != 0) {
      _safeTransferToUs(_msgSender(), brushTransferToUs);
    }

    if (brushTransferFromUs != 0) {
      _safeTransferFromUs(_msgSender(), brushTransferFromUs);
    }

    if (idsToUs.length != 0) {
      nft.safeBatchTransferFrom(_msgSender(), address(this), idsToUs, amountsToUs, "");
    }

    if (idsFromUs.length != 0) {
      _safeBatchTransferNFTsFromUs(_msgSender(), idsFromUs, amountsFromUs);
    }

    _sendFees(royalty, dev, burn);
  }

  /// @notice Cancel multiple orders in the order book
  /// @param _orderIds Array of order IDs to be cancelled
  /// @param _cancelOrderInfos Information about the orders so that they can be found in the order book
  function cancelOrders(uint[] calldata _orderIds, CancelOrderInfo[] calldata _cancelOrderInfos) external {
    if (_orderIds.length != _cancelOrderInfos.length) {
      revert LengthMismatch();
    }
    uint cancelOrderInfosLength = _cancelOrderInfos.length;
    uint amountToTransferFromUs = 0;
    uint nftsToTransferFromUs = 0;
    uint[] memory ids = new uint[](cancelOrderInfosLength);
    uint[] memory amounts = new uint[](cancelOrderInfosLength);
    for (uint i = 0; i < cancelOrderInfosLength; ++i) {
      CancelOrderInfo calldata cancelOrderInfo = _cancelOrderInfos[i];
      (OrderSide side, uint tokenId, uint72 price) = (
        cancelOrderInfo.side,
        cancelOrderInfo.tokenId,
        cancelOrderInfo.price
      );

      if (side == OrderSide.Buy) {
        uint24 quantity = _cancelOrdersSide(_orderIds[i], price, bidValues[tokenId][price], bids[tokenId]);
        // Send the remaining token back to them
        amountToTransferFromUs += quantity * price;
      } else {
        uint24 quantity = _cancelOrdersSide(_orderIds[i], price, askValues[tokenId][price], asks[tokenId]);
        // Send the remaining NFTs back to them
        ids[nftsToTransferFromUs] = tokenId;
        amounts[nftsToTransferFromUs] = quantity;
        nftsToTransferFromUs += 1;
      }
    }

    emit OrdersCancelled(_msgSender(), _orderIds);

    // Transfer tokens if there are any to send
    if (amountToTransferFromUs != 0) {
      _safeTransferFromUs(_msgSender(), amountToTransferFromUs);
    }

    // Send the NFTs
    if (nftsToTransferFromUs != 0) {
      // reset the size
      assembly ("memory-safe") {
        mstore(ids, nftsToTransferFromUs)
        mstore(amounts, nftsToTransferFromUs)
      }
      _safeBatchTransferNFTsFromUs(_msgSender(), ids, amounts);
    }
  }

  /// @notice Claim NFTs associated with filled or partially filled orders.
  ///         Must be the maker of these orders.
  /// @param _orderIds Array of order IDs from which to claim NFTs
  function claimTokens(uint[] calldata _orderIds) public {
    uint amount;
    for (uint i = 0; i < _orderIds.length; ++i) {
      uint40 orderId = uint40(_orderIds[i]);
      uint80 claimableAmount = brushClaimable[orderId];
      if (claimableAmount == 0) {
        revert NothingToClaim();
      }

      address maker = orderBookIdToMaker[orderId];
      if (maker != _msgSender()) {
        revert NotMaker();
      }
      amount += claimableAmount;
      brushClaimable[orderId] = 0;
    }

    if (amount == 0) {
      revert NothingToClaim();
    }

    (uint royalty, uint dev, uint burn) = _calcFees(amount);
    uint fees = royalty + dev + burn;
    uint amountExclFees = 0;
    if (amount > fees) {
      amountExclFees = amount - fees;
    }

    emit ClaimedTokens(_msgSender(), _orderIds, amountExclFees);

    if (amountExclFees != 0) {
      _safeTransferFromUs(_msgSender(), amountExclFees);
    }
  }

  /// @notice Claim NFTs associated with filled or partially filled orders
  ///         Must be the maker of these orders.
  /// @param _orderIds Array of order IDs from which to claim NFTs
  /// @param _tokenIds Array of token IDs to claim NFTs for
  function claimNFTs(uint[] calldata _orderIds, uint[] calldata _tokenIds) public {
    if (_orderIds.length != _tokenIds.length) {
      revert LengthMismatch();
    }

    uint[] memory amounts = new uint[](_tokenIds.length);
    for (uint i = 0; i < _tokenIds.length; ++i) {
      uint40 orderId = uint40(_orderIds[i]);
      uint tokenId = _tokenIds[i];
      mapping(uint => uint) storage tokenIdsClaimableForOrder = tokenIdsClaimable[orderId];
      uint amount = tokenIdsClaimableForOrder[tokenId];
      if (amount == 0) {
        revert NothingToClaim();
      }
      amounts[i] = amount;
      tokenIdsClaimableForOrder[tokenId] = 0;
    }

    emit ClaimedNFTs(_msgSender(), _orderIds, _tokenIds, amounts);

    _safeBatchTransferNFTsFromUs(_msgSender(), _tokenIds, amounts);
  }

  /// @notice Convience function to claim both tokens and nfts in filled or partially filled orders.
  ///         Must be the maker of these orders.
  /// @param _brushOrderIds Array of order IDs from which to claim tokens
  /// @param _nftOrderIds Array of order IDs from which to claim NFTs
  /// @param _tokenIds Array of token IDs to claim NFTs for
  function claimAll(uint[] calldata _brushOrderIds, uint[] calldata _nftOrderIds, uint[] calldata _tokenIds) external {
    claimTokens(_brushOrderIds);
    claimNFTs(_nftOrderIds, _tokenIds);
  }

  /// @notice When the nft royalty changes this updates the fee and recipient. Assumes all token ids have the same royalty
  function updateRoyaltyFee() public {
    bool supportsERC2981 = nft.supportsInterface(type(IERC2981).interfaceId);
    if (supportsERC2981) {
      (address _royaltyRecipient, uint _royaltyFee) = IERC2981(address(nft)).royaltyInfo(1, 10000);
      royaltyRecipient = _royaltyRecipient;
      royaltyFee = uint16(_royaltyFee);
    }
  }

  // TODO: editOrder

  function _buyTakeFromOrderBook(
    uint _tokenId,
    uint72 _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityRemaining, uint cost) {
    quantityRemaining = _quantity;

    // reset the size
    assembly ("memory-safe") {
      mstore(_orderIdsPool, MAX_ORDERS_HIT)
      mstore(_quantitiesPool, MAX_ORDERS_HIT)
    }

    uint length;
    while (quantityRemaining != 0) {
      uint72 lowestAsk = getLowestAsk(_tokenId);
      if (lowestAsk == 0 || lowestAsk > _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numSegmentsFullyConsumed = 0;
      bytes32[] storage lowestAskValues = askValues[_tokenId][lowestAsk];
      BokkyPooBahsRedBlackTreeLibrary.Tree storage askTree = asks[_tokenId];
      uint limit = lowestAskValues.length;
      for (uint i = askTree.getNode(lowestAsk).tombstoneOffset; i < limit; ++i) {
        bytes32 packed = lowestAskValues[i];
        uint numOrdersWithinSegmentConsumed;
        uint finalOffset;
        for (uint offset; offset < NUM_ORDERS_PER_SEGMENT; ++offset) {
          uint40 orderId = uint40(uint(packed >> (offset * 64)));
          if (orderId == 0 || quantityRemaining == 0) {
            // No more orders at this price level in this segment
            if (orderId == 0) {
              finalOffset = offset - 1;
            }
            break;
          }
          uint24 quantityL3 = uint24(uint(packed >> (offset * 64 + 40)));
          uint quantityNFTClaimable = 0;
          if (quantityRemaining >= quantityL3) {
            // Consume this whole order
            quantityRemaining -= quantityL3;
            // Is the the last one in the segment being fully consumed?
            if (offset == NUM_ORDERS_PER_SEGMENT - 1 || uint(packed >> ((offset + 1) * 64)) == 0) {
              ++numSegmentsFullyConsumed;
            }
            ++numOrdersWithinSegmentConsumed;
            quantityNFTClaimable = quantityL3;
          } else {
            // Eat into the order
            packed = bytes32(
              (uint(packed) & ~(uint(0xffffff) << (offset * 64 + 40))) |
                (uint(quantityL3 - quantityRemaining) << (offset * 64 + 40))
            );
            quantityNFTClaimable = quantityRemaining;
            quantityRemaining = 0;
          }
          finalOffset = offset;
          cost += quantityNFTClaimable * lowestAsk;

          brushClaimable[orderId] += uint80(quantityNFTClaimable * lowestAsk);

          _orderIdsPool[length] = orderId;
          _quantitiesPool[length++] = quantityNFTClaimable;

          if (length >= MAX_ORDERS_HIT) {
            revert TooManyOrdersHit();
          }
        }

        if (numOrdersWithinSegmentConsumed != finalOffset + 1) {
          lowestAskValues[i] = bytes32(packed >> (numOrdersWithinSegmentConsumed * 64));
        }
        if (quantityRemaining == 0) {
          break;
        }
      }

      // We consumed all orders at this price, so remove all
      if (numSegmentsFullyConsumed == lowestAskValues.length - askTree.getNode(lowestAsk).tombstoneOffset) {
        askTree.remove(lowestAsk);
        delete askValues[_tokenId][lowestAsk];
      } else {
        // Increase tombstone offset of this price for gas efficiency
        askTree.edit(lowestAsk, uint32(numSegmentsFullyConsumed));
      }
    }

    assembly ("memory-safe") {
      mstore(_orderIdsPool, length)
      mstore(_quantitiesPool, length)
    }

    emit OrdersMatched(_msgSender(), _orderIdsPool, _quantitiesPool);
  }

  function _sellTakeFromOrderBook(
    uint _tokenId,
    uint _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityRemaining, uint cost) {
    quantityRemaining = _quantity;

    // reset the size
    assembly ("memory-safe") {
      mstore(_orderIdsPool, MAX_ORDERS_HIT)
      mstore(_quantitiesPool, MAX_ORDERS_HIT)
    }
    uint length;
    while (quantityRemaining != 0) {
      uint72 highestBid = getHighestBid(_tokenId);
      if (highestBid == 0 || highestBid < _price) {
        // No more orders left
        break;
      }

      // Loop through all at this order
      uint numSegmentsFullyConsumed = 0;
      bytes32[] storage highestBidValues = bidValues[_tokenId][highestBid];
      BokkyPooBahsRedBlackTreeLibrary.Tree storage bidTree = bids[_tokenId];

      for (uint i = bidTree.getNode(highestBid).tombstoneOffset; i < highestBidValues.length; ++i) {
        bytes32 packed = highestBidValues[i];
        uint numOrdersWithinSegmentConsumed;
        uint finalOffset;
        for (uint offset; offset < NUM_ORDERS_PER_SEGMENT; ++offset) {
          uint40 orderId = uint40(uint(packed >> (offset * 64)));
          if (orderId == 0 || quantityRemaining == 0) {
            // No more orders at this price level in this segment
            if (orderId == 0) {
              finalOffset = offset - 1;
            }
            break;
          }
          uint24 quantityL3 = uint24(uint(packed >> (offset * 64 + 40)));
          uint quantityNFTClaimable = 0;
          if (quantityRemaining >= quantityL3) {
            // Consume this whole order
            quantityRemaining -= quantityL3;
            // Is the the last one in the segment being fully consumed?
            if (offset == NUM_ORDERS_PER_SEGMENT - 1 || uint(packed >> ((offset + 1) * 64)) == 0) {
              ++numSegmentsFullyConsumed;
            }
            ++numOrdersWithinSegmentConsumed;
            quantityNFTClaimable = quantityL3;
          } else {
            // Eat into the order
            packed = bytes32(
              (uint(packed) & ~(uint(0xffffff) << (offset * 64 + 40))) |
                (uint(quantityL3 - quantityRemaining) << (offset * 64 + 40))
            );
            quantityNFTClaimable = quantityRemaining;
            quantityRemaining = 0;
          }
          finalOffset = offset;
          cost += quantityNFTClaimable * highestBid;

          tokenIdsClaimable[orderId][_tokenId] += quantityNFTClaimable;

          _orderIdsPool[length] = orderId;
          _quantitiesPool[length++] = quantityNFTClaimable;

          if (length >= MAX_ORDERS_HIT) {
            revert TooManyOrdersHit();
          }
        }

        if (numOrdersWithinSegmentConsumed != finalOffset + 1) {
          highestBidValues[i] = bytes32(packed >> (numOrdersWithinSegmentConsumed * 64));
        }
        if (quantityRemaining == 0) {
          break;
        }
      }

      // We consumed all orders at this price level, so remove all
      if (numSegmentsFullyConsumed == highestBidValues.length - bidTree.getNode(highestBid).tombstoneOffset) {
        bidTree.remove(highestBid); // TODO: A ranged delete would be nice
        delete bidValues[_tokenId][highestBid];
      } else {
        // Increase tombstone offset of this price for gas efficiency
        bidTree.edit(highestBid, uint32(numSegmentsFullyConsumed));
      }
    }

    assembly ("memory-safe") {
      mstore(_orderIdsPool, length)
      mstore(_quantitiesPool, length)
    }

    emit OrdersMatched(_msgSender(), _orderIdsPool, _quantitiesPool);
  }

  function _takeFromOrderBook(
    OrderSide _side,
    uint _tokenId,
    uint72 _price,
    uint24 _quantity,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityRemaining, uint cost) {
    // Take as much as possible from the order book
    if (_side == OrderSide.Buy) {
      (quantityRemaining, cost) = _buyTakeFromOrderBook(_tokenId, _price, _quantity, _orderIdsPool, _quantitiesPool);
    } else {
      (quantityRemaining, cost) = _sellTakeFromOrderBook(_tokenId, _price, _quantity, _orderIdsPool, _quantitiesPool);
    }
  }

  function _allOrdersAtPriceSide(
    bytes32[] storage packedOrderBookEntries,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree,
    uint72 _price
  ) private view returns (OrderBookEntryHelper[] memory orderBookEntries) {
    if (!_tree.exists(_price)) {
      return orderBookEntries;
    }
    uint tombstoneOffset = _tree.getNode(_price).tombstoneOffset;
    orderBookEntries = new OrderBookEntryHelper[](
      (packedOrderBookEntries.length - tombstoneOffset) * NUM_ORDERS_PER_SEGMENT
    );
    uint length;
    for (uint i; i < orderBookEntries.length; ++i) {
      uint packed = uint(packedOrderBookEntries[i / NUM_ORDERS_PER_SEGMENT + tombstoneOffset]);
      uint offset = i % NUM_ORDERS_PER_SEGMENT;
      uint40 id = uint40(packed >> (offset * 64));
      if (id != 0) {
        uint24 quantity = uint24(packed >> (offset * 64 + 40));
        orderBookEntries[length++] = OrderBookEntryHelper(orderBookIdToMaker[id], quantity, id);
      }
    }

    assembly ("memory-safe") {
      mstore(orderBookEntries, length)
    }
  }

  function _cancelOrdersSide(
    uint _orderId,
    uint72 _price,
    bytes32[] storage _packedOrderBookEntries,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private returns (uint24 quantity) {
    // Loop through all of them until we hit ours.
    if (!_tree.exists(_price)) {
      revert OrderNotFound();
    }

    uint tombstoneOffset = _tree.getNode(_price).tombstoneOffset;

    (uint index, uint offset) = _find(
      _packedOrderBookEntries,
      tombstoneOffset,
      _packedOrderBookEntries.length,
      _orderId
    );
    if (index == type(uint).max) {
      revert OrderNotFound();
    }

    quantity = uint24(uint(_packedOrderBookEntries[index]) >> (offset * 64 + 40));
    _cancelOrder(_packedOrderBookEntries, _price, index, offset, tombstoneOffset, _tree);
  }

  function _makeLimitOrder(
    LimitOrder calldata _limitOrder,
    uint[] memory _orderIdsPool,
    uint[] memory _quantitiesPool
  ) private returns (uint24 quantityAddedToBook, uint24 failedQuantity, uint cost) {
    if (_limitOrder.quantity == 0) {
      revert NoQuantity();
    }

    if (_limitOrder.price == 0) {
      revert PriceZero();
    }

    TokenIdInfo storage tokenIdInfo = tokenIdInfos[_limitOrder.tokenId];
    uint tick = tokenIdInfo.tick;

    if (tick == 0) {
      revert TokenDoesntExist(_limitOrder.tokenId);
    }

    if (_limitOrder.price % tick != 0) {
      revert PriceNotMultipleOfTick(tick);
    }

    (quantityAddedToBook, cost) = _takeFromOrderBook(
      _limitOrder.side,
      _limitOrder.tokenId,
      _limitOrder.price,
      _limitOrder.quantity,
      _orderIdsPool,
      _quantitiesPool
    );

    // Add the rest to the order book if has the minimum required, in order to keep order books healthy
    if (quantityAddedToBook >= tokenIdInfo.minQuantity) {
      _addToBook(_limitOrder.side, _limitOrder.tokenId, _limitOrder.price, quantityAddedToBook);
    } else {
      failedQuantity = quantityAddedToBook;
      quantityAddedToBook = 0;
      emit FailedToAddToBook(_msgSender(), _limitOrder.side, _limitOrder.tokenId, _limitOrder.price, failedQuantity);
    }
  }

  function _addToBookSide(
    mapping(uint price => bytes32[]) storage _packedOrdersPriceMap,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree,
    uint72 _price,
    uint _orderId,
    uint _quantity,
    int128 _tickIncrement // -1 for buy, +1 for sell
  ) private returns (uint72 price) {
    // Add to the bids section
    price = _price;
    if (!_tree.exists(price)) {
      _tree.insert(price);
    } else {
      uint tombstoneOffset = _tree.getNode(price).tombstoneOffset;
      // Check if this would go over the max number of orders allowed at this price level
      bool lastSegmentFilled = uint(
        _packedOrdersPriceMap[price][_packedOrdersPriceMap[price].length - 1] >> ((NUM_ORDERS_PER_SEGMENT - 1) * 64)
      ) != 0;

      // Check if last segment is full
      if (
        (_packedOrdersPriceMap[price].length - tombstoneOffset) * NUM_ORDERS_PER_SEGMENT >= maxOrdersPerPrice &&
        lastSegmentFilled
      ) {
        // Loop until we find a suitable place to put this
        while (true) {
          price = uint72(uint128(int72(price) + _tickIncrement));
          if (!_tree.exists(price)) {
            _tree.insert(price);
            break;
          } else if (
            (_packedOrdersPriceMap[price].length - tombstoneOffset) * NUM_ORDERS_PER_SEGMENT >= maxOrdersPerPrice &&
            uint(
              _packedOrdersPriceMap[price][_packedOrdersPriceMap[price].length - 1] >>
                ((NUM_ORDERS_PER_SEGMENT - 1) * 64)
            ) !=
            0
          ) {
            break;
          }
        }
      }
    }

    // Read last one
    bytes32[] storage packedOrders = _packedOrdersPriceMap[price];
    bool pushToEnd = true;
    if (packedOrders.length != 0) {
      bytes32 lastPacked = packedOrders[packedOrders.length - 1];
      // Are there are free entries in this segment
      for (uint i = 0; i < NUM_ORDERS_PER_SEGMENT; ++i) {
        uint orderId = uint40(uint(lastPacked >> (i * 64)));
        if (orderId == 0) {
          // Found one, so add to an existing segment
          bytes32 newPacked = lastPacked | (bytes32(_orderId) << (i * 64)) | (bytes32(_quantity) << (i * 64 + 40));
          packedOrders[packedOrders.length - 1] = newPacked;
          pushToEnd = false;
          break;
        }
      }
    }

    if (pushToEnd) {
      bytes32 packedOrder = bytes32(_orderId) | (bytes32(_quantity) << 40);
      packedOrders.push(packedOrder);
    }
  }

  function _addToBook(OrderSide _side, uint _tokenId, uint72 _price, uint24 _quantity) private {
    uint40 orderId = nextOrderId++;
    orderBookIdToMaker[orderId] = _msgSender();
    uint72 price;
    // Price can update if the price level is at capacity
    if (_side == OrderSide.Buy) {
      price = _addToBookSide(
        bidValues[_tokenId],
        bids[_tokenId],
        _price,
        orderId,
        _quantity,
        -int128(tokenIdInfos[_tokenId].tick)
      );
    } else {
      price = _addToBookSide(
        askValues[_tokenId],
        asks[_tokenId],
        _price,
        orderId,
        _quantity,
        int128(tokenIdInfos[_tokenId].tick)
      );
    }
    emit AddedToBook(_msgSender(), _side, orderId, price, _quantity);
  }

  function _calcFees(uint _cost) private view returns (uint royalty, uint dev, uint burn) {
    royalty = (_cost.mul(royaltyFee)).div(10000);
    dev = (_cost.mul(devFee)).div(10000);
    burn = (_cost.mul(burntFee)).div(10000);
  }

  function _sendFees(uint _royalty, uint _dev, uint _burn) private {
    if (_royalty != 0) {
      _safeTransferFromUs(royaltyRecipient, _royalty);
    }

    if (_dev != 0) {
      _safeTransferFromUs(devAddr, _dev);
    }

    if (_burn != 0) {
      token.burn(_burn);
    }
  }

  function _find(
    bytes32[] storage packedData,
    uint begin,
    uint end,
    uint value
  ) private view returns (uint mid, uint offset) {
    while (begin < end) {
      mid = begin + (end - begin) / 2;
      uint packed = uint(packedData[mid]);
      offset = 0;

      for (uint i = 0; i < NUM_ORDERS_PER_SEGMENT; ++i) {
        uint40 id = uint40(packed >> (offset.mul(8)));
        if (id == value) {
          return (mid, i); // Return the index where the ID is found
        } else if (id < value) {
          offset = offset.add(8); // Move to the next segment
        } else {
          break; // Break if the searched value is smaller, as it's a binary search
        }
      }

      if (offset == NUM_ORDERS_PER_SEGMENT * 8) {
        begin = mid.inc();
      } else {
        end = mid;
      }
    }

    return (type(uint).max, type(uint).max); // ID not found in any segment of the packed data
  }

  function _cancelOrder(
    bytes32[] storage orderBookEntries,
    uint72 _price,
    uint _index,
    uint _offset,
    uint _tombstoneOffset,
    BokkyPooBahsRedBlackTreeLibrary.Tree storage _tree
  ) private {
    bytes32 packed = orderBookEntries[_index];
    uint40 orderId = uint40(uint(packed) >> (_offset * 64));

    address maker = orderBookIdToMaker[orderId];
    if (maker == address(0) || maker != _msgSender()) {
      revert NotMaker();
    }

    if (_offset == 0 && packed >> 64 == bytes32(0)) {
      // Remove the entire segment by shifting all other segments to the left. Not very efficient, but this at least only affects the user cancelling
      uint limit = orderBookEntries.length.sub(1);
      for (uint i = _index; i < limit; ++i) {
        orderBookEntries[i] = orderBookEntries[i.inc()];
      }
      orderBookEntries.pop();
      if (orderBookEntries.length - _tombstoneOffset == 0) {
        // Last one at this price level so trash it
        _tree.remove(_price);
      }
    } else {
      // Just shift orders in the segment
      for (uint i = _offset; i < NUM_ORDERS_PER_SEGMENT - 1; ++i) {
        // Shift the next one into this one
        uint nextSection = uint72(uint(packed) >> ((i + 1) * 64));
        packed = packed & ~(bytes32(uint(0xffffffffffffffff) << (i * 64)));
        packed = packed | (bytes32(nextSection) << (i * 64));
      }

      // Last one set to 0
      packed = packed & ~(bytes32(uint(0xffffffffffffffff) << ((NUM_ORDERS_PER_SEGMENT - 1) * 64)));
      orderBookEntries[_index] = packed;
    }
  }

  function _safeTransferToUs(address _from, uint _amount) private {
    if (!token.transferFrom(_from, address(this), _amount)) {
      revert TransferToUsFailed();
    }
  }

  function _safeTransferFromUs(address _to, uint _amount) private {
    if (!token.transfer(_to, _amount)) {
      revert TransferFromUsFailed();
    }
  }

  function _safeBatchTransferNFTsFromUs(address _to, uint[] memory _tokenIds, uint[] memory _amounts) private {
    nft.safeBatchTransferFrom(address(this), _to, _tokenIds, _amounts, "");
  }

  /// @notice Get the amount of tokens claimable for these orders
  /// @param _orderIds The order IDs to get the claimable tokens for
  /// @param takeAwayFees Whether to take away the fees from the claimable amount
  function tokensClaimable(uint40[] calldata _orderIds, bool takeAwayFees) external view returns (uint amount) {
    uint limit = _orderIds.length;
    for (uint i = 0; i < limit; ++i) {
      amount += brushClaimable[_orderIds[i]];
    }
    if (takeAwayFees) {
      (uint royalty, uint dev, uint burn) = _calcFees(amount);
      amount -= royalty + dev + burn;
    }
  }

  /// @notice Get the amount of NFTs claimable for these orders
  /// @param _orderIds The order IDs to get the claimable NFTs for
  /// @param _tokenIds The token IDs to get the claimable NFTs for
  function nftsClaimable(
    uint40[] calldata _orderIds,
    uint[] calldata _tokenIds
  ) external view returns (uint[] memory amounts) {
    amounts = new uint[](_orderIds.length);
    uint limit = _orderIds.length;
    for (uint i = 0; i < limit; ++i) {
      amounts[i] = tokenIdsClaimable[_orderIds[i]][_tokenIds[i]];
    }
  }

  /// @notice Get the highest bid for a specific token ID
  /// @param _tokenId The token ID to get the highest bid for
  function getHighestBid(uint _tokenId) public view returns (uint72) {
    return bids[_tokenId].last();
  }

  /// @notice Get the lowest ask for a specific token ID
  /// @param _tokenId The token ID to get the lowest ask for
  function getLowestAsk(uint _tokenId) public view returns (uint72) {
    return asks[_tokenId].first();
  }

  /// @notice Get the order book entry for a specific order ID
  /// @param _side The side of the order book to get the order from
  /// @param _tokenId The token ID to get the order for
  /// @param _price The price level to get the order for
  function getNode(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view returns (BokkyPooBahsRedBlackTreeLibrary.Node memory) {
    if (_side == OrderSide.Buy) {
      return bids[_tokenId].getNode(_price);
    } else {
      return asks[_tokenId].getNode(_price);
    }
  }

  /// @notice Check if the node exists
  /// @param _side The side of the order book to get the order from
  /// @param _tokenId The token ID to get the order for
  /// @param _price The price level to get the order for
  function nodeExists(OrderSide _side, uint _tokenId, uint72 _price) external view returns (bool) {
    if (_side == OrderSide.Buy) {
      return bids[_tokenId].exists(_price);
    } else {
      return asks[_tokenId].exists(_price);
    }
  }

  /// @notice Get the tick size for a specific token ID
  /// @param _tokenId The token ID to get the tick size for
  function getTick(uint _tokenId) external view returns (uint) {
    return tokenIdInfos[_tokenId].tick;
  }

  /// @notice The minimum amount that can be added to the order book for a specific token ID, to keep the order book healthy
  /// @param _tokenId The token ID to get the minimum quantity for
  function getMinAmount(uint _tokenId) external view returns (uint) {
    return tokenIdInfos[_tokenId].minQuantity;
  }

  /// @notice Get all orders at a specific price level
  /// @param _side The side of the order book to get orders from
  /// @param _tokenId The token ID to get orders for
  /// @param _price The price level to get orders for
  function allOrdersAtPrice(
    OrderSide _side,
    uint _tokenId,
    uint72 _price
  ) external view returns (OrderBookEntryHelper[] memory orderBookEntries) {
    if (_side == OrderSide.Buy) {
      return _allOrdersAtPriceSide(bidValues[_tokenId][_price], bids[_tokenId], _price);
    } else {
      return _allOrdersAtPriceSide(askValues[_tokenId][_price], asks[_tokenId], _price);
    }
  }

  /// @notice The maximum amount of orders allowed at a specific price level
  /// @param _maxOrdersPerPrice The new maximum amount of orders allowed at a specific price level
  function setMaxOrdersPerPrice(uint16 _maxOrdersPerPrice) public onlyOwner {
    maxOrdersPerPrice = _maxOrdersPerPrice;
    emit SetMaxOrdersPerPriceLevel(_maxOrdersPerPrice);
  }

  /// @notice Set constraints like minimum quantity of an order that is allowed to be
  ///         placed and the minimum of specific tokenIds in this nft collection.
  /// @param _tokenIds Array of token IDs for which to set TokenIdInfo
  /// @param _tokenIdInfos Array of TokenIdInfo to be set
  function setTokenIdInfos(uint[] calldata _tokenIds, TokenIdInfo[] calldata _tokenIdInfos) external onlyOwner {
    uint limit = _tokenIds.length;
    if (limit != _tokenIdInfos.length) {
      revert LengthMismatch();
    }

    for (uint i = 0; i < limit; ++i) {
      tokenIdInfos[_tokenIds[i]] = _tokenIdInfos[i];
    }

    emit SetTokenIdInfos(_tokenIds, _tokenIdInfos);
  }

  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
