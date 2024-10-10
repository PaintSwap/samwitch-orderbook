# ISamWitchOrderBook

## Methods

### allOrdersAtPrice

```solidity
function allOrdersAtPrice(enum ISamWitchOrderBook.OrderSide side, uint256 tokenId, uint72 price) external view returns (struct ISamWitchOrderBook.Order[] orderBookEntries)
```

#### Parameters

| Name    | Type                              | Description |
| ------- | --------------------------------- | ----------- |
| side    | enum ISamWitchOrderBook.OrderSide | undefined   |
| tokenId | uint256                           | undefined   |
| price   | uint72                            | undefined   |

#### Returns

| Name             | Type                       | Description |
| ---------------- | -------------------------- | ----------- |
| orderBookEntries | ISamWitchOrderBook.Order[] | undefined   |

### cancelAndMakeLimitOrders

```solidity
function cancelAndMakeLimitOrders(uint256[] orderIds, ISamWitchOrderBook.CancelOrder[] orders, ISamWitchOrderBook.LimitOrder[] newOrders) external nonpayable
```

#### Parameters

| Name      | Type                             | Description |
| --------- | -------------------------------- | ----------- |
| orderIds  | uint256[]                        | undefined   |
| orders    | ISamWitchOrderBook.CancelOrder[] | undefined   |
| newOrders | ISamWitchOrderBook.LimitOrder[]  | undefined   |

### cancelOrders

```solidity
function cancelOrders(uint256[] orderIds, ISamWitchOrderBook.CancelOrder[] cancelClaimableTokenInfos) external nonpayable
```

#### Parameters

| Name                      | Type                             | Description |
| ------------------------- | -------------------------------- | ----------- |
| orderIds                  | uint256[]                        | undefined   |
| cancelClaimableTokenInfos | ISamWitchOrderBook.CancelOrder[] | undefined   |

### claimAll

```solidity
function claimAll(uint256[] brushOrderIds, uint256[] nftOrderIds, uint256[] tokenIds) external nonpayable
```

#### Parameters

| Name          | Type      | Description |
| ------------- | --------- | ----------- |
| brushOrderIds | uint256[] | undefined   |
| nftOrderIds   | uint256[] | undefined   |
| tokenIds      | uint256[] | undefined   |

### claimNFTs

```solidity
function claimNFTs(uint256[] orderIds, uint256[] tokenIds) external nonpayable
```

#### Parameters

| Name     | Type      | Description |
| -------- | --------- | ----------- |
| orderIds | uint256[] | undefined   |
| tokenIds | uint256[] | undefined   |

### claimTokens

```solidity
function claimTokens(uint256[] _orderIds) external nonpayable
```

#### Parameters

| Name       | Type      | Description |
| ---------- | --------- | ----------- |
| \_orderIds | uint256[] | undefined   |

### getClaimableTokenInfo

```solidity
function getClaimableTokenInfo(uint40 _orderId) external view returns (struct ISamWitchOrderBook.ClaimableTokenInfo)
```

#### Parameters

| Name      | Type   | Description |
| --------- | ------ | ----------- |
| \_orderId | uint40 | undefined   |

#### Returns

| Name | Type                                  | Description |
| ---- | ------------------------------------- | ----------- |
| \_0  | ISamWitchOrderBook.ClaimableTokenInfo | undefined   |

### getHighestBid

```solidity
function getHighestBid(uint256 tokenId) external view returns (uint72)
```

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| tokenId | uint256 | undefined   |

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | uint72 | undefined   |

### getLowestAsk

```solidity
function getLowestAsk(uint256 tokenId) external view returns (uint72)
```

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| tokenId | uint256 | undefined   |

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | uint72 | undefined   |

### getNode

```solidity
function getNode(enum ISamWitchOrderBook.OrderSide side, uint256 tokenId, uint72 price) external view returns (struct BokkyPooBahsRedBlackTreeLibrary.Node)
```

