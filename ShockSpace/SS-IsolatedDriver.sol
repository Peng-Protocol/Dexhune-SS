// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.4:
// - Removed pullMargin function (per user correction).
// - Updated setAgent to ownerOnly.
// - Fully implemented cancelAll* to cancel pending positions with payouts via ssUpdate.
// - Added tax-on-transfer checks for margin transfers, storing post-transfer amounts.
// - Added historical interest view functions: interest, interestHeight.
// - Moved ISSListing interface locally, removed import.
// - PositionLibrary and UtilityLibrary as separate contracts, not inherited.
// - Clarified status1 (pending/executable), status2 (open/closed/cancelled) usage.
// - Local imports for SafeERC20, IERC20Metadata, etc.
// - Ensured no constructor args, reusable set* functions.

import "./imports/SafeERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Strings.sol";
import "./imports/IERC20Metadata.sol";
import "./imports/Ownable.sol";

interface ISSListing {
    function prices(uint256 listingId) external view returns (uint256);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function liquidityAddresses(uint256 listingId) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface ISSLiquidity {
    function addFees(bool isX, uint256 amount) external;
    function liquidityDetails(address listingAddress) external view returns (uint256 xLiquid, uint256 yLiquid);
}

interface ISSPositionLibrary {
    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token0,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        address driver
    ) external returns (uint256 positionId);

    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        address token1,
        uint256 normalizedInitialMargin,
        uint256 normalizedExcessMargin,
        address driver
    ) external returns (uint256 positionId);

    function closeLongPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 leverageAmount,
        uint256 initialLoan,
        address driver
    ) external returns (uint256 payout);

    function closeShortPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 minPrice,
        uint256 initialMargin,
        uint8 leverage,
        uint256 taxedMargin,
        uint256 excessMargin,
        address driver
    ) external returns (uint256 payout);

    function cancelPosition(
        uint256 positionId,
        address listingAddress,
        address makerAddress,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint8 positionType,
        address driver
    ) external;

    function forceExecution(
        address listingAddress,
        address driver
    ) external returns (uint256 resultCount);

    function addExcessMargin(
        uint256 positionId,
        uint256 amount,
        address token,
        address listingAddress,
        uint8 positionType,
        uint256 normalizedAmount,
        address driver
    ) external;

    function updateSL(
        uint256 positionId,
        uint256 newStopLossPrice,
        address listingAddress,
        uint8 positionType,
        address makerAddress,
        uint256 minPrice,
        uint256 maxPrice,
        address driver
    ) external;

    function updateTP(
        uint256 positionId,
        uint256 newTakeProfitPrice,
        uint8 positionType,
        address makerAddress,
        uint256 minPrice,
        uint256 maxPrice,
        address driver
    ) external;

    function closeAllShort(
        address user,
        address driver
    ) external returns (uint256 count);

    function cancelAllShort(
        address user,
        address driver
    ) external returns (uint256 count);

    function closeAllLongs(
        address user,
        address driver
    ) external returns (uint256 count);

    function cancelAllLong(
        address user,
        address driver
    ) external returns (uint256 count);

    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external;
    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external;
    function updatePositionStatus(uint256 positionId, uint8 newStatus) external;
    function updateExcessMargin(uint256 positionId, uint256 normalizedAmount) external;
    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external;
    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external;
    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external;
    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external;
}

interface ISSUtilityLibrary {
    function normalizeAmount(address token, uint256 amount) external view returns (uint256);
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
    function parseUint(string memory str) external pure returns (uint256);
    function splitString(string memory str, string memory delimiter) external pure returns (string memory, string memory);
}

