I// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "imports/SafeERC20.sol";
import "imports/ReentrancyGuard.sol";
import "imports/Strings.sol";
import "imports/IERC20Metadata.sol";

// Interfaces based on SSListingTemplate.sol and SSLiquidityTemplate.sol
interface ISSListing {
    function prices(address listingAddress) external view returns (uint256);
    function volumeBalances(address listingAddress) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddresses(address listingAddress) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address listingAddress, PayoutUpdate[] calldata updates) external;
}

interface ISSLiquidity {
    function addFees(bool isX, uint256 amount) external;
    function liquidityDetails(address listingAddress) external view returns (uint256 xLiquid, uint256 yLiquid);
}

struct PayoutUpdate {
    address recipient;
    uint256 required;
    uint8 payoutType; // 0: Long (Token-1), 1: Short (Token-0)
}

contract SSIsolatedDriver is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Structs
    struct PositionDetails {
        address makerAddress;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType; // 0: Long, 1: Short
        bool status1; // false: pending, true: executable
        uint8 status2; // 0: open, 1: closed, 2: cancelled
        uint256 closePrice;
        uint256 priceAtEntry;
        uint256 positionId;
        address listingAddress;
    }

    struct HistoricalInterest {
        uint256 shortIO;
        uint256 longIO;
        uint256 timestamp;
    }

    struct CheckResult {
        uint256 positionId;
        bool updateStatus1;
        bool closePosition;
        uint256 payout;
    }

    // Mappings
    mapping(uint256 => PositionDetails) public positionDetails;
    mapping(address => uint256[]) public userPositions;
    mapping(uint8 => uint256[]) public positionsByType; // 0: Long, 1: Short
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions; // listingAddress -> type -> positionIds
    mapping(uint256 => HistoricalInterest) public historicalInterest;
    uint256 public positionCount;
    uint256 public historicalInterestHeight;
    address public agent;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Events
    event PositionCreated(uint256 indexed positionId, bool isLong);
    event PositionClosed(uint256 indexed positionId, uint256 payout);
    event PositionCancelled(uint256 indexed positionId);
    event PositionsExecuted(uint256 count, address listingAddress);
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice);
    event ExcessMarginAdded(uint256 indexed positionId, uint256 amount);
    event PositionsClosed(uint256 count);
    event PositionsCancelled(uint256 count);

    // Set agent
    function setAgent(address _agent) external {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
    }

    // Helper: Normalize amount based on token decimals
    function normalizeAmount(address token, uint256 amount) internal view returns (uint256) {
        if (token == address(0)) return amount; // Native ETH, assume 18 decimals
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals == 18) return amount;
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Helper: Parse entry price string
    function parseEntryPrice(string memory entryPrice, address listingAddress) internal view returns (uint256 minPrice, uint256 maxPrice) {
        // Strict validation: Only digits and optional comma
        bytes memory priceBytes = bytes(entryPrice);
        require(priceBytes.length > 0, "Empty price");
        for (uint256 i = 0; i < priceBytes.length; i++) {
            if (priceBytes[i] != ',' && (priceBytes[i] < '0' || priceBytes[i] > '9')) {
                revert("Invalid characters");
            }
        }

        // Check for comma
        bool isRange;
        for (uint256 i = 0; i < priceBytes.length; i++) {
            if (priceBytes[i] == ',') {
                isRange = true;
                break;
            }
        }

        if (!isRange) {
            // Single or market price
            uint256 price;
            if (keccak256(abi.encodePacked(entryPrice)) == keccak256(abi.encodePacked("0"))) {
                price = ISSListing(listingAddress).prices(listingAddress);
            } else {
                price = parseUint(entryPrice);
            }
            require(price > 0, "Invalid price");
            return (price, price);
        }

        // Range price
        (string memory minStr, string memory maxStr) = splitString(entryPrice, ",");
        minPrice = parseUint(minStr);
        maxPrice = parseUint(maxStr);
        require(minPrice > 0 && maxPrice > 0, "Invalid range");
        require(minPrice <= maxPrice, "Invalid range order");
        return (minPrice, maxPrice);
    }

    // Helper: Parse uint from string
    function parseUint(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] >= '0' && b[i] <= '9', "Invalid digit");
            result = result * 10 + (uint8(b[i]) - 48);
        }
        return result * DECIMAL_PRECISION; // Normalize to 18 decimals
    }

    // Helper: Split string at delimiter
    function splitString(string memory str, string memory delimiter) internal pure returns (string memory, string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory delimBytes = bytes(delimiter);
        require(delimBytes.length == 1, "Invalid delimiter");

        uint256 delimIndex;
        bool found;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimBytes[0]) {
                delimIndex = i;
                found = true;
                break;
            }
        }
        require(found, "Delimiter not found");

        bytes memory part1 = new bytes(delimIndex);
        bytes memory part2 = new bytes(strBytes.length - delimIndex - 1);
        for (uint256 i = 0; i < delimIndex; i++) {
            part1[i] = strBytes[i];
        }
        for (uint256 i = delimIndex + 1; i < strBytes.length; i++) {
            part2[i - delimIndex - 1] = strBytes[i];
        }
        return (string(part1), string(part2));
    }

    // Helper: Remove from array
    function removeFromArray(uint256[] storage array, uint256 index) internal {
        require(index < array.length, "Invalid index");
        array[index] = array[array.length - 1];
        array.pop();
    }

    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable nonReentrant {
        require(listingAddress != address(0), "Invalid listing");
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse price
        (uint256 minPrice, uint256 maxPrice) = parseEntryPrice(entryPrice, listingAddress);
        
        // Validate SL/TP
        if (stopLossPrice != 0) require(stopLossPrice < minPrice, "Invalid SL");
        if (takeProfitPrice != 0) require(takeProfitPrice > maxPrice, "Invalid TP");

        // Fetch tokens
        address token0 = ISSListing(listingAddress).tokenA();
        
        // Normalize margins
        uint256 normalizedInitialMargin = normalizeAmount(token0, initialMargin);
        uint256 normalizedExcessMargin = normalizeAmount(token0, excessMargin);

        // Transfer margin
        if (token0 == address(0)) {
            require(msg.value == initialMargin + excessMargin, "Incorrect ETH amount");
        } else {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), initialMargin + excessMargin);
        }

        // Calculate fee
        uint256 fee = (leverage - 1) * normalizedInitialMargin / 100;
        uint256 taxedMargin = normalizedInitialMargin - fee;

        // Update liquidity fees
        ISSLiquidity liquidity = ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(listingAddress));
        liquidity.addFees(true, fee);

        // Leverage calculations
        uint256 leverageAmount = normalizedInitialMargin * leverage;
        require(normalizedExcessMargin <= leverageAmount, "Excess margin too high");
        uint256 yLiquid = liquidity.liquidityDetails(listingAddress).yLiquid;
        require(leverageAmount <= yLiquid * (101 - leverage) / 100, "Leverage limit exceeded");

        // Create position
        uint256 positionId = positionCount++;
        PositionDetails storage pos = positionDetails[positionId];
        pos.makerAddress = msg.sender;
        pos.minPrice = minPrice;
        pos.maxPrice = maxPrice;
        pos.initialMargin = normalizedInitialMargin;
        pos.taxedMargin = taxedMargin;
        pos.excessMargin = normalizedExcessMargin;
        pos.leverage = leverage;
        pos.leverageAmount = leverageAmount;
        pos.initialLoan = leverageAmount * minPrice / DECIMAL_PRECISION; // Use minPrice for initial calc
        pos.liquidationPrice = minPrice - ((taxedMargin + normalizedExcessMargin) / leverageAmount);
        pos.stopLossPrice = stopLossPrice;
        pos.takeProfitPrice = takeProfitPrice;
        pos.positionType = 0;
        pos.status1 = (minPrice == maxPrice && minPrice == ISSListing(listingAddress).prices(listingAddress));
        pos.status2 = 0;
        pos.positionId = positionId;
        pos.listingAddress = listingAddress;

        // Update storage
        userPositions[msg.sender].push(positionId);
        positionsByType[0].push(positionId);
        if (!pos.status1) {
            pendingPositions[listingAddress][0].push(positionId);
        }

        // Update IO
        historicalInterest[historicalInterestHeight] = HistoricalInterest({
            shortIO: historicalInterest[historicalInterestHeight].shortIO,
            longIO: historicalInterest[historicalInterestHeight].longIO + taxedMargin + normalizedExcessMargin,
            timestamp: block.timestamp
        });
        historicalInterestHeight++;

        // Update listing balance
        (uint256 xBalance,) = ISSListing(listingAddress).volumeBalances(listingAddress);
        // Note: Assume external call to update xBalance (TBD: settleOrders not called here)

        emit PositionCreated(positionId, true);
        forceExecution(listingAddress);
    }

    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable nonReentrant {
        require(listingAddress != address(0), "Invalid listing");
        require(initialMargin > 0, "Invalid margin");
        require(leverage >= 2 && leverage <= 100, "Invalid leverage");

        // Parse price
        (uint256 minPrice, uint256 maxPrice) = parseEntryPrice(entryPrice, listingAddress);
        
        // Validate SL/TP
        if (stopLossPrice != 0) require(stopLossPrice > maxPrice, "Invalid SL");
        if (takeProfitPrice != 0) require(takeProfitPrice < minPrice, "Invalid TP");

        // Fetch tokens
        address token1 = ISSListing(listingAddress).tokenB();
        
        // Normalize margins
        uint256 normalizedInitialMargin = normalizeAmount(token1, initialMargin);
        uint256 normalizedExcessMargin = normalizeAmount(token1, excessMargin);

        // Transfer margin
        if (token1 == address(0)) {
            require(msg.value == initialMargin + excessMargin, "Invalid ETH amount");
        } else {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), initialMargin + excessMargin);
        }

        // Calculate fee
        uint256 fee = (leverage - 1) * normalizedInitialMargin / 100;
        uint256 taxedMargin = normalizedInitialMargin - fee;

        // Update liquidity fees
        ISSLiquidity liquidity = ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(listingAddress));
        liquidity.addFees(false, fee);

        // Leverage calculations
        uint256 leverageAmount = normalizedInitialMargin * leverage;
        require(normalizedExcessMargin <= leverageAmount, "Excess margin too high");
        uint256 yLiquid = liquidity.liquidityDetails(listingAddress).yLiquid;
        require(leverageAmount <= yLiquid * (101 - leverage) / 100, "Leverage limit exceeded");

        // Create position
        uint256 positionId = positionCount++;
        PositionDetails storage pos = positionDetails[positionId];
        pos.makerAddress = msg.sender;
        pos.minPrice = minPrice;
        pos.maxPrice = maxPrice;
        pos.initialMargin = normalizedInitialMargin;
        pos.taxedMargin = taxedMargin;
        pos.excessMargin = normalizedExcessMargin;
        pos.leverage = leverage;
        pos.leverageAmount = leverageAmount;
        pos.initialLoan = leverageAmount * DECIMAL_PRECISION / minPrice; // Use minPrice for initial calc
        pos.liquidationPrice = minPrice + ((taxedMargin + normalizedExcessMargin) / leverageAmount);
        pos.stopLossPrice = stopLossPrice;
        pos.takeProfitPrice = takeProfitPrice;
        pos.positionType = 1;
        pos.status1 = (minPrice == maxPrice && minPrice == ISSListing(listingAddress).prices(listingAddress));
        pos.status2 = 0;
        pos.positionId = positionId;
        pos.listingAddress = listingAddress;

        // Update storage
        userPositions[msg.sender].push(positionId);
        positionsByType[1].push(positionId);
        if (!pos.status1) {
            pendingPositions[listingAddress][1].push(positionId);
        }

        // Update IO
        historicalInterest[historicalInterestHeight] = HistoricalInterest({
            shortIO: historicalInterest[historicalInterestHeight].shortIO + taxedMargin + normalizedExcessMargin,
            longIO: historicalInterest[historicalInterestHeight].longIO,
            timestamp: block.timestamp
        });
        historicalInterestHeight++;

        // Update listing balance
        (, uint256 yBalance) = ISSListing(listingAddress).volumeBalances(listingAddress);
        // Note: Assume external call to update yBalance (TBD)

        emit PositionCreated(positionId, false);
        forceExecution(listingAddress);
    }

    function closeLongPosition(uint256 positionId) external nonReentrant {
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 0, "Not a long position");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        uint256 currentPrice = ISSListing(pos.listingAddress).prices(pos.listingAddress);
        uint256 payout = ((pos.taxedMargin + pos.excessMargin + pos.leverageAmount) * currentPrice / DECIMAL_PRECISION) - pos.initialLoan;
        if (payout > type(uint256).max / DECIMAL_PRECISION) payout = 0; // Prevent overflow

        // Create payout order
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: pos.makerAddress,
            required: payout,
            payoutType: 0 // Long: Token-1
        });
        ISSListing(pos.listingAddress).ssUpdate(pos.listingAddress, updates);

        // Update position
        pos.status2 = 1;
        pos.closePrice = currentPrice;
        pos.leverageAmount = 0;

        // Update IO
        historicalInterest[historicalInterestHeight] = HistoricalInterest({
            shortIO: historicalInterest[historicalInterestHeight].shortIO,
            longIO: historicalInterest[historicalInterestHeight].longIO - (pos.taxedMargin + pos.excessMargin),
            timestamp: block.timestamp
        });
        historicalInterestHeight++;

        // Remove from mappings
        for (uint256 i = 0; i < userPositions[msg.sender].length; i++) {
            if (userPositions[msg.sender][i] == positionId) {
                removeFromArray(userPositions[msg.sender], i);
                break;
            }
        }
        for (uint256 i = 0; i < positionsByType[0].length; i++) {
            if (positionsByType[0][i] == positionId) {
                removeFromArray(positionsByType[0], i);
                break;
            }
        }
        for (uint256 i = 0; i < pendingPositions[pos.listingAddress][0].length; i++) {
            if (pendingPositions[pos.listingAddress][0][i] == positionId) {
                removeFromArray(pendingPositions[pos.listingAddress][0], i);
                break;
            }
        }

        emit PositionClosed(positionId, payout);
        forceExecution(pos.listingAddress);
    }

    function closeShortPosition(uint256 positionId) external nonReentrant {
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 1, "Not a short position");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        uint256 currentPrice = ISSListing(pos.listingAddress).prices(pos.listingAddress);
        require(currentPrice > 0, "Invalid price");
        uint256 payout = ((pos.minPrice - currentPrice) * pos.initialMargin * pos.leverage / DECIMAL_PRECISION) +
                         ((pos.taxedMargin + pos.excessMargin) * DECIMAL_PRECISION / currentPrice);
        if (payout > type(uint256).max / DECIMAL_PRECISION) payout = 0;

        // Create payout order
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: pos.makerAddress,
            required: payout,
            payoutType: 1 // Short: Token-0
        });
        ISSListing(pos.listingAddress).ssUpdate(pos.listingAddress, updates);

        // Update position
        pos.status2 = 1;
        pos.closePrice = currentPrice;
        pos.leverageAmount = 0;

        // Update IO
        historicalInterest[historicalInterestHeight] = HistoricalInterest({
            shortIO: historicalInterest[historicalInterestHeight].shortIO - (pos.taxedMargin + pos.excessMargin),
            longIO: historicalInterest[historicalInterestHeight].longIO,
            timestamp: block.timestamp
        });
        historicalInterestHeight++;

        // Remove from mappings
        for (uint256 i = 0; i < userPositions[msg.sender].length; i++) {
            if (userPositions[msg.sender][i] == positionId) {
                removeFromArray(userPositions[msg.sender], i);
                break;
            }
        }
        for (uint256 i = 0; i < positionsByType[1].length; i++) {
            if (positionsByType[1][i] == positionId) {
                removeFromArray(positionsByType[1], i);
                break;
            }
        }
        for (uint256 i = 0; i < pendingPositions[pos.listingAddress][1].length; i++) {
            if (pendingPositions[pos.listingAddress][1][i] == positionId) {
                removeFromArray(pendingPositions[pos.listingAddress][1], i);
                break;
            }
        }

        emit PositionClosed(positionId, payout);
        forceExecution(pos.listingAddress);
    }

    function cancelPosition(uint256 positionId) external nonReentrant {
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.status1 == false, "Position executable");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        // Create refund order
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: pos.makerAddress,
            required: pos.taxedMargin,
            payoutType: pos.positionType // Long: Token-0, Short: Token-1
        });
        ISSListing(pos.listingAddress).ssUpdate(pos.listingAddress, updates);

        // Update position
        pos.status2 = 2;

        // Update IO
        historicalInterest[historicalInterestHeight] = HistoricalInterest({
            shortIO: pos.positionType == 1 ? historicalInterest[historicalInterestHeight].shortIO - (pos.taxedMargin + pos.excessMargin) : historicalInterest[historicalInterestHeight].shortIO,
            longIO: pos.positionType == 0 ? historicalInterest[historicalInterestHeight].longIO - (pos.taxedMargin + pos.excessMargin) : historicalInterest[historicalInterestHeight].longIO,
            timestamp: block.timestamp
        });
        historicalInterestHeight++;

        // Remove from mappings
        for (uint256 i = 0; i < userPositions[msg.sender].length; i++) {
            if (userPositions[msg.sender][i] == positionId) {
                removeFromArray(userPositions[msg.sender], i);
                break;
            }
        }
        for (uint256 i = 0; i < positionsByType[pos.positionType].length; i++) {
            if (positionsByType[pos.positionType][i] == positionId) {
                removeFromArray(positionsByType[pos.positionType], i);
                break;
            }
        }
        for (uint256 i = 0; i < pendingPositions[pos.listingAddress][pos.positionType].length; i++) {
            if (pendingPositions[pos.listingAddress][pos.positionType][i] == positionId) {
                removeFromArray(pendingPositions[pos.listingAddress][pos.positionType], i);
                break;
            }
        }

        emit PositionCancelled(positionId);
        forceExecution(pos.listingAddress);
    }

    function closeAllShort() external nonReentrant {
        uint256[] storage positions = userPositions[msg.sender];
        uint256 count = 0;
        for (uint256 i = positions.length; i > 0 && count < 100; i--) {
            uint256 positionId = positions[i - 1];
            PositionDetails storage pos = positionDetails[positionId];
            if (pos.positionType == 1 && pos.status2 == 0) {
                closeShortPosition(positionId);
                count++;
            }
        }
        emit PositionsClosed(count);
    }

    function cancelAllShort() external nonReentrant {
        uint256[] storage positions = userPositions[msg.sender];
        uint256 count = 0;
        for (uint256 i = positions.length; i > 0 && count < 100; i--) {
            uint256 positionId = positions[i - 1];
            PositionDetails storage pos = positionDetails[positionId];
            if (pos.positionType == 1 && pos.status1 == false && pos.status2 == 0) {
                cancelPosition(positionId);
                count++;
            }
        }
        emit PositionsCancelled(count);
    }

    function closeAllLongs() external nonReentrant {
        uint256[] storage positions = userPositions[msg.sender];
        uint256 count = 0;
        for (uint256 i = positions.length; i > 0 && count < 100; i--) {
            uint256 positionId = positions[i - 1];
            PositionDetails storage pos = positionDetails[positionId];
            if (pos.positionType == 0 && pos.status2 == 0) {
                closeLongPosition(positionId);
                count++;
            }
        }
        emit PositionsClosed(count);
    }

    function cancelAllLong() external nonReentrant {
        uint256[] storage positions = userPositions[msg.sender];
        uint256 count = 0;
        for (uint256 i = positions.length; i > 0 && count < 100; i--) {
            uint256 positionId = positions[i - 1];
            PositionDetails storage pos = positionDetails[positionId];
            if (pos.positionType == 0 && pos.status1 == false && pos.status2 == 0) {
                cancelPosition(positionId);
                count++;
            }
        }
        emit PositionsCancelled(count);
    }

    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.makerAddress == msg.sender, "Not position maker");
        require(pos.status2 == 0, "Position not open");

        uint256 currentPrice = ISSListing(pos.listingAddress).prices(pos.listingAddress);
        if (pos.positionType == 0) {
            require(newStopLossPrice == 0 || (newStopLossPrice <= currentPrice && newStopLossPrice < pos.minPrice), "Invalid SL");
        } else {
            require(newStopLossPrice == 0 || (newStopLossPrice >= currentPrice && newStopLossPrice > pos.maxPrice), "Invalid SL");
        }

        pos.stopLossPrice = newStopLossPrice;
        emit StopLossUpdated(positionId, newStopLossPrice);
    }

    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.makerAddress == msg.sender, "Not position maker");
        require(pos.status2 == 0, "Position not open");

        if (pos.positionType == 0) {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice >= pos.maxPrice, "Invalid TP");
        } else {
            require(newTakeProfitPrice == 0 || newTakeProfitPrice <= pos.minPrice, "Invalid TP");
        }

        pos.takeProfitPrice = newTakeProfitPrice;
        emit TakeProfitUpdated(positionId, newTakeProfitPrice);
    }

    function addExcessMargin(uint256 positionId, uint256 amount) external payable nonReentrant {
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.status2 == 0, "Position not open");
        require(amount > 0, "Invalid amount");

        address token = pos.positionType == 0 ? ISSListing(pos.listingAddress).tokenA() : ISSListing(pos.listingAddress).tokenB();
        uint256 normalizedAmount = normalizeAmount(token, amount);

        // Transfer
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update position
        pos.excessMargin += normalizedAmount;
        require(pos.excessMargin <= pos.leverageAmount, "Excess margin too high");

        // Update IO
        historicalInterest[historicalInterestHeight] = HistoricalInterest({
            shortIO: pos.positionType == 1 ? historicalInterest[historicalInterestHeight].shortIO + normalizedAmount : historicalInterest[historicalInterestHeight].shortIO,
            longIO: pos.positionType == 0 ? historicalInterest[historicalInterestHeight].longIO + normalizedAmount : historicalInterest[historicalInterestHeight].longIO,
            timestamp: block.timestamp
        });
        historicalInterestHeight++;

        // Update listing balance
        if (pos.positionType == 0) {
            // xBalance += normalizedAmount (TBD: external call)
        } else {
            // yBalance += normalizedAmount (TBD)
        }

        // Recalculate liquidation price
        pos.liquidationPrice = pos.positionType == 0 ?
            pos.minPrice - ((pos.taxedMargin + pos.excessMargin) / pos.leverageAmount) :
            pos.minPrice + ((pos.taxedMargin + pos.excessMargin) / pos.leverageAmount);

        emit ExcessMarginAdded(positionId, normalizedAmount);
        forceExecution(pos.listingAddress);
    }

    function PositionsByTypeView(uint8 positionType, uint256 step, uint16 maxIteration) external view returns (uint256[] memory) {
        require(positionType <= 1, "Invalid type");
        require(maxIteration <= 1000, "Max iteration exceeded");

        uint256[] storage positions = positionsByType[positionType];
        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > positions.length ? positions.length : start + maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = positions[i];
        }
        return result;
    }

    function PositionsByAddressView(address user, uint256 step, uint16 maxIteration) external view returns (uint256[] memory) {
        require(maxIteration <= 1000, "Max iteration exceeded");

        uint256[] storage positions = userPositions[user];
        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > positions.length ? positions.length : start + maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            if (positionDetails[positions[i]].status2 == 0) {
                result[i - start] = positions[i];
            }
        }
        return result;
    }

    function PositionByIndex(uint256 positionId) external view returns (PositionDetails memory) {
        require(positionId < positionCount, "Invalid position ID");
        return positionDetails[positionId];
    }

    function queryInterest(uint256 step, uint16 maxIteration) external view returns (HistoricalInterest[] memory) {
        require(maxIteration <= 1000, "Max iteration exceeded");

        uint256 start = step * maxIteration;
        uint256 end = start + maxIteration > historicalInterestHeight ? historicalInterestHeight : start + maxIteration;
        HistoricalInterest[] memory result = new HistoricalInterest[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = historicalInterest[i];
        }
        return result;
    }

    function forceExecution(address listingAddress) external nonReentrant {
        uint256 currentPrice = ISSListing(listingAddress).prices(listingAddress);
        CheckResult[] memory results = new CheckResult[](100);
        uint256 resultCount = 0;

        // Check pending entries
        resultCount = checkPending(listingAddress, currentPrice, results, resultCount);

        // Check stop loss
        resultCount = checkStopLoss(listingAddress, currentPrice, results, resultCount);

        // Check take profit
        resultCount = checkTakeProfit(listingAddress, currentPrice, results, resultCount);

        // Check liquidations
        resultCount = checkLiquidation(listingAddress, currentPrice, results, resultCount);

        // Execute results
        PayoutUpdate[] memory updates = new PayoutUpdate[](resultCount);
        uint256 updateIndex = 0;
        for (uint256 i = 0; i < resultCount; i++) {
            PositionDetails storage pos = positionDetails[results[i].positionId];
            if (results[i].updateStatus1) {
                pos.status1 = true;
                pos.priceAtEntry = currentPrice;
                pos.initialLoan = pos.positionType == 0 ?
                    pos.leverageAmount * currentPrice / DECIMAL_PRECISION :
                    pos.leverageAmount * DECIMAL_PRECISION / currentPrice;
                pos.liquidationPrice = pos.positionType == 0 ?
                    currentPrice - ((pos.taxedMargin + pos.excessMargin) / pos.leverageAmount) :
                    currentPrice + ((pos.taxedMargin + pos.excessMargin) / pos.leverageAmount);

                for (uint256 j = 0; j < pendingPositions[listingAddress][pos.positionType].length; j++) {
                    if (pendingPositions[listingAddress][pos.positionType][j] == pos.positionId) {
                        removeFromArray(pendingPositions[listingAddress][pos.positionType], j);
                        break;
                    }
                }
            }
            if (results[i].closePosition) {
                pos.status2 = 1;
                pos.closePrice = currentPrice;
                pos.leverageAmount = 0;

                updates[updateIndex] = PayoutUpdate({
                    recipient: pos.makerAddress,
                    required: results[i].payout,
                    payoutType: pos.positionType
                });
                updateIndex++;

                // Update IO
                historicalInterest[historicalInterestHeight] = HistoricalInterest({
                    shortIO: pos.positionType == 1 ? historicalInterest[historicalInterestHeight].shortIO - (pos.taxedMargin + pos.excessMargin) : historicalInterest[historicalInterestHeight].shortIO,
                    longIO: pos.positionType == 0 ? historicalInterest[historicalInterestHeight].longIO - (pos.taxedMargin + pos.excessMargin) : historicalInterest[historicalInterestHeight].longIO,
                    timestamp: block.timestamp
                });
                historicalInterestHeight++;

                // Remove from mappings
                for (uint256 j = 0; j < userPositions[pos.makerAddress].length; j++) {
                    if (userPositions[pos.makerAddress][j] == pos.positionId) {
                        removeFromArray(userPositions[pos.makerAddress], j);
                        break;
                    }
                }
                for (uint256 j = 0; j < positionsByType[pos.positionType].length; j++) {
                    if (positionsByType[pos.positionType][j] == pos.positionId) {
                        removeFromArray(positionsByType[pos.positionType], j);
                        break;
                    }
                }
            }
        }

        if (updateIndex > 0) {
            ISSListing(listingAddress).ssUpdate(listingAddress, updates);
        }

        emit PositionsExecuted(resultCount, listingAddress);
    }

    // Helper: Check pending entries
    function checkPending(address listingAddress, uint256 currentPrice, CheckResult[] memory results, uint256 resultCount) internal view returns (uint256) {
        for (uint8 type_ = 0; type_ <= 1 && resultCount < 100; type_++) {
            uint256[] storage pending = pendingPositions[listingAddress][type_];
            for (uint256 i = 0; i < pending.length && resultCount < 100; i++) {
                PositionDetails storage pos = positionDetails[pending[i]];
                if (pos.status1 == false && pos.status2 == 0 && pos.minPrice <= currentPrice && currentPrice <= pos.maxPrice) {
                    results[resultCount] = CheckResult({
                        positionId: pos.positionId,
                        updateStatus1: true,
                        closePosition: false,
                        payout: 0
                    });
                    resultCount++;
                }
            }
        }
        return resultCount;
    }

    // Helper: Check stop loss
    function checkStopLoss(address listingAddress, uint256 currentPrice, CheckResult[] memory results, uint256 resultCount) internal view returns (uint256) {
        for (uint8 type_ = 0; type_ <= 1 && resultCount < 100; type_++) {
            uint256[] storage positions = positionsByType[type_];
            for (uint256 i = 0; i < positions.length && resultCount < 100; i++) {
                PositionDetails storage pos = positionDetails[positions[i]];
                if (pos.listingAddress == listingAddress && pos.status2 == 0 && pos.stopLossPrice != 0) {
                    bool trigger = (type_ == 0 && currentPrice <= pos.stopLossPrice) ||
                                   (type_ == 1 && currentPrice >= pos.stopLossPrice);
                    if (trigger) {
                        uint256 payout = type_ == 0 ?
                            ((pos.taxedMargin + pos.excessMargin + pos.leverageAmount) * currentPrice / DECIMAL_PRECISION) - pos.initialLoan :
                            ((pos.minPrice - currentPrice) * pos.initialMargin * pos.leverage / DECIMAL_PRECISION) + ((pos.taxedMargin + pos.excessMargin) * DECIMAL_PRECISION / currentPrice);
                        if (payout > type(uint256).max / DECIMAL_PRECISION) payout = 0;
                        results[resultCount] = CheckResult({
                            positionId: pos.positionId,
                            updateStatus1: false,
                            closePosition: true,
                            payout: payout
                        });
                        resultCount++;
                    }
                }
            }
        }
        return resultCount;
    }

    // Helper: Check take profit
    function checkTakeProfit(address listingAddress, uint256 currentPrice, CheckResult[] memory results, uint256 resultCount) internal view returns (uint256) {
        for (uint8 type_ = 0; type_ <= 1 && resultCount < 100; type_++) {
            uint256[] storage positions = positionsByType[type_];
            for (uint256 i = 0; i < positions.length && resultCount < 100; i++) {
                PositionDetails storage pos = positionDetails[positions[i]];
                if (pos.listingAddress == listingAddress && pos.status2 == 0 && pos.takeProfitPrice != 0) {
                    bool trigger = (type_ == 0 && currentPrice >= pos.takeProfitPrice) ||
                                   (type_ == 1 && currentPrice <= pos.takeProfitPrice);
                    if (trigger) {
                        uint256 payout = type_ == 0 ?
                            ((pos.taxedMargin + pos.excessMargin + pos.leverageAmount) * currentPrice / DECIMAL_PRECISION) - pos.initialLoan :
                            ((pos.minPrice - currentPrice) * pos.initialMargin * pos.leverage / DECIMAL_PRECISION) + ((pos.taxedMargin + pos.excessMargin) * DECIMAL_PRECISION / currentPrice);
                        if (payout > type(uint256).max / DECIMAL_PRECISION) payout = 0;
                        results[resultCount] = CheckResult({
                            positionId: pos.positionId,
                            updateStatus1: false,
                            closePosition: true,
                            payout: payout
                        });
                        resultCount++;
                    }
                }
            }
        }
        return resultCount;
    }

    // Helper: Check liquidations
    function checkLiquidation(address listingAddress, uint256 currentPrice, CheckResult[] memory results, uint256 resultCount) internal view returns (uint256) {
        for (uint8 type_ = 0; type_ <= 1 && resultCount < 100; type_++) {
            uint256[] storage positions = positionsByType[type_];
            for (uint256 i = 0; i < positions.length && resultCount < 100; i++) {
                PositionDetails storage pos = positionDetails[positions[i]];
                if (pos.listingAddress == listingAddress && pos.status2 == 0) {
                    bool trigger = (type_ == 0 && currentPrice <= pos.liquidationPrice) ||
                                   (type_ == 1 && currentPrice >= pos.liquidationPrice);
                    if (trigger) {
                        results[resultCount] = CheckResult({
                            positionId: pos.positionId,
                            updateStatus1: false,
                            closePosition: true,
                            payout: 0 // Liquidation: no payout
                        });
                        resultCount++;
                    }
                }
            }
        }
        return resultCount;
    }
}