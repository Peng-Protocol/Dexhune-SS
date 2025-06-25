/* SPDX-License-Identifier: BSD-3-Clause */
pragma solidity ^0.8.2;

// Version: 0.0.4

// Interface for SSLiquidityTemplate contract
interface ISSLiquidityTemplate {
    // Structs
    struct LiquidityDetails {
        uint256 xLiquid; // Total liquidity for tokenA
        uint256 yLiquid; // Total liquidity for tokenB
        uint256 xFees;   // Accumulated fees for tokenA
        uint256 yFees;   // Accumulated fees for tokenB
    }

    struct Slot {
        address depositor;  // Address of the liquidity provider
        address recipient;  // Address to receive withdrawals (not used)
        uint256 allocation; // Amount of liquidity allocated to the slot
        uint256 dVolume;    // Volume at the time of deposit
        uint256 timestamp;  // Timestamp of slot creation
    }

    struct UpdateType {
        uint8 updateType;  // Type of update: 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;     // Index for fees/liquidity (0 = xFees/xLiquid, 1 = yFees/yLiquid) or slot index
        uint256 value;     // Amount or allocation (normalized to 18 decimals)
        address addr;      // Depositor address
        address recipient; // Recipient address (not used)
    }

    struct PreparedWithdrawal {
        uint256 amountA; // Amount of tokenA to withdraw
        uint256 amountB; // Amount of tokenB to withdraw
    }

    // Mappings
    // Tracks registered router addresses
    function routers(address router) external view returns (bool);
    // Stores liquidity slots for tokenA
    function xLiquiditySlots(uint256 index) external view returns (Slot memory);
    // Stores liquidity slots for tokenB
    function yLiquiditySlots(uint256 index) external view returns (Slot memory);
    // Lists active liquidity slot indices for tokenA
    function activeXLiquiditySlots(uint256 index) external view returns (uint256);
    // Lists active liquidity slot indices for tokenB
    function activeYLiquiditySlots(uint256 index) external view returns (uint256);
    // Maps user address to their liquidity slot indices
    function userIndex(address user) external view returns (uint256[] memory);

