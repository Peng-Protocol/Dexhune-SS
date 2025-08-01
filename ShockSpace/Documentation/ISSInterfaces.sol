/* SPDX-License-Identifier: BSD-3-Clause */
pragma solidity ^0.8.2;

//For documentation, can be used in code but it's better to inline the exact methods used. 

// Version: 0.0.6

// Interface for SSAgent contract
interface ISSAgent {
    // Events
    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);
    event GlobalLiquidityChanged(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit);
    event GlobalOrderChanged(uint256 listingId, address tokenA, address tokenB, uint256 orderId, bool isBuy, address maker, uint256 amount, uint8 status);
    event RouterAdded(address indexed router); // Emitted when a router is added
    event RouterRemoved(address indexed router); // Emitted when a router is removed

    // Structs
    struct GlobalOrder {
        uint256 orderId; // Unique order identifier
        bool isBuy; // True for buy order, false for sell
        address maker; // Address creating the order
        address recipient; // Address receiving the order outcome
        uint256 amount; // Order amount
        uint8 status; // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
        uint256 timestamp; // Timestamp of order creation or update
    }

    struct TrendData {
        address token; // Token or user address for sorting
        uint256 timestamp; // Timestamp of data point
        uint256 amount; // Amount for liquidity or volume
    }

    struct OrderData {
        uint256 orderId; // Order identifier
        bool isBuy; // True for buy order, false for sell
        address maker; // Order creator
        address recipient; // Order recipient
        uint256 amount; // Order amount
        uint8 status; // Order status
        uint256 timestamp; // Order timestamp
    }

    struct ListingDetails {
        address listingAddress; // Listing contract address
        address liquidityAddress; // Associated liquidity contract address
        address tokenA; // First token in pair
        address tokenB; // Second token in pair
        uint256 listingId; // Listing ID
    }

    // State Variables
    function routers(uint256 index) external view returns (address); // Array of router contract addresses
    function listingLogicAddress() external view returns (address); // SSListingLogic contract address
    function liquidityLogicAddress() external view returns (address); // SSLiquidityLogic contract address
    function registryAddress() external view returns (address); // Registry contract address
    function listingCount() external view returns (uint256); // Counter for total listings created

    // Mappings
    function getListing(address tokenA, address tokenB) external view returns (address); // tokenA => tokenB => listing address
    function allListings(uint256 index) external view returns (address); // Array of all listing addresses
    function allListedTokens(uint256 index) external view returns (address); // Array of all unique listed tokens
    function queryByAddress(address token, uint256 index) external view returns (uint256); // token => listing IDs
    function liquidityProviders(uint256 listingId, uint256 index) external view returns (address); // listingId => array of users providing liquidity
    function globalLiquidity(address tokenA, address tokenB, address user) external view returns (uint256); // tokenA => tokenB => user => amount
    function totalLiquidityPerPair(address tokenA, address tokenB) external view returns (uint256); // tokenA => tokenB => amount
    function userTotalLiquidity(address user) external view returns (uint256); // user => total liquidity
    function listingLiquidity(uint256 listingId, address user) external view returns (uint256); // listingId => user => amount
    function historicalLiquidityPerPair(address tokenA, address tokenB, uint256 timestamp) external view returns (uint256); // tokenA => tokenB => timestamp => amount
    function historicalLiquidityPerUser(address tokenA, address tokenB, address user, uint256 timestamp) external view returns (uint256); // tokenA => tokenB => user => timestamp => amount
    function globalOrders(address tokenA, address tokenB, uint256 orderId) external view returns (GlobalOrder memory); // tokenA => tokenB => orderId => GlobalOrder
    function pairOrders(address tokenA, address tokenB, uint256 index) external view returns (uint256); // tokenA => tokenB => orderId[]
    function userOrders(address user, uint256 index) external view returns (uint256); // user => orderId[]
    function historicalOrderStatus(address tokenA, address tokenB, uint256 orderId, uint256 timestamp) external view returns (uint8); // tokenA => tokenB => orderId => timestamp => status
    function userTradingSummaries(address user, address tokenA, address tokenB) external view returns (uint256); // user => tokenA => tokenB => volume

    // External Functions
    // Adds a router address to the routers array (owner only)
    function addRouter(address router) external;
    // Removes a router address from the routers array (owner only)
    function removeRouter(address router) external;
    // Returns the current list of routers
    function getRouters() external view returns (address[] memory);
    // Sets listing logic contract address (owner only)
    function setListingLogic(address _listingLogic) external;
    // Sets liquidity logic contract address (owner only)
    function setLiquidityLogic(address _liquidityLogic) external;
    // Sets registry contract address (owner only)
    function setRegistry(address _registryAddress) external;
    // Lists a new token pair, deploying listing and liquidity contracts
    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress);
    // Lists a token paired with native currency
    function listNative(address token, bool isA) external returns (address listingAddress, address liquidityAddress);
    // Checks if a listing address is valid and returns its details
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
    // Updates global liquidity state for a user and emits event
    function globalizeLiquidity(uint256 listingId, address tokenA, address tokenB, address user, uint256 amount, bool isDeposit) external;
    // Updates global order state and emits event
    function globalizeOrders(
        uint256 listingId,
        address tokenA,
        address tokenB,
        uint256 orderId,
        bool isBuy,
        address maker,
        address recipient,
        uint256 amount,
        uint8 status
    ) external;
    // Returns liquidity trend for a token pair
    function getPairLiquidityTrend(address tokenA, bool focusOnTokenA, uint256 startTime, uint256 endTime)
        external view returns (uint256[] memory timestamps, uint256[] memory amounts);
    // Returns liquidity trend for a user across tokens
    function getUserLiquidityTrend(address user, bool focusOnTokenA, uint256 startTime, uint256 endTime)
        external view returns (address[] memory tokens, uint256[] memory timestamps, uint256[] memory amounts);
    // Returns user's liquidity across token pairs
    function getUserLiquidityAcrossPairs(address user, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts);
    // Returns top liquidity providers for a listing
    function getTopLiquidityProviders(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory users, uint256[] memory amounts);
    // Returns user's liquidity share for a token pair
    function getUserLiquidityShare(address user, address tokenA, address tokenB)
        external view returns (uint256 share, uint256 total);
    // Returns pairs with liquidity above a threshold
    function getAllPairsByLiquidity(uint256 minLiquidity, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory amounts);
    // Returns order activity for a token pair within a time range
    function getOrderActivityByPair(address tokenA, address tokenB, uint256 startTime, uint256 endTime)
        external view returns (uint256[] memory orderIds, OrderData[] memory orders);
    // Returns user's trading profile across token pairs
    function getUserTradingProfile(address user)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes);
    // Returns top traders by volume for a listing
    function getTopTradersByVolume(uint256 listingId, uint256 maxIterations)
        external view returns (address[] memory traders, uint256[] memory volumes);
    // Returns pairs with order volume above a threshold
    function getAllPairsByOrderVolume(uint256 minVolume, bool focusOnTokenA, uint256 maxIterations)
        external view returns (address[] memory tokenAs, address[] memory tokenBs, uint256[] memory volumes);
    // Returns listing address by index
    function queryByIndex(uint256 index) external view returns (address);
    // Returns paginated listing IDs for a token
    function queryByAddressView(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory);
    // Returns number of listing IDs for a token
    function queryByAddressLength(address target) external view returns (uint256);
    // Returns total number of listings
    function allListingsLength() external view returns (uint256);
    // Returns total number of listed tokens
    function allListedTokensLength() external view returns (uint256);
}

