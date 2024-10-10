# SamWitchOrderBook

_Sam Witch (PaintSwap, Estfor Kingdom) &amp; 0xDoubleSharp_

> SamWitchOrderBook (SWOB)

This efficient ERC1155 order book is an upgradeable UUPS proxy contract. It has functions for bulk placing limit orders, cancelling limit orders, and claiming NFTs and tokens from filled or partially filled orders. It suppports ERC2981 royalties, and optional dev &amp; burn fees on successful trades.

## Methods

### UPGRADE_INTERFACE_VERSION

```solidity
function UPGRADE_INTERFACE_VERSION() external view returns (string)
```

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | string | undefined   |

### allOrdersAtPrice

```solidity
function allOrdersAtPrice(enum ISamWitchOrderBook.OrderSide _side, uint256 _tokenId, uint72 _price) external view returns (struct ISamWitchOrderBook.Order[])
```

Get all orders at a specific price level

#### Parameters

| Name      | Type                              | Description                                   |
| --------- | --------------------------------- | --------------------------------------------- |
| \_side    | enum ISamWitchOrderBook.OrderSide | The side of the order book to get orders from |
| \_tokenId | uint256                           | The token ID to get orders for                |
| \_price   | uint72                            | The price level to get orders for             |

#### Returns

| Name | Type                       | Description |
| ---- | -------------------------- | ----------- |
| \_0  | ISamWitchOrderBook.Order[] | undefined   |

### cancelAndMakeLimitOrders

```solidity
function cancelAndMakeLimitOrders(uint256[] _orderIds, ISamWitchOrderBook.CancelOrder[] _orders, ISamWitchOrderBook.LimitOrder[] _newOrders) external nonpayable
```

#### Parameters

| Name        | Type                             | Description |
| ----------- | -------------------------------- | ----------- |
| \_orderIds  | uint256[]                        | undefined   |
| \_orders    | ISamWitchOrderBook.CancelOrder[] | undefined   |
| \_newOrders | ISamWitchOrderBook.LimitOrder[]  | undefined   |

### cancelOrders

```solidity
function cancelOrders(uint256[] _orderIds, ISamWitchOrderBook.CancelOrder[] _orders) external nonpayable
```

#### Parameters

| Name       | Type                             | Description |
| ---------- | -------------------------------- | ----------- |
| \_orderIds | uint256[]                        | undefined   |
| \_orders   | ISamWitchOrderBook.CancelOrder[] | undefined   |

### claimAll

```solidity
function claimAll(uint256[] _brushOrderIds, uint256[] _nftOrderIds, uint256[] _tokenIds) external nonpayable
```

Convience function to claim both tokens and nfts in filled or partially filled orders. Must be the maker of these orders.

#### Parameters

| Name            | Type      | Description                                   |
| --------------- | --------- | --------------------------------------------- |
| \_brushOrderIds | uint256[] | Array of order IDs from which to claim tokens |
| \_nftOrderIds   | uint256[] | Array of order IDs from which to claim NFTs   |
| \_tokenIds      | uint256[] | Array of token IDs to claim NFTs for          |

### claimNFTs

```solidity
function claimNFTs(uint256[] _orderIds, uint256[] _tokenIds) external nonpayable
```

Claim NFTs associated with filled or partially filled orders Must be the maker of these orders.

#### Parameters

| Name       | Type      | Description                                 |
| ---------- | --------- | ------------------------------------------- |
| \_orderIds | uint256[] | Array of order IDs from which to claim NFTs |
| \_tokenIds | uint256[] | Array of token IDs to claim NFTs for        |

### claimTokens

```solidity
function claimTokens(uint256[] _orderIds) external nonpayable
```

Claim tokens associated with filled or partially filled orders. Must be the maker of these orders.

#### Parameters