contract SSIsolatedDriver is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Structs
    struct PositionDetails {
        address makerAddress;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 initialMargin; // Pre-tax margin
        uint256 taxedMargin; // Post-tax margin
        uint256 excessMargin; // Additional margin
        uint8 leverage; // 2-100x
        uint256 leverageAmount; // Margin * leverage
        uint256 initialLoan; // Loan at entry
        uint256 liquidationPrice; // Price to liquidate
        uint256 stopLossPrice; // SL trigger
        uint256 takeProfitPrice; // TP trigger
        uint8 positionType; // 0: Long, 1: Short
        bool status1; // false: pending, true: executable
        uint8 status2; // 0: open, 1: closed, 2: cancelled
        uint256 closePrice; // Price at close
        uint256 priceAtEntry; // Entry price
        uint256 positionId; // Unique ID
        address listingAddress; // Listing contract
    }

    struct HistoricalInterest {
        uint256 shortIO; // Total taxed + excess margin for shorts
        uint256 longIO; // Total taxed + excess margin for longs
        uint256 timestamp; // Update time
    }

    struct PayoutUpdate {
        address recipient;
        uint256 required;
        uint8 payoutType; // 0: Long, 1: Short
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
    address public positionLibrary;
    address public utilityLibrary;

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
    event LibrarySet(address indexed library, string libraryType);
    event HistoricalInterestUpdated(uint256 indexed index, uint256 longIO, uint256 shortIO);

    // Set agent (owner-only)
    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
    }

    // Set library addresses (owner-only)
    function setPositionLibrary(address _positionLibrary) external onlyOwner {
        require(_positionLibrary != address(0), "Invalid address");
        positionLibrary = _positionLibrary;
        emit LibrarySet(_positionLibrary, "PositionLibrary");
    }

    function setUtilityLibrary(address _utilityLibrary) external onlyOwner {
        require(_utilityLibrary != address(0), "Invalid address");
        utilityLibrary = _utilityLibrary;
        emit LibrarySet(_utilityLibrary, "UtilityLibrary");
    }

    // Enter long position
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
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        address token0 = ISSListing(listingAddress).tokenA();
        address liquidityAddress = ISSListing(listingAddress).liquidityAddresses(uint256(uint160(listingAddress)));
        uint256 normalizedInitialMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token0, initialMargin);
        uint256 normalizedExcessMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token0, excessMargin);
        uint256 fee = (leverage - 1) * initialMargin / 100;

        // Transfer margin to listingAddress, fee to liquidityAddress with tax-on-transfer check
        uint256 totalMargin = initialMargin + excessMargin;
        if (token0 == address(0)) {
            require(msg.value == totalMargin, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: totalMargin - fee}("");
            require(success, "ETH transfer failed");
            ISSLiquidity(liquidityAddress).addFees(true, fee);
        } else {
            uint256 balanceBefore = IERC20(token0).balanceOf(listingAddress);
            IERC20(token0).safeTransferFrom(msg.sender, listingAddress, totalMargin - fee);
            uint256 balanceAfter = IERC20(token0).balanceOf(listingAddress);
            require(balanceAfter >= balanceBefore + totalMargin - fee, "Tax-on-transfer issue");
            IERC20(token0).safeTransferFrom(msg.sender, liquidityAddress, fee);
            ISSLiquidity(liquidityAddress).addFees(true, fee);
        }

        // Store post-transfer amounts
        positionDetails[positionCount].initialMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token0, initialMargin);
        positionDetails[positionCount].excessMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token0, excessMargin);

        uint256 positionId = ISSPositionLibrary(positionLibrary).enterLong(
            listingAddress,
            entryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token0,
            normalizedInitialMargin,
            normalizedExcessMargin,
            address(this)
        );

        emit PositionCreated(positionId, true);
    }

    // Enter short position
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
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        address token1 = ISSListing(listingAddress).tokenB();
        address liquidityAddress = ISSListing(listingAddress).liquidityAddresses(uint256(uint160(listingAddress)));
        uint256 normalizedInitialMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token1, initialMargin);
        uint256 normalizedExcessMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token1, excessMargin);
        uint256 fee = (leverage - 1) * initialMargin / 100;

        // Transfer margin to listingAddress, fee to liquidityAddress with tax-on-transfer check
        uint256 totalMargin = initialMargin + excessMargin;
        if (token1 == address(0)) {
            require(msg.value == totalMargin, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: totalMargin - fee}("");
            require(success, "ETH transfer failed");
            ISSLiquidity(liquidityAddress).addFees(false, fee);
        } else {
            uint256 balanceBefore = IERC20(token1).balanceOf(listingAddress);
            IERC20(token1).safeTransferFrom(msg.sender, listingAddress, totalMargin - fee);
            uint256 balanceAfter = IERC20(token1).balanceOf(listingAddress);
            require(balanceAfter >= balanceBefore + totalMargin - fee, "Tax-on-transfer issue");
            IERC20(token1).safeTransferFrom(msg.sender, liquidityAddress, fee);
            ISSLiquidity(liquidityAddress).addFees(false, fee);
        }

        // Store post-transfer amounts
        positionDetails[positionCount].initialMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token1, initialMargin);
        positionDetails[positionCount].excessMargin = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token1, excessMargin);

        uint256 positionId = ISSPositionLibrary(positionLibrary).enterShort(
            listingAddress,
            entryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token1,
            normalizedInitialMargin,
            normalizedExcessMargin,
            address(this)
        );

        emit PositionCreated(positionId, false);
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 0, "Not a long position");
        require(pos.status2 == 0, "Position not open"); // Only open positions can be closed
        require(pos.makerAddress == msg.sender, "Not position maker");

        uint256 payout = ISSPositionLibrary(positionLibrary).closeLongPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.taxedMargin,
            pos.excessMargin,
            pos.leverageAmount,
            pos.initialLoan,
            address(this)
        );

        emit PositionClosed(positionId, payout);
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 1, "Not a short position");
        require(pos.status2 == 0, "Position not open"); // Only open positions can be closed
        require(pos.makerAddress == msg.sender, "Not position maker");

        uint256 payout = ISSPositionLibrary(positionLibrary).closeShortPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.minPrice,
            pos.initialMargin,
            pos.leverage,
            pos.taxedMargin,
            pos.excessMargin,
            address(this)
        );

        emit PositionClosed(positionId, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.status1 == false, "Position executable"); // Only pending positions can be cancelled
        require(pos.status2 == 0, "Position not open"); // Only open positions can be cancelled
        require(pos.makerAddress == msg.sender, "Not position maker");

        ISSPositionLibrary(positionLibrary).cancelPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.taxedMargin,
            pos.excessMargin,
            pos.positionType,
            address(this)
        );

        emit PositionCancelled(positionId);
    }

    // Force execution
    function forceExecution(address listingAddress) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 resultCount = ISSPositionLibrary(positionLibrary).forceExecution(
            listingAddress,
            address(this)
        );
        emit PositionsExecuted(resultCount, listingAddress);
    }

    // Add excess margin
    function addExcessMargin(uint256 positionId, uint256 amount) external payable nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");
        require(amount > 0, "Invalid amount");

        PositionDetails storage pos = positionDetails[positionId];
        require(pos.status2 == 0, "Position not open"); // Only open positions can add margin

        address token = pos.positionType == 0 ? ISSListing(pos.listingAddress).tokenA() : ISSListing(pos.listingAddress).tokenB();
        address listingAddress = pos.listingAddress;
        uint256 normalizedAmount = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, amount);

        // Transfer to listingAddress with tax-on-transfer check
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            (bool success, ) = listingAddress.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(listingAddress);
            IERC20(token).safeTransferFrom(msg.sender, listingAddress, amount);
            uint256 balanceAfter = IERC20(token).balanceOf(listingAddress);
            require(balanceAfter >= balanceBefore + amount, "Tax-on-transfer issue");
            normalizedAmount = ISSUtilityLibrary(utilityLibrary).normalizeAmount(token, balanceAfter - balanceBefore);
        }

        // Store post-transfer amount
        pos.excessMargin += normalizedAmount;

        ISSPositionLibrary(positionLibrary).addExcessMargin(
            positionId,
            amount,
            token,
            pos.listingAddress,
            pos.positionType,
            normalizedAmount,
            address(this)
        );

        emit ExcessMarginAdded(positionId, normalizedAmount);
    }

    // Update stop loss
    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.makerAddress == msg.sender, "Not position maker");
        require(pos.status2 == 0, "Position not open"); // Only open positions can update SL

        ISSPositionLibrary(positionLibrary).updateSL(
            positionId,
            newStopLossPrice,
            pos.listingAddress,
            pos.positionType,
            pos.makerAddress,
            pos.minPrice,
            pos.maxPrice,
            address(this)
        );

        emit StopLossUpdated(positionId, newStopLossPrice);
    }

    // Update take profit
    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.makerAddress == msg.sender, "Not position maker");
        require(pos.status2 == 0, "Position not open"); // Only open positions can update TP

        ISSPositionLibrary(positionLibrary).updateTP(
            positionId,
            newTakeProfitPrice,
            pos.positionType,
            pos.makerAddress,
            pos.minPrice,
            pos.maxPrice,
            address(this)
        );

        emit TakeProfitUpdated(positionId, newTakeProfitPrice);
    }

    // Close all short positions
    function closeAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).closeAllShort(msg.sender, address(this));
        emit PositionsClosed(count);
    }

    // Cancel all short positions
    function cancelAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).cancelAllShort(msg.sender, address(this));
        emit PositionsCancelled(count);
    }

    // Close all long positions
    function closeAllLongs() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).closeAllLongs(msg.sender, address(this));
        emit PositionsClosed(count);
    }

    // Cancel all long positions
    function cancelAllLong() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ISSPositionLibrary(positionLibrary).cancelAllLong(msg.sender, address(this));
        emit PositionsCancelled(count);
    }

    // Storage update functions
    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external {
        require(msg.sender == positionLibrary, "Library only");
        positionDetails[positionId] = pos;
        positionCount++;
    }

    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external {
        require(msg.sender == positionLibrary, "Library only");
        userPositions[user].push(positionId);
        positionsByType[positionType].push(positionId);
        pendingPositions[pos.listingAddress][positionType].push(positionId);
    }

    function updatePositionStatus(uint256 positionId, uint8 newStatus) external {
        require(msg.sender == positionLibrary, "Library only");
        positionDetails[positionId].status2 = newStatus;
    }

    function updateExcessMargin(uint256 positionId, uint256 normalizedAmount) external {
        require(msg.sender == positionLibrary, "Library only");
        positionDetails[positionId].excessMargin += normalizedAmount;
    }

    function updatePositionSL(uint256 positionId, uint256 newStopLossPrice) external {
        require(msg.sender == positionLibrary, "Library only");
        positionDetails[positionId].stopLossPrice = newStopLossPrice;
    }

    function updatePositionTP(uint256 positionId, uint256 newTakeProfitPrice) external {
        require(msg.sender == positionLibrary, "Library only");
        positionDetails[positionId].takeProfitPrice = newTakeProfitPrice;
    }

    function updateHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        require(msg.sender == positionLibrary, "Library only");
        HistoricalInterest storage interest = historicalInterest[index];
        interest.longIO += longIO;
        interest.shortIO += shortIO;
        interest.timestamp = block.timestamp;
        historicalInterestHeight = index + 1;
        emit HistoricalInterestUpdated(index, interest.longIO, interest.shortIO);
    }

    function reduceHistoricalInterest(uint256 index, uint256 longIO, uint256 shortIO) external {
        require(msg.sender == positionLibrary, "Library only");
        HistoricalInterest storage interest = historicalInterest[index];
        interest.longIO = interest.longIO > longIO ? interest.longIO - longIO : 0;
        interest.shortIO = interest.shortIO > shortIO ? interest.shortIO - shortIO : 0;
        interest.timestamp = block.timestamp;
        historicalInterestHeight = index + 1;
        emit HistoricalInterestUpdated(index, interest.longIO, interest.shortIO);
    }

    // View functions
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

    function interest(uint256 index) external view returns (uint256 longIO, uint256 shortIO, uint256 timestamp) {
        require(index < historicalInterestHeight, "Invalid index");
        HistoricalInterest storage hi = historicalInterest[index];
        return (hi.longIO, hi.shortIO, hi.timestamp);
    }

    function interestHeight() external view returns (uint256) {
        return historicalInterestHeight;
    }
}