// Interface for SSLiquidityTemplate contract
interface ISSLiquidityTemplate {
    // Events
    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed caller, uint256 listingId, bool isX, uint256 amount);
    event UpdateRegistryFailed(address indexed caller, bool isX);

    // Structs
    struct LiquidityDetails {
        uint256 xLiquid; // Total liquidity for tokenA
        uint256 yLiquid; // Total liquidity for tokenB
        uint256 xFees;   // Accumulated fees for tokenA
        uint256 yFees;   // Accumulated fees for tokenB
        uint256 xFeesAcc; // Cumulative fee volume for x-token
        uint256 yFeesAcc; // Cumulative fee volume for y-token
    }

    struct Slot {
        address depositor;  // Address of the liquidity provider
        address recipient;  // Address to receive withdrawals (not used)
        uint256 allocation; // Amount of liquidity allocated to the slot
        uint256 dFeesAcc;   // Cumulative fees at deposit (yFeesAcc for xSlot, xFeesAcc for ySlot)
        uint256 timestamp;  // Timestamp of slot creation
    }

    struct UpdateType {
        uint8 updateType;  // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;     // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value;     // Amount or allocation (normalized to 18 decimals)
        address addr;      // Depositor address
        address recipient; // Recipient address (not used)
    }

    struct PreparedWithdrawal {
        uint256 amountA; // Amount of tokenA to withdraw
        uint256 amountB; // Amount of tokenB to withdraw
    }

    // Mappings
    function routers(address router) external view returns (bool); // Tracks registered router addresses
    function xLiquiditySlots(uint256 index) external view returns (Slot memory); // Stores liquidity slots for tokenA
    function yLiquiditySlots(uint256 index) external view returns (Slot memory); // Stores liquidity slots for tokenB
    function activeXLiquiditySlots(uint256 index) external view returns (uint256); // Lists active liquidity slot indices for tokenA
    function activeYLiquiditySlots(uint256 index) external view returns (uint256); // Lists active liquidity slot indices for tokenB
    function userIndex(address user) external view returns (uint256[] memory); // Maps user address to their liquidity slot indices

    // External Functions
    // Sets router addresses (callable once)
    function setRouters(address[] memory _routers) external;
    // Sets the listing ID (callable once)
    function setListingId(uint256 _listingId) external;
    // Sets the listing contract address (callable once)
    function setListingAddress(address _listingAddress) external;
    // Sets tokenA and tokenB addresses (callable once)
    function setTokens(address _tokenA, address _tokenB) external;
    // Sets the agent contract address (callable once)
    function setAgent(address _agent) external;
    // Updates liquidity or fees (router only)
    function update(address caller, UpdateType[] memory updates) external;
    // Changes the depositor of a liquidity slot (router only)
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external;
    // Deposits liquidity for tokenA or tokenB (router only)
    function deposit(address caller, address token, uint256 amount) external payable;
    // Prepares withdrawal for tokenA liquidity slot (router only)
    function xPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    // Executes withdrawal for tokenA liquidity slot (router only)
    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    // Prepares withdrawal for tokenB liquidity slot (router only)
    function yPrepOut(address caller, uint256 amount, uint256 index) external returns (PreparedWithdrawal memory);
    // Executes withdrawal for tokenB liquidity slot (router only)
    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external;
    // Claims fees for a liquidity provider (router only, xSlots claim yFees, ySlots claim xFees)
    function claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
    // Transfers tokens or ETH (router only)
    function transact(address caller, address token, uint256 amount, address recipient) external;
    // Adds fees to liquidity pool (router only)
    function addFees(address caller, bool isX, uint256 fee) external;
    // Updates liquidity amounts (router only)
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    // Returns the listing address
    function getListingAddress(uint256) external view returns (address);
    // Returns current liquidity amounts for tokenA and tokenB
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    // Returns liquidity details (xLiquid, yLiquid, xFees, yFees, xFeesAcc, yFeesAcc)
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc);
    // Returns active tokenA liquidity slot indices
    function activeXLiquiditySlotsView() external view returns (uint256[] memory);
    // Returns active tokenB liquidity slot indices
    function activeYLiquiditySlotsView() external view returns (uint256[] memory);
    // Returns user's liquidity slot indices
    function userIndexView(address user) external view returns (uint256[] memory);
    // Returns tokenA slot details by index
    function getXSlotView(uint256 index) external view returns (Slot memory);
    // Returns tokenB slot details by index
    function getYSlotView(uint256 index) external view returns (Slot memory);
}