| Name       | Type      | Description                                 |
| ---------- | --------- | ------------------------------------------- |
| \_orderIds | uint256[] | Array of order IDs from which to claim NFTs |

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
function getHighestBid(uint256 _tokenId) external view returns (uint72)
```

Get the highest bid for a specific token ID

#### Parameters

| Name      | Type    | Description                             |
| --------- | ------- | --------------------------------------- |
| \_tokenId | uint256 | The token ID to get the highest bid for |

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | uint72 | undefined   |

### getLowestAsk

```solidity
function getLowestAsk(uint256 _tokenId) external view returns (uint72)
```

Get the lowest ask for a specific token ID

#### Parameters

| Name      | Type    | Description                            |
| --------- | ------- | -------------------------------------- |
| \_tokenId | uint256 | The token ID to get the lowest ask for |

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | uint72 | undefined   |

### getNode

```solidity
function getNode(enum ISamWitchOrderBook.OrderSide _side, uint256 _tokenId, uint72 _price) external view returns (struct BokkyPooBahsRedBlackTreeLibrary.Node)
```

Get the order book entry for a specific order ID

#### Parameters

| Name      | Type                              | Description                                      |
| --------- | --------------------------------- | ------------------------------------------------ |
| \_side    | enum ISamWitchOrderBook.OrderSide | The side of the order book to get the order from |
| \_tokenId | uint256                           | The token ID to get the order for                |
| \_price   | uint72                            | The price level to get the order for             |

#### Returns

| Name | Type                                 | Description |
| ---- | ------------------------------------ | ----------- |
| \_0  | BokkyPooBahsRedBlackTreeLibrary.Node | undefined   |

### getTokenIdInfo

```solidity
function getTokenIdInfo(uint256 _tokenId) external view returns (struct ISamWitchOrderBook.TokenIdInfo)
```

Get the token ID info for a specific token ID

#### Parameters

| Name      | Type    | Description                      |
| --------- | ------- | -------------------------------- |
| \_tokenId | uint256 | The token ID to get the info for |

#### Returns

| Name | Type                           | Description |
| ---- | ------------------------------ | ----------- |
| \_0  | ISamWitchOrderBook.TokenIdInfo | undefined   |

### initialize

```solidity
function initialize(contract IERC1155 _nft, address _token, address _devAddr, uint16 _devFee, uint8 _burntFee, uint16 _maxOrdersPerPrice) external payable
```

Initialize the contract as part of the proxy contract deployment

#### Parameters

| Name                | Type              | Description                                              |
| ------------------- | ----------------- | -------------------------------------------------------- |
| \_nft               | contract IERC1155 | Address of the nft                                       |
| \_token             | address           | The quote token                                          |
| \_devAddr           | address           | The address to receive trade fees                        |
| \_devFee            | uint16            | The fee to send to the dev address (max 10%)             |
| \_burntFee          | uint8             | The fee to burn (max 2.55%)                              |
| \_maxOrdersPerPrice | uint16            | The maximum number of orders allowed at each price level |

### limitOrders

```solidity
function limitOrders(ISamWitchOrderBook.LimitOrder[] _orders) external nonpayable
```

#### Parameters

| Name     | Type                            | Description |
| -------- | ------------------------------- | ----------- |
| \_orders | ISamWitchOrderBook.LimitOrder[] | undefined   |

### marketOrder

```solidity
function marketOrder(ISamWitchOrderBook.MarketOrder _marketOrder) external nonpayable
```

#### Parameters

| Name          | Type                           | Description |
| ------------- | ------------------------------ | ----------- |
| \_marketOrder | ISamWitchOrderBook.MarketOrder | undefined   |

### nftsClaimable

```solidity
function nftsClaimable(uint40[] _orderIds, uint256[] _tokenIds) external view returns (uint256[] amounts_)
```

Get the amount of NFTs claimable for these orders

#### Parameters

| Name       | Type      | Description                                 |
| ---------- | --------- | ------------------------------------------- |
| \_orderIds | uint40[]  | The order IDs to get the claimable NFTs for |
| \_tokenIds | uint256[] | The token IDs to get the claimable NFTs for |

#### Returns

| Name      | Type      | Description |
| --------- | --------- | ----------- |
| amounts\_ | uint256[] | undefined   |

### nodeExists

```solidity
function nodeExists(enum ISamWitchOrderBook.OrderSide _side, uint256 _tokenId, uint72 _price) external view returns (bool)
```

Check if the node exists

#### Parameters

| Name      | Type                              | Description                                      |
| --------- | --------------------------------- | ------------------------------------------------ |
| \_side    | enum ISamWitchOrderBook.OrderSide | The side of the order book to get the order from |
| \_tokenId | uint256                           | The token ID to get the order for                |
| \_price   | uint72                            | The price level to get the order for             |

#### Returns

| Name | Type | Description |
| ---- | ---- | ----------- |
| \_0  | bool | undefined   |

### onERC1155BatchReceived

```solidity
function onERC1155BatchReceived(address, address, uint256[], uint256[], bytes) external nonpayable returns (bytes4)
```

#### Parameters

| Name | Type      | Description |
| ---- | --------- | ----------- |
| \_0  | address   | undefined   |
| \_1  | address   | undefined   |
| \_2  | uint256[] | undefined   |
| \_3  | uint256[] | undefined   |
| \_4  | bytes     | undefined   |

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | bytes4 | undefined   |

### onERC1155Received

```solidity
function onERC1155Received(address, address, uint256, uint256, bytes) external nonpayable returns (bytes4)
```

#### Parameters

| Name | Type    | Description |
| ---- | ------- | ----------- |
| \_0  | address | undefined   |
| \_1  | address | undefined   |
| \_2  | uint256 | undefined   |
| \_3  | uint256 | undefined   |
| \_4  | bytes   | undefined   |

#### Returns

| Name | Type   | Description |
| ---- | ------ | ----------- |
| \_0  | bytes4 | undefined   |

### owner

```solidity
function owner() external view returns (address)
```

_Returns the address of the current owner._

#### Returns

| Name | Type    | Description |
| ---- | ------- | ----------- |
| \_0  | address | undefined   |

### proxiableUUID

```solidity
function proxiableUUID() external view returns (bytes32)
```

_Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the implementation. It is used to validate the implementation&#39;s compatibility when performing an upgrade. IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier._

#### Returns

| Name | Type    | Description |
| ---- | ------- | ----------- |
| \_0  | bytes32 | undefined   |

### renounceOwnership

```solidity
function renounceOwnership() external nonpayable
```

_Leaves the contract without owner. It will not be possible to call `onlyOwner` functions. Can only be called by the current owner. NOTE: Renouncing ownership will leave the contract without an owner, thereby disabling any functionality that is only available to the owner._

### setFees

```solidity
function setFees(address _devAddr, uint16 _devFee, uint8 _burntFee) external nonpayable
```

Set the fees for the contract

#### Parameters

| Name       | Type    | Description                                  |
| ---------- | ------- | -------------------------------------------- |
| \_devAddr  | address | The address to receive trade fees            |
| \_devFee   | uint16  | The fee to send to the dev address (max 10%) |
| \_burntFee | uint8   | The fee to burn (max 2%)                     |

### setMaxOrdersPerPrice

```solidity
function setMaxOrdersPerPrice(uint16 _maxOrdersPerPrice) external payable
```

The maximum amount of orders allowed at a specific price level

#### Parameters

| Name                | Type   | Description                                                        |
| ------------------- | ------ | ------------------------------------------------------------------ |
| \_maxOrdersPerPrice | uint16 | The new maximum amount of orders allowed at a specific price level |

### setTokenIdInfos

```solidity
function setTokenIdInfos(uint256[] _tokenIds, ISamWitchOrderBook.TokenIdInfo[] _tokenIdInfos) external payable
```

#### Parameters

| Name           | Type                             | Description |
| -------------- | -------------------------------- | ----------- |
| \_tokenIds     | uint256[]                        | undefined   |
| \_tokenIdInfos | ISamWitchOrderBook.TokenIdInfo[] | undefined   |

### supportsInterface

```solidity
function supportsInterface(bytes4 interfaceId) external view returns (bool)
```

_See {IERC165-supportsInterface}._

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
function tokensClaimable(uint40[] _orderIds, bool _takeAwayFees) external view returns (uint256 amount_)
```