#### Parameters

| Name    | Type                              | Description |
| ------- | --------------------------------- | ----------- |
| side    | enum ISamWitchOrderBook.OrderSide | undefined   |
| tokenId | uint256                           | undefined   |
| price   | uint72                            | undefined   |

#### Returns

| Name | Type                                 | Description |
| ---- | ------------------------------------ | ----------- |
| \_0  | BokkyPooBahsRedBlackTreeLibrary.Node | undefined   |

### getTokenIdInfo

```solidity
function getTokenIdInfo(uint256 tokenId) external view returns (struct ISamWitchOrderBook.TokenIdInfo)
```

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| tokenId | uint256 | undefined   |

#### Returns

| Name | Type                           | Description |
| ---- | ------------------------------ | ----------- |
| \_0  | ISamWitchOrderBook.TokenIdInfo | undefined   |

### limitOrders

```solidity
function limitOrders(ISamWitchOrderBook.LimitOrder[] orders) external nonpayable
```

#### Parameters

| Name   | Type                            | Description |
| ------ | ------------------------------- | ----------- |
| orders | ISamWitchOrderBook.LimitOrder[] | undefined   |

### marketOrder

```solidity
function marketOrder(ISamWitchOrderBook.MarketOrder order) external nonpayable
```

#### Parameters

| Name  | Type                           | Description |
| ----- | ------------------------------ | ----------- |
| order | ISamWitchOrderBook.MarketOrder | undefined   |

### nftsClaimable

```solidity
function nftsClaimable(uint40[] orderIds, uint256[] tokenIds) external view returns (uint256[] amounts)
```

#### Parameters

| Name     | Type      | Description |
| -------- | --------- | ----------- |
| orderIds | uint40[]  | undefined   |
| tokenIds | uint256[] | undefined   |

#### Returns

| Name    | Type      | Description |
| ------- | --------- | ----------- |
| amounts | uint256[] | undefined   |

### nodeExists

```solidity
function nodeExists(enum ISamWitchOrderBook.OrderSide side, uint256 tokenId, uint72 price) external view returns (bool)
```

#### Parameters

| Name    | Type                              | Description |
| ------- | --------------------------------- | ----------- |
| side    | enum ISamWitchOrderBook.OrderSide | undefined   |
| tokenId | uint256                           | undefined   |
| price   | uint72                            | undefined   |

#### Returns

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_0  | bool | undefined   |

### onERC1155BatchReceived

```solidity
function onERC1155BatchReceived(address operator, address from, uint256[] ids, uint256[] values, bytes data) external nonpayable returns (bytes4)
```

_Handles the receipt of a multiple ERC1155 token types. This function is called at the end of a `safeBatchTransferFrom` after the balances have been updated. NOTE: To accept the transfer(s), this must return `bytes4(keccak256(&quot;onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)&quot;))` (i.e. 0xbc197c81, or its own function selector)._

#### Parameters

| Name     | Type      | Description                                                                                         |
| -------- | --------- | --------------------------------------------------------------------------------------------------- |
| operator | address   | The address which initiated the batch transfer (i.e. msg.sender)                                    |
| from     | address   | The address which previously owned the token                                                        |
| ids      | uint256[] | An array containing ids of each token being transferred (order and length must match values array)  |
| values   | uint256[] | An array containing amounts of each token being transferred (order and length must match ids array) |
| data     | bytes     | Additional data with no specified format                                                            |

#### Returns

| Name | Type   | Description                                                                                                               |
| ---- | ------ | ------------------------------------------------------------------------------------------------------------------------- |
| \_0  | bytes4 | `bytes4(keccak256(&quot;onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)&quot;))` if transfer is allowed |

### onERC1155Received

```solidity
function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes data) external nonpayable returns (bytes4)
```