// Interface for SSListingTemplate contract
interface ISSListingTemplate {
    // Events
    event OrderUpdated(uint256 listingId, uint256 orderId, bool isBuy, uint8 status);
    event PayoutOrderCreated(uint256 orderId, bool isLong, uint8 status);
    event BalancesUpdated(uint256 listingId, uint256 xBalance, uint256 yBalance);

    // Structs
    struct VolumeBalance {
        uint256 xBalance; // Balance of tokenX
        uint256 yBalance; // Balance of tokenY
        uint256 xVolume;  // Trading volume of tokenX
        uint256 yVolume;  // Trading volume of tokenY
    }

    struct BuyOrderCore {
        address makerAddress;    // Address of the order creator
        address recipientAddress;// Address to receive filled order
        uint8 status;           // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct BuyOrderPricing {
        uint256 maxPrice; // Maximum price for buy order
        uint256 minPrice; // Minimum price for buy order
    }

    struct BuyOrderAmounts {
        uint256 pending;    // Amount of tokenY pending
        uint256 filled;     // Amount of tokenY filled
        uint256 amountSent; // Amount of tokenX sent during settlement
    }

    struct SellOrderCore {
        address makerAddress;    // Address of the order creator
        address recipientAddress;// Address to receive filled order
        uint8 status;           // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct SellOrderPricing {
        uint256 maxPrice; // Maximum price for sell order
        uint256 minPrice; // Minimum price for sell order
    }

    struct SellOrderAmounts {
        uint256 pending;    // Amount of tokenX pending
        uint256 filled;     // Amount of tokenX filled
        uint256 amountSent; // Amount of tokenY sent during settlement
    }

    struct PayoutUpdate {
        uint8 payoutType; // 0 = Long, 1 = Short
        address recipient;// Address to receive payout
        uint256 required; // Amount required for payout
    }

    struct LongPayoutStruct {
        address makerAddress;    // Address of the payout creator
        address recipientAddress;// Address to receive payout
        uint256 required;       // Amount required for payout
        uint256 filled;         // Amount filled
        uint256 orderId;        // Order ID
        uint8 status;           // Payout status
    }

    struct ShortPayoutStruct {
        address makerAddress;    // Address of the payout creator
        address recipientAddress;// Address to receive payout
        uint256 amount;         // Amount for payout
        Ascending
        uint256 filled;         // Amount filled
        uint256 orderId;        // Order ID
        uint8 status;           // Payout status
    }

    struct HistoricalData {
        uint256 price;     // Historical price
        uint256 xBalance;  // Historical tokenX balance
        uint256 yBalance;  // Historical tokenY balance
        uint256 xVolume;   // Historical tokenX volume
        uint256 yVolume;   // Historical tokenY volume
        uint256 timestamp; // Timestamp of the data
    }

    struct UpdateType {
        uint8 updateType;  // 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId;    // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index;     // Order ID or balance/volume index (0 = xBalance, 1 = yBalance, 2 = xVolume, 3 = yVolume)
        uint256 value;     // Amount or price (normalized)
        address addr;      // Maker address
        address recipient; // Recipient address
        uint256 maxPrice;  // Max price for pricing struct or packed xBalance/yBalance
        uint256 minPrice;  // Min price for pricing struct or packed xVolume/yVolume
        uint256 amountSent;// Amount of opposite token sent during settlement
    }