Get the amount of tokens claimable for these orders

#### Parameters

| Name           | Type     | Description                                             |
| -------------- | -------- | ------------------------------------------------------- |
| \_orderIds     | uint40[] | The order IDs of which to find the claimable tokens for |
| \_takeAwayFees | bool     | Whether to take away the fees from the claimable amount |

#### Returns

| Name     | Type    | Description |
| -------- | ------- | ----------- |
| amount\_ | uint256 | undefined   |

### transferOwnership

```solidity
function transferOwnership(address newOwner) external nonpayable
```

_Transfers ownership of the contract to a new account (`newOwner`). Can only be called by the current owner._

#### Parameters

| Name     | Type    | Description |
| -------- | ------- | ----------- |
| newOwner | address | undefined   |

### updateRoyaltyFee

```solidity
function updateRoyaltyFee() external nonpayable
```

When the nft royalty changes this updates the fee and recipient. Assumes all token ids have the same royalty

### upgradeToAndCall

```solidity
function upgradeToAndCall(address newImplementation, bytes data) external payable
```

_Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call encoded in `data`. Calls {\_authorizeUpgrade}. Emits an {Upgraded} event._

#### Parameters

| Name              | Type    | Description |
| ----------------- | ------- | ----------- |
| newImplementation | address | undefined   |
| data              | bytes   | undefined   |

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

