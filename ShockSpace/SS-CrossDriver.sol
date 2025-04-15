// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.1:
// - Cloned from SSIsolatedDriver, acts as a proxy contract delegating to CSDPositionLibrary and CSDUtilityLibrary.
// - Adds makerTokenMargin for token-wide totalMargin, single index per maker and token.
// - Immediate totalMargin updates for addExcessMargin, enterLong, enterShort, pullMargin, closures, cancellations, liquidations.
// - New functions: makerTokenMarginView, makerMarginIndex (view), pullMargin.
// - Modified: enterLong, enterShort, closeLongPosition, closeShortPosition, addExcessMargin, forceExecution.
// - Corrected liquidation price calculations for enterLong and enterShort.
// - Includes local interfaces, no library imports in libraries.
// - Size: ~235 lines, minimal footprint.
// - Handles storage, validation, and library calls.

import "imports/SafeERC20.sol";
import "imports/ReentrancyGuard.sol";
import "imports/Strings.sol";
import "imports/IERC20Metadata.sol";
import "imports/Ownable.sol";

contract SSCrossDriver is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Structs
    struct PositionDetails {
        address makerAddress;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin; // Reference only, not used in calculations; stores margin for deductions
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

    struct PayoutUpdate {
        address recipient;
        uint256 required;
        uint8 payoutType;
    }

    // Interfaces
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

    interface ICSDPositionLibrary {
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
            uint256 totalMargin,
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
            uint256 totalMargin,
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
            uint256 totalMargin,
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
            uint256 totalMargin,
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
            address maker,
            uint256 amount,
            address token,
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
    }

    interface ICSDUtilityLibrary {
        function normalizeAmount(address token, uint256 amount) external view returns (uint256);
        function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice);
        function parseUint(string memory str) external pure returns (uint256);
        function splitString(string memory str, string memory delimiter) external pure returns (string memory, string memory);
    }

    // Mappings
    mapping(uint256 => PositionDetails) public positionDetails;
    mapping(address => uint256[]) public userPositions;
    mapping(uint8 => uint256[]) public positionsByType; // 0: Long, 1: Short
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions; // listingAddress -> type -> positionIds
    mapping(address => mapping(address => uint256)) public makerTokenMargin; // maker => token => totalMargin
    mapping(address => address[]) public makerMarginTokens; // maker => token[] (tracks non-zero margins)
    mapping(uint256 => HistoricalInterest) public historicalInterest;
    uint256 public positionCount;
    uint256 public historicalInterestHeight;
    address public agent;

    // Library addresses
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
    event ExcessMarginAdded(address indexed maker, uint256 amount, address token);
    event MarginPulled(address indexed maker, uint256 amount, address token);
    event PositionsClosed(uint256 count);
    event PositionsCancelled(uint256 count);
    event LibrarySet(address indexed library, string libraryType);

    // Modifiers
    modifier onlyAgent() {
        require(msg.sender == agent, "Only agent");
        _;
    }

    // Constructor
    constructor(address _positionLibrary, address _utilityLibrary) {
        positionLibrary = _positionLibrary;
        utilityLibrary = _utilityLibrary;
        emit LibrarySet(_positionLibrary, "PositionLibrary");
        emit LibrarySet(_utilityLibrary, "UtilityLibrary");
    }

    // Set agent
    function setAgent(address _agent) external onlyAgent {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
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
        require(excessMargin <= initialMargin * leverage, "Excess margin too high");
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        // Fetch token
        address token0 = ISSListing(listingAddress).tokenA();

        // Normalize margins
        uint256 normalizedInitialMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token0, initialMargin);
        uint256 normalizedExcessMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token0, excessMargin);

        // Transfer margin
        if (token0 == address(0)) {
            require(msg.value == initialMargin + excessMargin, "Incorrect ETH amount");
        } else {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), initialMargin + excessMargin);
        }

        // Update totalMargin immediately
        uint256 totalMargin = makerTokenMargin[msg.sender][token0];
        makerTokenMargin[msg.sender][token0] += initialMargin + excessMargin;
        if (totalMargin == 0) {
            makerMarginTokens[msg.sender].push(token0);
        }

        // Delegate to CSDPositionLibrary with totalMargin for liquidation price
        uint256 positionId = ICSDPositionLibrary(positionLibrary).enterLong(
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
            makerTokenMargin[msg.sender][token0],
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
        require(excessMargin <= initialMargin * leverage, "Excess margin too high");
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        // Fetch token
        address token1 = ISSListing(listingAddress).tokenB();

        // Normalize margins
        uint256 normalizedInitialMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token1, initialMargin);
        uint256 normalizedExcessMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token1, excessMargin);

        // Transfer margin
        if (token1 == address(0)) {
            require(msg.value == initialMargin + excessMargin, "Incorrect ETH amount");
        } else {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), initialMargin + excessMargin);
        }

        // Update totalMargin immediately
        uint256 totalMargin = makerTokenMargin[msg.sender][token1];
        makerTokenMargin[msg.sender][token1] += initialMargin + excessMargin;
        if (totalMargin == 0) {
            makerMarginTokens[msg.sender].push(token1);
        }

        // Delegate to CSDPositionLibrary with totalMargin for liquidation price
        uint256 positionId = ICSDPositionLibrary(positionLibrary).enterShort(
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
            makerTokenMargin[msg.sender][token1],
            address(this)
        );

        emit PositionCreated(positionId, false);
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 0, "Not a long position");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        // Delegate to CSDPositionLibrary
        uint256 payout = ICSDPositionLibrary(positionLibrary).closeLongPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.taxedMargin,
            pos.excessMargin,
            pos.leverageAmount,
            pos.initialLoan,
            makerTokenMargin[pos.makerAddress][ISSListing(pos.listingAddress).tokenA()],
            address(this)
        );

        // Deduct margin immediately
        address token = ISSListing(pos.listingAddress).tokenA();
        makerTokenMargin[pos.makerAddress][token] -= (pos.taxedMargin + pos.excessMargin);
        if (makerTokenMargin[pos.makerAddress][token] == 0) {
            _removeToken(pos.makerAddress, token);
        }

        emit PositionClosed(positionId, payout);
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 1, "Not a short position");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        // Delegate to CSDPositionLibrary
        uint256 payout = ICSDPositionLibrary(positionLibrary).closeShortPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.minPrice,
            pos.initialMargin,
            pos.leverage,
            pos.taxedMargin,
            pos.excessMargin,
            makerTokenMargin[pos.makerAddress][ISSListing(pos.listingAddress).tokenB()],
            address(this)
        );

        // Deduct margin immediately
        address token = ISSListing(pos.listingAddress).tokenB();
        makerTokenMargin[pos.makerAddress][token] -= (pos.taxedMargin + pos.excessMargin);
        if (makerTokenMargin[pos.makerAddress][token] == 0) {
            _removeToken(pos.makerAddress, token);
        }

        emit PositionClosed(positionId, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.status1 == false, "Position executable");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        // Delegate to CSDPositionLibrary
        ICSDPositionLibrary(positionLibrary).cancelPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.taxedMargin,
            pos.excessMargin,
            pos.positionType,
            address(this)
        );

        // Deduct margin immediately
        address token = pos.positionType == 0 ? ISSListing(pos.listingAddress).tokenA() : ISSListing(pos.listingAddress).tokenB();
        makerTokenMargin[pos.makerAddress][token] -= (pos.taxedMargin + pos.excessMargin);
        if (makerTokenMargin[pos.makerAddress][token] == 0) {
            _removeToken(pos.makerAddress, token);
        }

        emit PositionCancelled(positionId);
    }

    // Force execution
    function forceExecution(address listingAddress) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 resultCount = ICSDPositionLibrary(positionLibrary).forceExecution(
            listingAddress,
            address(this)
        );
        emit PositionsExecuted(resultCount, listingAddress);
    }

    // Add excess margin
    function addExcessMargin(address maker, uint256 amount, address token) external payable nonReentrant {
        require(amount > 0, "Invalid amount");
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        // Transfer margin
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Normalize amount
        uint256 normalizedAmount = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token, amount);

        // Delegate to CSDPositionLibrary
        ICSDPositionLibrary(positionLibrary).addExcessMargin(
            maker,
            amount,
            token,
            normalizedAmount,
            address(this)
        );

        // Update totalMargin immediately
        uint256 totalMargin = makerTokenMargin[maker][token];
        makerTokenMargin[maker][token] += amount;
        if (totalMargin == 0) {
            makerMarginTokens[maker].push(token);
        }

        emit ExcessMarginAdded(maker, amount, token);
    }

    // Pull margin
    function pullMargin(address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(makerTokenMargin[msg.sender][token] >= amount, "Insufficient margin");

        // Deduct margin immediately
        makerTokenMargin[msg.sender][token] -= amount;
        if (makerTokenMargin[msg.sender][token] == 0) {
            _removeToken(msg.sender, token);
        }

        // Transfer funds
        if (token == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit MarginPulled(msg.sender, amount, token);
    }

    // View functions
    function makerTokenMarginView(address maker, address token) external view returns (uint256) {
        return makerTokenMargin[maker][token];
    }

    function makerMarginIndex(address maker, uint256 index) external view returns (address token, uint256 totalMargin) {
        if (index < makerMarginTokens[maker].length) {
            token = makerMarginTokens[maker][index];
            totalMargin = makerTokenMargin[maker][token];
        } else {
            token = address(0);
            totalMargin = 0;
        }
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

    // Batch operations
    function closeAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).closeAllShort(msg.sender, address(this));
        emit PositionsClosed(count);
    }

    function cancelAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).cancelAllShort(msg.sender, address(this));
        emit PositionsCancelled(count);
    }

    function closeAllLongs() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).closeAllLongs(msg.sender, address(this));
        emit PositionsClosed(count);
    }

    function cancelAllLong() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).cancelAllLong(msg.sender, address(this));
        emit PositionsCancelled(count);
    }

    // Internal helper
    function _removeToken(address maker, address token) internal {
        address[] storage tokens = makerMarginTokens[maker];
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }
    }
}