    // Mappings
    function routers(address router) external view returns (bool); // Tracks registered router addresses
    function buyOrderCores(uint256 orderId) external view returns (BuyOrderCore memory); // Stores buy order core details by order ID
    function buyOrderPricings(uint256 orderId) external view returns (BuyOrderPricing memory); // Stores buy order pricing details by order ID
    function buyOrderAmounts(uint256 orderId) external view returns (BuyOrderAmounts memory); // Stores buy order amounts by order ID
    function sellOrderCores(uint256 orderId) external view returns (SellOrderCore memory); // Stores sell order core details by order ID
    function sellOrderPricings(uint256 orderId) external view returns (SellOrderPricing memory); // Stores sell order pricing details by order ID
    function sellOrderAmounts(uint256 orderId) external view returns (SellOrderAmounts memory); // Stores sell order amounts by order ID
    function longPayouts(uint256 orderId) external view returns (LongPayoutStruct memory); // Stores long payout details by order ID
    function shortPayouts(uint256 orderId) external view returns (ShortPayoutStruct memory); // Stores short payout details by order ID
    function pendingBuyOrders(uint256 index) external view returns (uint256); // Lists pending buy order IDs
    function pendingSellOrders(uint256 index) external view returns (uint256); // Lists pending sell order IDs
    function longPayoutsByIndex(uint256 index) external view returns (uint256); // Lists long payout order IDs
    function shortPayoutsByIndex(uint256 index) external view returns (uint256); // Lists short payout order IDs
    function userPayoutIDs(address user) external view returns (uint256[] memory); // Maps user address to their payout order IDs
    function makerPendingOrders(address maker) external view returns (uint256[] memory); // Maps maker address to their pending order IDs
    function historicalData(uint256 index) external view returns (HistoricalData memory); // Stores historical data by index

    // External Functions
    // Sets router addresses (callable once)
    function setRouters(address[] memory _routers) external;
    // Sets the listing ID (callable once)
    function setListingId(uint256 _listingId) external;
    // Sets the liquidity contract address (callable once)
    function setLiquidityAddress(address _liquidityAddress) external;
    // Sets tokenX and tokenY addresses (callable once)
    function setTokens(address _tokenA, address _tokenB) external;
    // Sets the agent contract address (callable once)
    function setAgent(address _agent) external;
    // Sets the registry contract address (callable once)
    function setRegistry(address _registryAddress) external;
    // Updates balances, orders, or historical data (router only)
    function update(address caller, UpdateType[] memory updates) external;
    // Processes payout updates (router only)
    function ssUpdate(address caller, PayoutUpdate[] memory payoutUpdates) external;
    // Handles token or ETH transfers (router only)
    function transact(address caller, address token, uint256 amount, address recipient) external;
    // Queries annualized yield for tokenX or tokenY
    function queryYield(bool isA, uint256 maxIterations) external view returns (uint256);
    // Returns current price
    function prices(uint256) external view returns (uint256);
    // Returns volume balances (xBalance, yBalance)
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    // Returns liquidity contract address
    function liquidityAddressView(uint256) external view returns (address);
    // Returns tokenX and tokenY addresses
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    // Returns tokenX decimals
    function decimalsA() external view returns (uint8);
    // Returns tokenY decimals
    function decimalsB() external view returns (uint8);
    // Returns listing ID
    function getListingId() external view returns (uint256);
    // Returns next order ID
    function getNextOrderId() external view returns (uint256);
    // Returns volume balance details
    function listingVolumeBalancesView() external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    // Returns current price
    function listingPriceView() external view returns (uint256);
    // Returns pending buy order IDs
    function pendingBuyOrdersView() external view returns (uint256[] memory);
    // Returns pending sell order IDs
    function pendingSellOrdersView() external view returns (uint256[] memory);
    // Returns maker's pending order IDs
    function makerPendingOrdersView(address maker) external view returns (uint256[] memory);
    // Returns long payout order IDs
    function longPayoutByIndexView() external view returns (uint256[] memory);
    // Returns short payout order IDs
    function shortPayoutByIndexView() external view returns (uint256[] memory);
    // Returns user's payout order IDs
    function userPayoutIDsView(address user) external view returns (uint256[] memory);
    // Returns long payout details by order ID
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory);
    // Returns short payout details by order ID
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory);
    // Returns buy order core details
    function getBuyOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    // Returns buy order pricing details
    function getBuyOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    // Returns buy order amounts
    function getBuyOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    // Returns sell order core details
    function getSellOrderCore(uint256 orderId) external view returns (address makerAddress, address recipientAddress, uint8 status);
    // Returns sell order pricing details
    function getSellOrderPricing(uint256 orderId) external view returns (uint256 maxPrice, uint256 minPrice);
    // Returns sell order amounts
    function getSellOrderAmounts(uint256 orderId) external view returns (uint256 pending, uint256 filled, uint256 amountSent);
    // Returns historical data by index
    function getHistoricalDataView(uint256 index) external view returns (HistoricalData memory);
    // Returns historical data length
    function historicalDataLengthView() external view returns (uint256);
    // Returns historical data by nearest timestamp
    function getHistoricalDataByNearestTimestamp(uint256 targetTimestamp) external view returns (HistoricalData memory);
}

// Interface for SSRouter contract
interface ISSRouter {
    // Structs
    struct BuyOrderDetails {
        uint256 orderId;        // Unique identifier for the buy order
        address maker;          // Address of the order creator
        address receiver;       // Address to receive filled order
        uint256 pending;        // Amount of tokenY pending
        uint256 filled;         // Amount of tokenY filled
        uint256 maxPrice;       // Maximum price for the order
        uint256 minPrice;       // Minimum price for the order
        uint8 status;           // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct SellOrderDetails {
        uint256 orderId;        // Unique identifier for the sell order
        address maker;          // Address of the order creator
        address receiver;       // Address to receive filled order
        uint256 pending;        // Amount of tokenX pending
        uint256 filled;         // Amount of tokenX filled
        uint256 maxPrice;       // Maximum price for the order
        uint256 minPrice;       // Minimum price for the order
        uint8 status;           // 0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled
    }