_Handles the receipt of a single ERC1155 token type. This function is called at the end of a `safeTransferFrom` after the balance has been updated. NOTE: To accept the transfer, this must return `bytes4(keccak256(&quot;onERC1155Received(address,address,uint256,uint256,bytes)&quot;))` (i.e. 0xf23a6e61, or its own function selector)._

#### Parameters

| Name     | Type    | Description                                                |
| -------- | ------- | ---------------------------------------------------------- |
| operator | address | The address which initiated the transfer (i.e. msg.sender) |
| from     | address | The address which previously owned the token               |
| id       | uint256 | The ID of the token being transferred                      |
| value    | uint256 | The amount of tokens being transferred                     |
| data     | bytes   | Additional data with no specified format                   |

#### Returns

| Name | Type   | Description                                                                                                      |
| ---- | ------ | ---------------------------------------------------------------------------------------------------------------- |
| \_0  | bytes4 | `bytes4(keccak256(&quot;onERC1155Received(address,address,uint256,uint256,bytes)&quot;))` if transfer is allowed |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) external view returns (bool)
```

_Returns true if this contract implements the interface defined by `interfaceId`. See the corresponding https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section] to learn more about how these ids are created. This function call must use less than 30 000 gas._

#### Parameters

| Name        | Type   | Description |
| ----------- | ------ | ----------- |
| interfaceId | bytes4 | undefined   |

#### Returns

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_0  | bool | undefined   |

### tokensClaimable

```solidity
function tokensClaimable(uint40[] orderIds, bool takeAwayFees) external view returns (uint256 amount)
```

#### Parameters

| Name         | Type     | Description |
| ------------ | -------- | ----------- |
| orderIds     | uint40[] | undefined   |
| takeAwayFees | bool     | undefined   |

#### Returns

| Name   | Type    | Description |
| ------ | ------- | ----------- |
| amount | uint256 | undefined   |

## Events

### AddedToBook

```solidity
event AddedToBook(address maker, enum ISamWitchOrderBook.OrderSide side, uint256 orderId, uint256 tokenId, uint256 price, uint256 quantity)
```

#### Parameters

| Name     | Type                              | Description |
| -------- | --------------------------------- | ----------- |
| maker    | address                           | undefined   |
| side     | enum ISamWitchOrderBook.OrderSide | undefined   |
| orderId  | uint256                           | undefined   |
| tokenId  | uint256                           | undefined   |
| price    | uint256                           | undefined   |
| quantity | uint256                           | undefined   |

### ClaimedNFTs

```solidity
event ClaimedNFTs(address user, uint256[] orderIds, uint256[] tokenIds, uint256[] amounts)
```

#### Parameters

| Name     | Type      | Description |
| -------- | --------- | ----------- |
| user     | address   | undefined   |
| orderIds | uint256[] | undefined   |
| tokenIds | uint256[] | undefined   |
| amounts  | uint256[] | undefined   |

### ClaimedTokens

```solidity
event ClaimedTokens(address user, uint256[] orderIds, uint256 amount, uint256 fees)
```

#### Parameters

| Name     | Type      | Description |
| -------- | --------- | ----------- |
| user     | address   | undefined   |
| orderIds | uint256[] | undefined   |
| amount   | uint256   | undefined   |
| fees     | uint256   | undefined   |

### FailedToAddToBook

```solidity
event FailedToAddToBook(address maker, enum ISamWitchOrderBook.OrderSide side, uint256 tokenId, uint256 price, uint256 quantity)
```

#### Parameters

| Name     | Type                              | Description |
| -------- | --------------------------------- | ----------- |
| maker    | address                           | undefined   |
| side     | enum ISamWitchOrderBook.OrderSide | undefined   |
| tokenId  | uint256                           | undefined   |
| price    | uint256                           | undefined   |
| quantity | uint256                           | undefined   |

### OrdersCancelled

```solidity
event OrdersCancelled(address maker, uint256[] orderIds)
```

#### Parameters

| Name     | Type      | Description |
| -------- | --------- | ----------- |
| maker    | address   | undefined   |
| orderIds | uint256[] | undefined   |

### OrdersMatched

```solidity
event OrdersMatched(address taker, uint256[] orderIds, uint256[] quantities)
```

#### Parameters

| Name       | Type      | Description |
| ---------- | --------- | ----------- |
| taker      | address   | undefined   |
| orderIds   | uint256[] | undefined   |
| quantities | uint256[] | undefined   |

### SetFees

```solidity
event SetFees(address devAddr, uint256 devFee, uint256 burntFee)
```

#### Parameters

| Name     | Type    | Description |
| -------- | ------- | ----------- |
| devAddr  | address | undefined   |
| devFee   | uint256 | undefined   |
| burntFee | uint256 | undefined   |

### SetMaxOrdersPerPriceLevel

```solidity
event SetMaxOrdersPerPriceLevel(uint256 maxOrdesrsPerPrice)
```

#### Parameters

| Name               | Type    | Description |
| ------------------ | ------- | ----------- |
| maxOrdesrsPerPrice | uint256 | undefined   |

### SetTokenIdInfos

```solidity
event SetTokenIdInfos(uint256[] tokenIds, ISamWitchOrderBook.TokenIdInfo[] tokenInfos)
```

#### Parameters

| Name       | Type                             | Description |
| ---------- | -------------------------------- | ----------- |
| tokenIds   | uint256[]                        | undefined   |
| tokenInfos | ISamWitchOrderBook.TokenIdInfo[] | undefined   |

## Errors

### ClaimingTooManyOrders

```solidity
error ClaimingTooManyOrders()
```

### DevFeeNotSet

```solidity
error DevFeeNotSet()
```

### DevFeeTooHigh

```solidity
error DevFeeTooHigh()
```

### FailedToTakeFromBook

```solidity
error FailedToTakeFromBook(address taker, enum ISamWitchOrderBook.OrderSide side, uint256 tokenId, uint256 quantityRemaining)
```

#### Parameters

| Name              | Type                              | Description |
| ----------------- | --------------------------------- | ----------- |
| taker             | address                           | undefined   |
| side              | enum ISamWitchOrderBook.OrderSide | undefined   |
| tokenId           | uint256                           | undefined   |
| quantityRemaining | uint256                           | undefined   |

### LengthMismatch

```solidity
error LengthMismatch()
```

### MaxOrdersNotMultipleOfOrdersInSegment

```solidity
error MaxOrdersNotMultipleOfOrdersInSegment()
```

### NoQuantity

```solidity
error NoQuantity()
```

### NotERC1155

```solidity
error NotERC1155()
```

### NotMaker

```solidity
error NotMaker()
```

### NothingToClaim

```solidity
error NothingToClaim()
```

### OrderNotFound

```solidity
error OrderNotFound(uint256 orderId, uint256 price)
```

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| orderId | uint256 | undefined   |
| price   | uint256 | undefined   |

### OrderNotFoundInTree

```solidity
error OrderNotFoundInTree(uint256 orderId, uint256 price)
```

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| orderId | uint256 | undefined   |
| price   | uint256 | undefined   |

### PriceNotMultipleOfTick

```solidity
error PriceNotMultipleOfTick(uint256 tick)
```

#### Parameters

| Name | Type    | Description |
| ---- | ------- | ----------- |
| tick | uint256 | undefined   |

### PriceZero

```solidity
error PriceZero()
```

### TickCannotBeChanged

```solidity
error TickCannotBeChanged()
```

### TokenDoesntExist

```solidity
error TokenDoesntExist(uint256 tokenId)
```

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| tokenId | uint256 | undefined   |

### TooManyOrdersHit

```solidity
error TooManyOrdersHit()
```

### TotalCostConditionNotMet

```solidity
error TotalCostConditionNotMet()
```

### ZeroAddress

```solidity
error ZeroAddress()
```