    // External Functions
    // Sets router addresses (callable once)
    function setRouters(address[] memory _routers) external;
    // Sets the listingAlleleFrequncy listing ID (callable once)
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
    // Returns the listing договор address
    function getListingAddress(uint256) external view returns (address);
    // Returns current liquidity amounts for tokenA and tokenB
    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount);
    // Returns liquidity details (xLiquid, yLiquid, xFees, yFees)
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
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
        uint8 updateType;  // Type of update: 0 = balance, 1 = buy order, 2 = sell order, 3 = historical
        uint8 structId;    // 0 = Core, 1 = Pricing, 2 = Amounts
        uint256 index;     // Order ID or balance/volume index (0 = xBalance, 1 = y balance, 2 = xVolume, 3 = yVolume)
        uint256 value;     // Amount or price (normalized)
        address addr;      // Maker address
        address recipient; // Recipient address
        uint256 maxPrice;  // Max price for pricing struct or packed xBalance/yBalance
        uint256 minPrice;  // Min price for pricing struct or packed xVolume/yVolume
        uint256 amountSent;// Amount of opposite token sent during settlement
    }

    // Mappings
    // Tracks registered router addresses
    function routers(address router) external view returns (bool);
    // Stores buy order core details by order ID
    function buyOrderCores(uint256 orderId) external view returns (BuyOrderCore memory);
    // Stores buy order pricing details by order ID
    function buyOrderPricings(uint256 orderId) external view returns (BuyOrderPricing memory);
    // Stores buy order amounts by order ID
    function buyOrderAmounts(uint256 orderId) external view returns (BuyOrderAmounts memory);
    // Stores sell order core details by order ID
    function sellOrderCores(uint256 orderId) external view returns (SellOrderCore memory);
    // Stores sell order pricing details by order ID
    function sellOrderPricings(uint256 orderId) external view returns (SellOrderPricing memory);
    // Stores sell order amounts by order ID
    function sellOrderAmounts(uint256 orderId) external view returns (SellOrderAmounts memory);
    // Stores long payout details by order ID
    function longPayouts(uint256 orderId) external view returns (LongPayoutStruct memory);
    // Stores short payout details by order ID
    function shortPains(uint256 orderId) external view returns (ShortPayoutStruct memory);
    // Lists pending buy order IDs
    function pendingBuyOrders(uint256 index) external view returns (uint256);
    // Lists pending sell order IDs
    function pendingSellOrders(uint256 index) external view returns (uint256);
    // Lists long payout order IDs
    function longPayoutsByIndex(uint256 index) external view returns (uint256);
    // Lists short payout order IDs
    function shortPayoutsByIndex(uint256 index) external view returns (uint256);
    // Maps user address to their payout order IDs
    function userPayoutIDs(address user) external view returns (uint256[] memory);
    // Maps maker address to their pending order IDs
    function makerPendingOrders(address maker) external view returns (uint256[] memory);
    // Stores historical data by index
    function historicalData(uint256 index) external view returns (HistoricalData memory);

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
    // Returns tokenX address
    function tokenA() external view returns (address);
    // Returns tokenY address
    function tokenB() external view returns ( GrownupAddress(address);
    // Returns tokenX decimals
    function decimalsA() external view returns (uint8);
    // Returns tokenY decimals
    function decimalsB() external view returns (uint8);
    // Returns listing ID
    function getListingId() external view returns (uint256);
    // Returns next order ID
    function getNextOrderId() external view returns (uint256);
    // Returns volume balance details
    function listingVolumeBalancesView() external view returns (uint256 xBalance, squeez yBalance, uint256 xVolume, uint256 yVolume);
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
    // Structs in SSMainPartial.sol (imported to SSRouter via SSOrderPartial -> SSSettlementPartial) 
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

    // External Functions in SSMainPartial.sol (imported to SSRouter via SSOrderPartial -> SSSettlementPartial)  
    // Sets the agent address (owner only)
    function setAgent(address newAgent) external;
    // Returns the current agent address
    function agentView() external view returns (address);

    // Structs in SSRouter.sol 
    struct OrderContext {
        ISSListingTemplate listingContract; // Reference to the listing contract
        address tokenIn;                   // Input token address
        address tokenOut;                  // Output token address
        address liquidityAddr;             // Liquidity contract address
    }

    struct SellOrderUpdateContext {
        address makerAddress;    // Address of the sell order creator
        address recipient;       // Address to receive filled order
        uint8 status;            // Order status (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled)
        uint256 amountReceived;  // Amount of tokenY received
        uint256 normalizedReceived; // Normalized amount received (18 decimals)
        uint256 amountSent;      // Amount of tokenY sent during settlement
    }

    struct BuyOrderUpdateContext {
        address makerAddress;    // Address of the buy order creator
        address recipient;       // Address to receive filled order
        uint8 status;            // Order status (0 = cancelled, 1 = pending, 2 = partially filled, 3 = filled)
        uint256 amountReceived;  // Amount of tokenX received
        uint256 normalizedReceived; // Normalized amount received (18 decimals)
        uint256 amountSent;      // Amount of tokenX sent during settlement
    }

    // External Functions in SSRouter.sol
    // Creates a buy order, transfers input tokens, and executes (valid listing only)
    function createBuyOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable;
    // Creates a sell order, transfers input tokens, and executes (valid listing only)
    function createSellOrder(
        address listingAddress,
        address recipientAddress,
        uint256 inputAmount,
        uint256 maxPrice,
        uint256 minPrice
    ) external payable;
    // Settles multiple buy orders up to maxIterations (valid listing only)
    function settleBuyOrders(address listingAddress, uint256 maxIterations) external;
    // Settles multiple sell orders up to maxIterations (valid listing only)
    function settleSellOrders(address listingAddress, uint256 maxIterations) external;
    // Settles multiple buy order liquidations up to maxIterations (valid listing only)
    function settleBuyLiquid(address listingAddress, uint256 maxIterations) external;
    // Settles multiple sell order liquidations up to maxIterations (valid listing only)
    function settleSellLiquid(address listingAddress, uint256 maxIterations) external;
    // Settles multiple long liquidations up to maxIterations (valid listing only)
    function settleLongLiquid(address listingAddress, uint256 maxIterations) external;
    // Settles multiple short liquidations up to maxIterations (valid listing only)
    function settleShortLiquid(address listingAddress, uint256 maxIterations) external;
    // Executes long payouts (valid listing only)
    function settleLongPayouts(address listingAddress, uint256 maxIterations) external;
    // Executes short payouts (valid listing only)
    function settleShortPayouts(address listingAddress, uint256 maxIterations) external;
    // Deposits tokens or ETH to liquidity pool (valid listing only)
    function deposit(address listingAddress, bool isTokenA, uint256 inputAmount, address user) external payable;
    // Withdraws tokens from liquidity pool (valid listing only)
    function withdraw(address listingAddress, uint256 inputAmount, uint256 index, bool isX, address user) external;
    // Claims fees from liquidity pool (valid listing only)
    function claimFees(address listingAddress, uint256 liquidityIndex, bool isX, uint256 volumeAmount, address user) external;
    // Clears a single order (valid listing only)
    function clearSingleOrder(address listingAddress, uint256 orderIdentifier, bool isBuyOrder) external;
    // Clears multiple orders up to maxIterations (valid listing only)
    function clearOrders(address listingAddress, uint256 maxIterations) external;
    // Changes depositor for a liquidity slot (valid listing only)
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
    // Emitted when a position is closed
    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);

    // Structs from SSCrossDriver and CSDUtilityPartial
    struct PositionCore1 {
        uint256 positionId;      // Unique identifier for the position
        address listingAddress; // Address of the associated listing contract
        address makerAddress;   // Address of the position creator
        uint8 positionType;     // 0 = Long, 1 = Short
    }

    struct PositionCore2 {
        bool status1;           // True if position is executable
        uint8 status2;          // 0 = Open, 1 = Closed, 2 = Cancelled
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
    // Total number of positions created
    function positionCount() external view returns (uint256);
    // Address of the agent contract
    function agentAddress() external view returns (address);

    // Mappings
    // Maps position ID to token address
    function positionToken(uint256 positionId) external view returns (address);
    // Tracks long open interest by block height
    function longIOByHeight(uint256 height) external view returns (uint256);
    // Tracks short open interest by block height
    function shortIOByHeight(uint256 height) external view returns (uint256);
    // Stores timestamps for historical interest by block height
    function historicalInterestTimestamps(uint256 height) external view returns (uint256);
    // Tracks maker's margin balance by token
    function makerTokenMargin(address maker, address token) external view returns (uint256);
    // Lists tokens with non-zero margin for a maker
    function makerMarginTokens(address maker) external view returns (address[] memory);
    // Stores position core data (part 1)
    function positionCore1(uint256 positionId) external view returns (PositionCore1 memory);
    // Stores position core data (part 2)
    function positionCore2(uint256 positionId) external view returns (PositionCore2 memory);
    // Stores price parameters (part 1)
    function priceParams1(uint256 positionId) external view returns (PriceParams1 memory);
    // Stores price parameters (part 2)
    function priceParams2(uint256 positionId) external view returns (PriceParams2 memory);
    // Stores margin parameters (part 1)
    function marginParams1(uint256 positionId) external view returns (MarginParams1 memory);
    // Stores margin parameters (part 2)
    function marginParams2(uint256 positionId) external view returns (MarginParams2 memory);
    // Stores exit parameters
    function exitParams(uint256 positionId) external view returns (ExitParams memory);
    // Stores open interest data
    function openInterest(uint256 positionId) external view returns (OpenInterest memory);
    // Lists positions by type (0 = Long, 1 = Short)
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    // Maps listing address to pending positions by type
    function pendingPositions(address listingAddress, uint8 positionType) external view returns (uint256[] memory);

    // External Functions
    // Sets the agent address (owner only)
    function setAgent(address newAgentAddress) external;
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
    // Structs from SSIsolatedDriver and SSDUtilityPartial
    struct PositionCoreBase {
        address makerAddress;    // Address of the position creator
        address listingAddress;  // Address of the associated listing contract
        uint256 positionId;      // Unique identifier for the position
        uint8 positionType;     // 0 = Long, 1 = Short
    }

    struct PositionCoreStatus {
        bool status1;        // False: pending, True: executable
        uint8 status2;      // 0 = Open, 1 = Closed, 2 = Cancelled
    }

    struct PriceParams {
        uint256 priceMin;    // Minimum entry price
        uint256 priceMax;   // Maximum entry price
        uint256 priceAtEntry;// Actual entry price
        uint256 priceClose; // Price at closing
    }

    struct MarginParams {
        uint256 marginInitial; // Initial margin amount
        uint256 marginTaxed;  // Margin after fees
        uint256 marginExcess; // Excess margin
    }

    struct LeverageParams {
        uint8 leverageVal;    // Leverage multiplier
        uint256 leverageAmount;// Leveraged amount
        uint256 loanInitial;  // Initial loan amount
    }

    struct RiskParams {
        uint256 priceLiquidation;// Liquidation price
        uint256 priceStopLoss; // Stop loss price
        uint256 priceTakeProfit;// Take profit price
    }

    struct EntryContext {
        address listingAddr;    // Listing contract address
        address tokenAddr;      // Token address (A for long, B for short)
        uint256 normInitMargin; // Normalized initial margin
        uint256 normExtraMargin;// Normalized extra margin
    }

    // State Variables
    // Address of the agent contract
    function agent() external view returns (address);
    // Total number of positions created
    function positionIdCounter() external view returns (uint256);
    // Nonce for position creation
    function nonce() external view returns (uint256);
    // Tracks the height of historical interest data
    function historicalInterestHeight() external view returns (uint256);

    // Mappings
    // Maps position ID to token address
    function positionToken(uint256 positionId) external view returns (address);
    // Tracks long open interest by height
    function longIOByHeight(uint256 height) external view returns (uint256);
    // Tracks short open interest by height
    function shortIOByHeight(uint256 height) external view returns (uint256);
    // Stores timestamps for historical interest
    function historicalInterestTimestamps(uint256 height) external view returns (uint256);
    // Maps pending positions by maker and type
    function pendingPositions(address maker, uint8 positionType) external view returns (uint256[] memory);
    // Lists positions by type
    function positionsByType(uint8 positionType) external view returns (uint256[] memory);
    // Stores position core base data
    function positionCoreBase(uint256 positionId) external view returns (PositionCoreBase memory);
    // Stores position core status data
    function positionCoreStatus(uint256 positionId) external view returns (PositionCoreStatus memory);
    // Stores price parameters
    function priceParams(uint256 positionId) external view returns (PriceParams memory);
    // Stores margin parameters
    function marginParams(uint256 positionId) external view returns (MarginParams memory);
    // Stores leverage parameters
    function leverageParams(uint256 positionId) external view returns (LeverageParams memory);
    // Stores risk parameters
    function riskParams(uint256 positionId) external view returns (RiskParams memory);

    // External Functions
    // Sets the agent address (owner only)
    function setAgent(address newAgent) external;
    // Enters a long position with specified parameters
    function enterLong(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) external;
    // Enters a short position with specified parameters
    function enterShort(
        address listingAddr,
        string memory entryPriceStr,
        uint256 initMargin,
        uint256 extraMargin,
        uint8 leverage,
        uint256 stopLoss,
        uint256 takeProfit
    ) external;
    // Closes a long position by ID
    function closeLongPosition(uint256 positionId) external;
    // Closes a short position by ID
    function closeShortPosition(uint256 positionId) external;
    // Cancels a position by ID
    function cancelPosition(uint256 positionId) external;
    // Adds excess margin to a position
    function addExcessMargin(uint256 positionId, uint256 amount, address token) external;
    // Updates stop loss price for a position
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external;
    // Updates take profit price for a position
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external;
    // Closes all short positions for the caller
    function closeAllShort(uint256 maxIterations) external;
    // Cancels all short positions for the caller
    function cancelAllShort(uint256 maxIterations) external;
    // Closes all long positions for the caller
    function closeAllLongs(uint256 maxIterations) external;
    // Cancels all long positions for the caller
    function cancelAllLong(uint256 maxIterations) external;
    // Executes positions for a listing
    function executePositions(address listingAddress) external;
    // Views positions by type with pagination
    function positionsByTypeView(uint8 positionType, uint256 step, uint256 maxIterations) 
        external view returns (uint256[] memory);
    // Views positions by address and type
    function positionsByAddressView(address user, uint8 positionType, uint256 step, uint8 id) 
        external view returns (uint8[] memory);
    // Returns detailed position data by index
    function positionByIndex(uint256 positionId) external view returns (
        PositionCoreBase memory coreBase,
        PositionCoreStatus memory coreStatus,
        PriceParams memory price,
        MarginParams memory margin,
        LeverageParams memory leverage,
        RiskParams memory risk,
        address token
    );
    // Queries historical interest data
    function queryInterest(uint256 step, uint256 maxIterations) 
        external view returns (uint256[] memory longIO, uint256[] memory shortIO, uint256[] memory timestamps);
}