    struct OrderClearData {
        uint256 orderId;        // Order ID to clear
        bool isBuy;             // True if buy order, false if sell order
        uint256 amount;         // Amount to clear
    }

    struct OrderContext {
        ISSListingTemplate listingContract; // Reference to the listing contract
        address tokenIn;                   // Input token address
        address tokenOut;                  // Output token address
        address liquidityAddr;             // Liquidity contract address
    }

    struct SellOrderUpdateContext {
        address makerAddress;    // Address of the sell order creator
        address recipient;       // Address to receive filled order
        uint8 status;            // Order status
        uint256 amountReceived;  // Amount of tokenY received
        uint256 normalizedReceived; // Normalized amount received
        uint256 amountSent;      // Amount of tokenY sent
    }

    struct BuyOrderUpdateContext {
        address makerAddress;    // Address of the buy order creator
        address recipient;       // Address to receive filled order
        uint8 status;            // Order status
        uint256 amountReceived;  // Amount of tokenX received
        uint256 normalizedReceived; // Normalized amount received
        uint256 amountSent;      // Amount of tokenX sent
    }

    // External Functions
    // Sets the agent address (owner only)
    function setAgent(address newAgent) external;
    // Returns the current agent address
    function agentView() external view returns (address);
    // Creates a buy order, transfers input tokens, and executes
    function createBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable;
    // Creates a sell order, transfers input tokens, and executes
    function createSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable;
    // Settles multiple buy orders up to maxIterations
    function settleBuyOrders(address listingAddress, uint256 maxIterations) external;
    // Settles multiple sell orders up to maxIterations
    function settleSellOrders(address listingAddress, uint256 maxIterations) external;
    // Settles multiple buy order liquidations up to maxIterations
    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external;
    // Settles multiple sell order liquidations up to maxIterations
    function settleSellLiquid(address listingAddress, uint256 maxIterations) external;
    // Settles multiple long liquidations up to maxIterations
    function settleLongLiquid(address listingAddress, uint256 maxIterations) external;
    // Settles multiple short liquidations up to maxIterations
    function settleShortLiquid(address listingAddress, uint256 maxIterations) external;
    // Executes long payouts
    function settleLongPayouts(address listingAddress, uint256 maxIterations) external;
    // Executes short payouts
    function settleShortPayouts(address listingAddress, uint256 maxIterations) external;
    // Deposits tokens or ETH to liquidity pool
    function deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user) external payable;
    // Withdraws tokens from liquidity pool
    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user) external;
    // Claims fees from liquidity pool
    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user) external;
    // Clears a single order
    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external;
    // Clears multiple orders up to maxIterations
    function clearOrders(address listingAddress, uint256 maxIterations) external;
    // Changes depositor for a liquidity slot
    function changeDepositor(
        address listingAddress,
        bool isX,
        uint256 slotIndex,
        address newDepositor,
        address user
    ) external;
}

// Interface for SSCrossDriver contract