### Initialized

```solidity
event Initialized(uint64 version)
```

_Triggered when the contract has been initialized or reinitialized._

#### Parameters

| Name    | Type   | Description |
| ------- | ------ | ----------- |
| version | uint64 | undefined   |

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

### OwnershipTransferred

```solidity
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
```

#### Parameters

| Name                    | Type    | Description |
| ----------------------- | ------- | ----------- |
| previousOwner `indexed` | address | undefined   |
| newOwner `indexed`      | address | undefined   |

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

### Upgraded

```solidity
event Upgraded(address indexed implementation)
```

_Emitted when the implementation is upgraded._

#### Parameters

| Name                     | Type    | Description |
| ------------------------ | ------- | ----------- |
| implementation `indexed` | address | undefined   |

## Errors

### AddressEmptyCode

```solidity
error AddressEmptyCode(address target)
```

_There&#39;s no code at `target` (it is not a contract)._

#### Parameters

| Name   | Type    | Description |
| ------ | ------- | ----------- |
| target | address | undefined   |

### AddressInsufficientBalance

```solidity
error AddressInsufficientBalance(address account)
```

_The ETH balance of the account is not enough to perform the operation._

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| account | address | undefined   |

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

### ERC1967InvalidImplementation

```solidity
error ERC1967InvalidImplementation(address implementation)
```

_The `implementation` of the proxy is invalid._

#### Parameters

| Name           | Type    | Description |
| -------------- | ------- | ----------- |
| implementation | address | undefined   |

### ERC1967NonPayable

```solidity
error ERC1967NonPayable()
```

_An upgrade function sees `msg.value &gt; 0` that may be lost._

### FailedInnerCall

```solidity
error FailedInnerCall()
```

_A call to an address target failed. The target may have reverted._

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

### InvalidInitialization

```solidity
error InvalidInitialization()
```

_The contract is already initialized._

### KeyCannotBeZero

```solidity
error KeyCannotBeZero()
```

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

### NotInitializing

```solidity
error NotInitializing()
```

_The contract is not initializing._

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

### OwnableInvalidOwner

```solidity
error OwnableInvalidOwner(address owner)
```

_The owner is not a valid owner account. (eg. `address(0)`)_

#### Parameters

| Name  | Type    | Description |
| ----- | ------- | ----------- |
| owner | address | undefined   |

### OwnableUnauthorizedAccount

```solidity
error OwnableUnauthorizedAccount(address account)
```

_The caller account is not authorized to perform an operation._

#### Parameters

| Name    | Type    | Description |
| ------- | ------- | ----------- |
| account | address | undefined   |

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

### SafeCastOverflowedUintDowncast

```solidity
error SafeCastOverflowedUintDowncast(uint8 bits, uint256 value)
```

_Value doesn&#39;t fit in an uint of `bits` size._

#### Parameters

| Name  | Type    | Description |
| ----- | ------- | ----------- |
| bits  | uint8   | undefined   |
| value | uint256 | undefined   |

### SafeERC20FailedOperation

```solidity
error SafeERC20FailedOperation(address token)
```

_An operation with an ERC20 token failed._

#### Parameters

| Name  | Type    | Description |
| ----- | ------- | ----------- |
| token | address | undefined   |

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

### UUPSUnauthorizedCallContext

```solidity
error UUPSUnauthorizedCallContext()
```

_The call is from an unauthorized context._

### UUPSUnsupportedProxiableUUID

```solidity
error UUPSUnsupportedProxiableUUID(bytes32 slot)
```

_The storage `slot` is unsupported as a UUID._

#### Parameters

| Name | Type    | Description |
| ---- | ------- | ----------- |
| slot | bytes32 | undefined   |

### ZeroAddress

```solidity
error ZeroAddress()
```