interface ISSCrossDriver {
    // Events
    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType);
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    event PositionCancelled(uint256 indexed positionId, address indexed maker);
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp);
    event AllLongsClosed(address indexed maker, uint256 processed);
    event AllLongsCancelled(address indexed maker, uint256 processed);
    event AllShortsClosed(address indexed maker, uint256 processed);
    event AllShortsCancelled(address indexed maker, uint256 processed);
    event MuxAdded(address indexed mux);
    event MuxRemoved(address indexed mux);

    // Structs
    struct PositionCore1 {
        uint256 positionId;      // Unique identifier for the position
        address listingAddress; // Address of the associated listing contract
        address makerAddress;   // Address of the position creator
        uint8 positionType;     // 0 = Long, 1 = Short
    }

    struct PositionCore2 {
        bool status1;           // True if position is executable
        uint8 status2;          // 0 = Open, 1 = Closed
    }

    struct PriceParams1 {
        uint256 minEntryPrice;  // Minimum entry price (normalized)
        uint256 maxEntryPrice;  // Maximum entry price (normalized)
        uint256 minPrice;       // Minimum price for liquidation
        uint256 priceAtEntry;   // Actual entry price (normalized)
        uint8 leverage;         // Leverage multiplier
    }

    struct PriceParams2 {
        uint256 liquidationPrice; // Price at which position is liquidated (normalized)
    }

    struct MarginParams1 {
        uint256 initialMargin;  // Initial margin provided (normalized)
        uint256 taxedMargin;    // Margin after fees (normalized)
        uint256 excessMargin;   // Additional margin provided (normalized)
        uint256 fee;            // Fee charged for the position
    }

    struct MarginParams2 {
        uint256 initialLoan;    // Loan amount for leveraged position (normalized)
    }

    struct ExitParams {
        uint256 stopLossPrice;  // Stop loss price (normalized)
        uint256 takeProfitPrice;// Take profit price (normalized)
        uint256 exitPrice;      // Actual exit price (normalized)
    }

    struct OpenInterest {
        uint256 leverageAmount; // Leveraged amount for the position
        uint256 timestamp;      // Timestamp of position creation
    }

    struct EntryContext {
        uint256 positionId;     // Unique identifier for the position
        address listingAddress; // Address of the associated listing contract
        uint256 minEntryPrice;  // Minimum entry price (normalized)
        uint256 maxEntryPrice;  // Maximum entry price (normalized)
        uint256 initialMargin;  // Initial margin provided (normalized)
        uint256 excessMargin;   // Additional margin provided (normalized)
        uint8 leverage;         // Leverage multiplier
        uint8 positionType;     // 0 = Long, 1 = Short
        address maker;         // Address of the position creator
        address token;         // Token address
    }

    // State Variables
    function positionCount() external view returns (uint256); // Total number of positions created
    function agentAddress() external view returns (address); // Address of the agent contract

    // Mappings
    function positionToken(uint256 positionId) external view returns (address); // Maps position ID to token address
    function longIOByHeight(uint256 height) external view returns (uint256); // Tracks long open interest by block height
    function shortIOByHeight(uint256 height) external view returns (uint256); // Tracks short open interest by block height
    function historicalInterestTimestamps(uint256 height) external view returns (uint256); // Stores timestamps for historical interest by block height
    function makerTokenMargin(address maker, address token) external view returns (uint256); // Tracks maker's margin balance by token
    function makerMarginTokens(address maker) external view returns (address[] memory); // Lists tokens with non-zero margin for a maker
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory); // Stores position core data (part 1)
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory); // Stores position core data (part 2)
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory); // Stores price parameters (part 1)
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory); // Stores price parameters (part 2)
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory); // Stores margin parameters (part 1)
    function marginParams2(uint256 positionId) external view returns (MarginParams2 memory); // Stores margin parameters (part 2)
    function exitParams(uint256 positionId) external view returns (ExitParams memory); // Stores exit parameters
    function openInterest(uint256 positionId) external view returns (OpenInterest memory); // Stores open interest data
    function positionsByType(uint8 positionType) external view returns (uint256[] memory); // Lists positions by type (0 = Long, 1 = Short)
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory); // Maps listing address to pending positions by type
    function muxes(address mux) external view returns (bool); // Tracks authorized mux contracts

    // External Functions
    // Sets the agent address (owner only)
    function setAgent(address newAgentAddress) external;
    // Adds a new mux to the authorized list (owner only)
    function addMux(address mux) external;
    // Removes a mux from the authorized list (owner only)
    function removeMux(address mux) external;
    // Returns a list of all authorized muxes
    function getMuxesView() external view returns (address[] memory);
    // Creates a position on behalf of a maker
    function drive(
        address maker,
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) external;
    // Closes a specific position for a maker, directing payout to the mux (mux only)
    function drift(uint256 positionId, address maker) external;
    // Enters a long position with specified parameters
    function enterLong(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external;
    // Enters a short position with specified parameters
    function enterShort(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external;
    // Adds excess margin to open positions for a maker
    function addExcessMargin(address listingAddress, bool tokenA, uint256 amount, address maker) external;
    // Withdraws margin from a listing
    function pullMargin(address listingAddress, bool tokenA, uint256 amount) external;
    // Closes a long position by ID
    function closeLongPosition(uint256 positionId) external;
    // Closes a short position by ID
    function closeShortPosition(uint256 positionId) external;
    // Cancels a position by ID
    function cancelPosition(uint256 positionId) external;
    // Updates stop loss price for a position
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external;
    // Updates take profit price for a position
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external;
    // Closes all long positions for the caller up to maxIterations
    function closeAllLongs(uint256 maxIterations) external;
    // Cancels all long positions for the caller up to maxIterations
    function cancelAllLongs(uint256 maxIterations) external;
    // Closes all short positions for the caller up to maxIterations
    function closeAllShorts(uint256 maxIterations) external;
    // Cancels all short positions for the caller up to maxIterations
    function cancelAllShorts(uint256 maxIterations) external;
    // Executes pending positions for a listing up to maxIterations
    function executePositions(address listingAddress, uint256 maxIterations) external;
    // Returns position IDs by type with pagination
    function PositionsByTypeView(uint8 positionType, uint256 startIndex, uint256 maxIterations) 
        external view returns (uint256[] memory);
    // Returns position IDs by maker address with pagination
    function PositionsByAddressView(address maker, uint256 startIndex, uint256 maxIterations) 
        external view returns (uint256[] memory);
    // Returns detailed position data by ID
    function positionByIndex(uint256 positionId) external view returns (
        PositionCore1 memory core1,
        PositionCore2 memory core2,
        PriceParams1 memory price1,
        PriceParams2 memory price2,
        MarginParams1 memory margin1,
        MarginParams2 memory margin2,
        ExitParams memory exit,
        address token
    );
    // Returns total number of active positions
    function TotalActivePositionsView() external view returns (uint256);
    // Queries historical interest data with pagination
    function queryInterest(uint256 startIndex, uint256 maxIterations) 
        external view returns (
            uint256[] memory longIO,
            uint256[] memory shortIO,
            uint256[] memory timestamps
        );
    // Queries maker's margin balances by token with pagination
    function makerMarginIndex(address maker, uint256 startIndex, uint256 maxIterations) 
        external view returns (address[] memory tokens, uint256[] memory margins);
    // Queries position health metrics
    function PositionHealthView(uint256 positionId) 
        external view returns (
            uint256 marginRatio,
            uint256 distanceToLiquidation,
            uint256 estimatedProfitLoss
        );
    // Aggregates margin by token across makers
    function AggregateMarginByToken(
        address tokenA,
        address tokenB,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory makers, uint256[] memory margins);
    // Queries open interest trends for a listing
    function OpenInterestTrend(
        address listingAddress,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps);
    // Counts positions at risk of liquidation
    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) 
        external view returns (uint256);
}

// Interface for SSIsolatedDriver contract

interface ISSIsolatedDriver {
    // Events
    // Emitted when a mux is added.
    event MuxAdded(address indexed mux);
    
    // Emitted when a mux is removed.
    event MuxRemoved(address indexed mux);
    
    // Emitted when a position is created.
    event PositionEntered(
        uint256 indexed positionId,
        address indexed maker,
        uint8 positionType,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address mux
    );
    
    // Emitted when a position is closed.
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);
    
    // Emitted when a position is cancelled.
    event PositionCancelled(uint256 indexed positionId, address indexed maker);
    
    // Emitted when excess margin is added.
    event ExcessMarginAdded(uint256 indexed positionId, address indexed maker, uint256 amount);
    
    // Emitted when stop-loss is updated.
    event StopLossUpdated(uint256 indexed positionId, address indexed maker, uint256 newStopLossPrice);
    
    // Emitted when take-profit is updated.
    event TakeProfitUpdated(uint256 indexed positionId, address indexed maker, uint256 newTakeProfitPrice);
    
    // Emitted when all long positions are closed.
    event AllLongsClosed(address indexed maker, uint256 count);
    
    // Emitted when all long positions are cancelled.
    event AllLongsCancelled(address indexed maker, uint256 count);
    
    // Emitted when all short positions are closed.
    event AllShortsClosed(address indexed maker, uint256 count);
    
    // Emitted when all short positions are cancelled.
    event AllShortsCancelled(address indexed maker, uint256 count);
    
    // Emitted when positions are executed.
    event PositionsExecuted(address indexed listingAddress, uint256 count);

    // State Variables
    // Precision for normalizing amounts/prices (1e18).
    uint256 constant DECIMAL_PRECISION = 1e18;
    
    // ISSAgent address for listing validation.
    address agent;
    
    // Block height for open interest updates, starts at 1.
    uint256 historicalInterestHeight;
    
    // Nonce for transaction tracking, starts at 0.
    uint256 nonce;
    
    // Counter for unique position IDs, starts at 1.
    uint256 positionIdCounter;
    
    // Mappings
    // Authorized mux contracts for position management.
    mapping(address => bool) muxes;
    
    // Core position data: maker, listing, ID, type.
    mapping(uint256 => PositionCoreBase) positionCoreBase;
    
    // Position status: pending/executable, open/closed/cancelled.
    mapping(uint256 => PositionCoreStatus) positionCoreStatus;
    
    // Price data: min/max entry, entry, close prices.
    mapping(uint256 => PriceParams) priceParams;
    
    // Margin details: initial, taxed, excess.
    mapping(uint256 => MarginParams) marginParams;
    
    // Leverage details: value, amount, initial loan.
    mapping(uint256 => LeverageParams) leverageParams;
    
    // Risk parameters: liquidation, stop-loss, take-profit.
    mapping(uint256 => RiskParams) riskParams;
    
    // Pending position IDs by maker and type (0: long, 1: short).
    mapping(address => mapping(uint8 => uint256[])) pendingPositions;
    
    // Position IDs by type (0: long, 1: short).
    mapping(uint8 => uint256[]) positionsByType;
    
    // Position ID to margin token (tokenA: long, tokenB: short).
    mapping(uint256 => address) positionToken;
    
    // Long open interest by block height.
    mapping(uint256 => uint256) longIOByHeight;
    
    // Short open interest by block height.
    mapping(uint256 => uint256) shortIOByHeight;
    
    // Timestamps for open interest updates.
    mapping(uint256 => uint256) historicalInterestTimestamps;
    
    // Temporary storage for position entry parameters.
    mapping(uint256 => PendingEntry) pendingEntries;

    // Structs
    // Core position data: maker, listing, ID, type (0: long, 1: short).
    struct PositionCoreBase {
        address makerAddress;
        address listingAddress;
        uint256 positionId;
        uint8 positionType;
    }

    // Position status: pending/executable, open/closed/cancelled.
    struct PositionCoreStatus {
        bool status1; // false: pending, true: executable
        uint8 status2; // 0: open, 1: closed, 2: cancelled
    }

    // Price parameters: min/max entry, entry, close (1e18 normalized).
    struct PriceParams {
        uint256 priceMin;
        uint256 priceMax;
        uint256 priceAtEntry;
        uint256 priceClose;
    }

    // Margin details: initial, taxed, excess (1e18 normalized).
    struct MarginParams {
        uint256 marginInitial;
        uint256 marginTaxed;
        uint256 marginExcess;
    }

    // Leverage details: value (2–100), amount, initial loan (1e18 normalized).
    struct LeverageParams {
        uint8 leverageVal;
        uint256 leverageAmount;
        uint256 loanInitial;
    }

    // Risk parameters: liquidation, stop-loss, take-profit (1e18 normalized).
    struct RiskParams {
        uint256 priceLiquidation;
        uint256 priceStopLoss;
        uint256 priceTakeProfit;
    }

    // Combines price and margin parameters.
    struct PosParamsCore {
        PriceParams priceParams;
        MarginParams marginParams;
    }

    // Combines leverage and risk parameters.
    struct PosParamsExt {
        LeverageParams leverageParams;
        RiskParams riskParams;
    }

    // Entry parameters: listing, price range, margins.
    struct EntryParamsBase {
        address listingAddr;
        string entryPriceStr;
        uint256 initMargin;
        uint256 extraMargin;
    }

    // Entry risk parameters: leverage, stop-loss, take-profit.
    struct EntryParamsRisk {
        uint8 leverageVal;
        uint256 stopLoss;
        uint256 takeProfit;
    }

    // Entry token parameters: token, normalized margins, driver.
    struct EntryParamsToken {
        address tokenAddr;
        uint256 normInitMargin;
        uint256 normExtraMargin;
        address driverAddr;
    }

    // Closing position data: ID, listing, maker, driver.
    struct ClosePositionBase {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        address driver;
    }

    // Closing position margin: taxed, excess.
    struct ClosePositionMargin {
        uint256 taxedMargin;
        uint256 excessMargin;
    }

    // Long position close: leverage amount, initial loan.
    struct LongCloseParams {
        uint256 leverageAmount;
        uint256 loanInitial;
    }

    // Short position close: min price, initial margin, leverage.
    struct ShortCloseParams {
        uint256 minPrice;
        uint256 initialMargin;
        uint8 leverage;
    }

    // Position action: ID, action type (0: update, 1: close).
    struct PositionAction {
        uint256 positionId;
        uint8 actionType;
    }

    // Execution context: listing, driver, current price.
    struct ExecutionContextBase {
        address listingAddress;
        address driver;
        uint256 currentPrice;
    }

    // Execution counts: action count, max actions.
    struct ExecutionContextCounts {
        uint256 actionCount;
        uint256 maxActions;
    }

    // Entry context: listing, token, normalized margins.
    struct EntryContext {
        address listingAddr;
        address tokenAddr;
        uint256 normInitMargin;
        uint256 normExtraMargin;
    }

    // Pending entry parameters.
    struct PendingEntry {
        address listingAddr;
        address tokenAddr;
        uint256 positionId;
        uint8 positionType;
        uint256 initialMargin;
        uint256 extraMargin;
        string entryPriceStr;
        address makerAddress;
        uint8 leverageVal;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 normInitMargin;
        uint256 normExtraMargin;
    }

    // Payout update: recipient, amount, type (0: long, 1: short).
    struct PayoutUpdate {
        address recipient;
        uint256 required;
        uint8 payoutType;
    }

    // Listing update: type, index, value, addresses.
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }

    // External Functions
    // Sets ISSAgent address, owner only.
    function setAgent(address newAgent) external;

    // Authorizes mux contract, owner only.
    function addMux(address mux) external;

    // Deauthorizes mux contract, owner only.
    function removeMux(address mux) external;

    // Returns authorized mux addresses.
    function getMuxesView() external view returns (address[] memory);

    // Creates position for maker, market order if min/max prices zero.
    function drive(
        address maker,
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) external returns (uint256);

    // Closes position via mux for specified maker based on price triggers, pays to mux.
    function drift(uint256 positionId, address maker) external;

    // Creates pending long position, market order if entryPriceStr is "0" or "0-0".
    function enterLong(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) external;

    // Creates pending short position, market order if entryPriceStr is "0" or "0-0".
    function enterShort(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) external;

    // Adds margin to open position, updates liquidation price.
    function addExcessMargin(uint256 positionId, uint256 amount, address token) external;

    // Closes long position, pays tokenB to caller.
    function closeLongPosition(uint256 positionId) external;

    // Closes short position, pays tokenA to caller.
    function closeShortPosition(uint256 positionId) external;

    // Cancels pending position, returns margins to caller.
    function cancelPosition(uint256 positionId) external;

    // Updates stop-loss price for open position.
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external;

    // Updates take-profit price for open position.
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external;

    // Closes all active long positions for caller, up to maxIterations.
    function closeAllLongs(uint256 maxIterations) external;

    // Cancels all pending long positions for caller, up to maxIterations.
    function cancelAllLong(uint256 maxIterations) external;

    // Closes all active short positions for caller, up to maxIterations.
    function closeAllShort(uint256 maxIterations) external;

    // Cancels all pending short positions for caller, up to maxIterations.
    function cancelAllShort(uint256 maxIterations) external;

    // Processes pending/active positions, activates/closes based on price triggers.
    function executePositions(address listingAddress) external;

    // Returns active position IDs by type (0: long, 1: short) from step.
    function positionsByTypeView(uint8 positionType, uint256 step, uint256 maxIterations)
        external
        view
        returns (uint256[] memory);

    // Returns pending position IDs for user by type from step.
    function positionsByAddressView(address user, uint8 positionType, uint256 step, uint256 maxIterations)
        external
        view
        returns (uint256[] memory);

    // Returns position data: core, status, price, margin, leverage, risk, token.
    function positionByIndex(uint256 positionId)
        external
        view
        returns (
            PositionCoreBase memory,
            PositionCoreStatus memory,
            PriceParams memory,
            MarginParams memory,
            LeverageParams memory,
            RiskParams memory,
            address
        );

    // Returns open interest and timestamps from step.
    function queryInterest(uint256 step, uint256 maxIterations)
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory);
}