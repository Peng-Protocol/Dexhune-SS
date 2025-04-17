// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.2:
// - Implemented setPositionDetails to store PositionDetails and update indexes.
// - Implemented updatePositionStatus to manage status2 and pendingPositions.
// - Added updatePositionIndexes and updatePendingPositions for enter$ functions.
// - Updated pullMargin to use payout order with listingAddress parameter.
// - Updated cancelPosition to use payout order.
// - Changed setAgent modifier to onlyOwner.
// - Enhanced batch functions with maxIteration and payout orders.
// - Updated addExcessMargin to use totalMargin, removed listingAddress requirement.
// - Limited excessMargin returns in close/cancel based on totalMargin.
// - Added tax-on-transfer checks for margin transfers.
// - Clarified status1 (pending/executed) and status2 (open/closed/cancelled).
// - Included ISSListing interface inline.
// - Added historicalInterest updates for enter$, close$, cancel$.
// - Added interest and interestHeight view functions.
// - Used local imports (./imports/...).
// - Assumed IERC20 includes decimals().

import "./imports/SafeERC20.sol";
import "./imports/IERC20.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";
import "./imports/Strings.sol";

contract SSCrossDriver is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Structs
    struct PositionDetails {
        address makerAddress;
        uint256 minPrice;
        uint256 maxPrice;
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin; // Reference only, not used in calculations
        uint8 leverage;
        uint256 leverageAmount;
        uint256 initialLoan;
        uint256 liquidationPrice;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType; // 0: Long, 1: Short
        bool status1; // false: pending, true: executed
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

    struct InterestUpdate {
        uint256 positionId;
        uint8 positionType; // 0: Long, 1: Short
        uint256 marginAmount;
        bool isAdd; // true: add, false: subtract
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

        function prepInterestUpdate(
            uint256 positionId,
            uint8 positionType,
            uint256 marginAmount,
            bool isAdd,
            address driver
        ) external;
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
    mapping(uint256 => InterestUpdate) private pendingInterestUpdates; // positionId -> InterestUpdate
    mapping(uint256 => bool) private interestUpdateExists; // positionId -> exists
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
    event InterestUpdated(uint256 indexed height, uint256 shortIO, uint256 longIO, uint256 timestamp);

    // Modifiers
    modifier onlyAgent() {
        require(msg.sender == agent, "Only agent");
        _;
    }

    // Constructor
    constructor() {}

    // Set library addresses
    function setPositionLibrary(address _positionLibrary) external onlyOwner {
        require(_positionLibrary != address(0), "Invalid library");
        positionLibrary = _positionLibrary;
        emit LibrarySet(_positionLibrary, "PositionLibrary");
    }

    function setUtilityLibrary(address _utilityLibrary) external onlyOwner {
        require(_utilityLibrary != address(0), "Invalid library");
        utilityLibrary = _utilityLibrary;
        emit LibrarySet(_utilityLibrary, "UtilityLibrary");
    }

    // Set agent
    function setAgent(address _agent) external onlyOwner {
        require(_agent != address(0), "Invalid agent");
        agent = _agent;
    }

    // Set position details
    function setPositionDetails(uint256 positionId, PositionDetails memory pos) external {
        require(msg.sender == positionLibrary, "Only position library");
        require(pos.positionId == positionId, "Mismatched position ID");
        positionDetails[positionId] = pos;
        positionCount++;
    }

    // Update position status
    function updatePositionStatus(uint256 positionId, uint8 newStatus) external {
        require(msg.sender == positionLibrary, "Only position library");
        require(newStatus <= 2, "Invalid status");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionId == positionId, "Invalid position");
        pos.status2 = newStatus;
        if (newStatus == 1 || newStatus == 2) {
            _removePendingPosition(pos.listingAddress, pos.positionType, positionId);
        }
    }

    // Update position indexes
    function updatePositionIndexes(address user, uint8 positionType, uint256 positionId) external {
        require(msg.sender == positionLibrary, "Only position library");
        userPositions[user].push(positionId);
        positionsByType[positionType].push(positionId);
    }

    // Update pending positions
    function updatePendingPositions(address listingAddress, uint8 positionType, uint256 positionId) external {
        require(msg.sender == positionLibrary, "Only position library");
        pendingPositions[listingAddress][positionType].push(positionId);
    }

    // Helper: Queue payout order
    function queuePayoutOrder(address listingAddress, address recipient, uint256 amount, uint8 payoutType) internal {
        PayoutUpdate[] memory updates = new PayoutUpdate[](1);
        updates[0] = PayoutUpdate({
            recipient: recipient,
            required: amount,
            payoutType: payoutType
        });
        ISSListing(listingAddress).ssUpdate(listingAddress, updates);
    }

    // Helper: Transfer margin with tax-on-transfer check
    function transferMargin(address to, address token, uint256 amount) internal returns (uint256 actualAmount) {
        if (token == address(0)) {
            uint256 balanceBefore = address(to).balance;
            (bool success, ) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
            actualAmount = address(to).balance - balanceBefore;
        } else {
            uint256 balanceBefore = IERC20(token).balanceOf(to);
            IERC20(token).safeTransfer(to, amount);
            actualAmount = IERC20(token).balanceOf(to) - balanceBefore;
        }
    }

    // Helper: Remove pending position
    function _removePendingPosition(address listingAddress, uint8 positionType, uint256 positionId) internal {
        uint256[] storage pending = pendingPositions[listingAddress][positionType];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == positionId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
    }

    // Helper: Queue interest update
    function _queueInterestUpdate(uint256 positionId, uint8 positionType, uint256 marginAmount, bool isAdd) internal {
        require(positionType <= 1, "Invalid position type");
        require(marginAmount > 0, "Invalid margin amount");
        pendingInterestUpdates[positionId] = InterestUpdate({
            positionId: positionId,
            positionType: positionType,
            marginAmount: marginAmount,
            isAdd: isAdd
        });
        interestUpdateExists[positionId] = true;
    }

    // Helper: Remove interest update
    function _removeInterestUpdate(uint256 positionId) internal {
        if (interestUpdateExists[positionId]) {
            delete pendingInterestUpdates[positionId];
            delete interestUpdateExists[positionId];
        }
    }

    // Helper: Execute interest updates
    function executeInterestUpdates() internal {
        bool updated = false;
        uint256 currentHeight = historicalInterestHeight;
        if (currentHeight == 0 || historicalInterest[currentHeight - 1].timestamp != block.timestamp) {
            historicalInterest[currentHeight].timestamp = block.timestamp;
            currentHeight++;
            historicalInterestHeight = currentHeight;
            updated = true;
        }

        for (uint256 i = 0; i < positionCount; i++) {
            if (interestUpdateExists[i]) {
                InterestUpdate memory update = pendingInterestUpdates[i];
                if (update.positionType == 0) {
                    if (update.isAdd) {
                        historicalInterest[currentHeight - 1].longIO += update.marginAmount;
                    } else {
                        historicalInterest[currentHeight - 1].longIO = historicalInterest[currentHeight - 1].longIO > update.marginAmount
                            ? historicalInterest[currentHeight - 1].longIO - update.marginAmount
                            : 0;
                    }
                } else {
                    if (update.isAdd) {
                        historicalInterest[currentHeight - 1].shortIO += update.marginAmount;
                    } else {
                        historicalInterest[currentHeight - 1].shortIO = historicalInterest[currentHeight - 1].shortIO > update.marginAmount
                            ? historicalInterest[currentHeight - 1].shortIO - update.marginAmount
                            : 0;
                    }
                }
                updated = true;
                _removeInterestUpdate(i);
            }
        }

        if (updated) {
            emit InterestUpdated(
                currentHeight - 1,
                historicalInterest[currentHeight - 1].shortIO,
                historicalInterest[currentHeight - 1].longIO,
                historicalInterest[currentHeight - 1].timestamp
            );
        }
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

        address token0 = ISSListing(listingAddress).tokenA();
        uint256 normalizedInitialMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token0, initialMargin);
        uint256 normalizedExcessMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token0, excessMargin);

        uint256 actualInitialMargin = transferMargin(address(this), token0, initialMargin);
        uint256 actualExcessMargin = transferMargin(address(this), token0, excessMargin);

        makerTokenMargin[msg.sender][token0] += actualInitialMargin + actualExcessMargin;
        if (makerTokenMargin[msg.sender][token0] == actualInitialMargin + actualExcessMargin) {
            makerMarginTokens[msg.sender].push(token0);
        }

        uint256 positionId = ICSDPositionLibrary(positionLibrary).enterLong(
            listingAddress,
            entryPrice,
            actualInitialMargin,
            actualExcessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token0,
            normalizedInitialMargin,
            normalizedExcessMargin,
            makerTokenMargin[msg.sender][token0],
            address(this)
        );

        ICSDPositionLibrary(positionLibrary).prepInterestUpdate(
            positionId,
            0,
            actualInitialMargin + actualExcessMargin,
            true,
            address(this)
        );
        executeInterestUpdates();

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

        address token1 = ISSListing(listingAddress).tokenB();
        uint256 normalizedInitialMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token1, initialMargin);
        uint256 normalizedExcessMargin = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token1, excessMargin);

        uint256 actualInitialMargin = transferMargin(address(this), token1, initialMargin);
        uint256 actualExcessMargin = transferMargin(address(this), token1, excessMargin);

        makerTokenMargin[msg.sender][token1] += actualInitialMargin + actualExcessMargin;
        if (makerTokenMargin[msg.sender][token1] == actualInitialMargin + actualExcessMargin) {
            makerMarginTokens[msg.sender].push(token1);
        }

        uint256 positionId = ICSDPositionLibrary(positionLibrary).enterShort(
            listingAddress,
            entryPrice,
            actualInitialMargin,
            actualExcessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            token1,
            normalizedInitialMargin,
            normalizedExcessMargin,
            makerTokenMargin[msg.sender][token1],
            address(this)
        );

        ICSDPositionLibrary(positionLibrary).prepInterestUpdate(
            positionId,
            1,
            actualInitialMargin + actualExcessMargin,
            true,
            address(this)
        );
        executeInterestUpdates();

        emit PositionCreated(positionId, false);
    }

    // Close long position
    function closeLongPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 0, "Not a long position");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        address token = ISSListing(pos.listingAddress).tokenA();
        uint256 payout = ICSDPositionLibrary(positionLibrary).closeLongPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.taxedMargin,
            pos.excessMargin,
            pos.leverageAmount,
            pos.initialLoan,
            makerTokenMargin[pos.makerAddress][token],
            address(this)
        );

        uint256 marginToDeduct = pos.taxedMargin + (pos.excessMargin > makerTokenMargin[pos.makerAddress][token] ? makerTokenMargin[pos.makerAddress][token] : pos.excessMargin);
        makerTokenMargin[pos.makerAddress][token] -= marginToDeduct;
        if (makerTokenMargin[pos.makerAddress][token] == 0) {
            _removeToken(pos.makerAddress, token);
        }

        ICSDPositionLibrary(positionLibrary).prepInterestUpdate(
            positionId,
            0,
            marginToDeduct,
            false,
            address(this)
        );
        executeInterestUpdates();

        emit PositionClosed(positionId, payout);
    }

    // Close short position
    function closeShortPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.positionType == 1, "Not a short position");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        address token = ISSListing(pos.listingAddress).tokenB();
        uint256 payout = ICSDPositionLibrary(positionLibrary).closeShortPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.minPrice,
            pos.initialMargin,
            pos.leverage,
            pos.taxedMargin,
            pos.excessMargin,
            makerTokenMargin[pos.makerAddress][token],
            address(this)
        );

        uint256 marginToDeduct = pos.taxedMargin + (pos.excessMargin > makerTokenMargin[pos.makerAddress][token] ? makerTokenMargin[pos.makerAddress][token] : pos.excessMargin);
        makerTokenMargin[pos.makerAddress][token] -= marginToDeduct;
        if (makerTokenMargin[pos.makerAddress][token] == 0) {
            _removeToken(pos.makerAddress, token);
        }

        ICSDPositionLibrary(positionLibrary).prepInterestUpdate(
            positionId,
            1,
            marginToDeduct,
            false,
            address(this)
        );
        executeInterestUpdates();

        emit PositionClosed(positionId, payout);
    }

    // Cancel position
    function cancelPosition(uint256 positionId) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        PositionDetails storage pos = positionDetails[positionId];
        require(pos.status1 == false, "Position executable");
        require(pos.status2 == 0, "Position not open");
        require(pos.makerAddress == msg.sender, "Not position maker");

        ICSDPositionLibrary(positionLibrary).cancelPosition(
            positionId,
            pos.listingAddress,
            pos.makerAddress,
            pos.taxedMargin,
            pos.excessMargin,
            pos.positionType,
            address(this)
        );

        address token = pos.positionType == 0 ? ISSListing(pos.listingAddress).tokenA() : ISSListing(pos.listingAddress).tokenB();
        uint256 marginToDeduct = pos.taxedMargin + (pos.excessMargin > makerTokenMargin[pos.makerAddress][token] ? makerTokenMargin[pos.makerAddress][token] : pos.excessMargin);
        makerTokenMargin[pos.makerAddress][token] -= marginToDeduct;
        if (makerTokenMargin[pos.makerAddress][token] == 0) {
            _removeToken(pos.makerAddress, token);
        }

        ICSDPositionLibrary(positionLibrary).prepInterestUpdate(
            positionId,
            pos.positionType,
            marginToDeduct,
            false,
            address(this)
        );
        executeInterestUpdates();

        emit PositionCancelled(positionId);
    }

    // Force execution
    function forceExecution(address listingAddress) external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 resultCount = ICSDPositionLibrary(positionLibrary).forceExecution(
            listingAddress,
            address(this)
        );
        executeInterestUpdates();
        emit PositionsExecuted(resultCount, listingAddress);
    }

    // Add excess margin
    function addExcessMargin(address maker, uint256 amount, address token) external payable nonReentrant {
        require(amount > 0, "Invalid amount");
        require(positionLibrary != address(0), "PositionLibrary not set");
        require(utilityLibrary != address(0), "UtilityLibrary not set");

        uint256 actualAmount = transferMargin(address(this), token, amount);
        uint256 normalizedAmount = ICSDUtilityLibrary(utilityLibrary).normalizeAmount(token, actualAmount);

        ICSDPositionLibrary(positionLibrary).addExcessMargin(
            maker,
            actualAmount,
            token,
            normalizedAmount,
            address(this)
        );

        makerTokenMargin[maker][token] += actualAmount;
        if (makerTokenMargin[maker][token] == actualAmount) {
            makerMarginTokens[maker].push(token);
        }

        emit ExcessMarginAdded(maker, actualAmount, token);
    }

    // Pull margin
    function pullMargin(address listingAddress, address token, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        require(makerTokenMargin[msg.sender][token] >= amount, "Insufficient margin");
        require(listingAddress != address(0), "Invalid listing");

        makerTokenMargin[msg.sender][token] -= amount;
        if (makerTokenMargin[msg.sender][token] == 0) {
            _removeToken(msg.sender, token);
        }

        uint8 payoutType = token == ISSListing(listingAddress).tokenA() ? uint8(0) : uint8(1);
        queuePayoutOrder(listingAddress, msg.sender, amount, payoutType);

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

    function interest(uint256 index) external view returns (uint256 shortIO, uint256 longIO) {
        require(index < historicalInterestHeight, "Invalid index");
        shortIO = historicalInterest[index].shortIO;
        longIO = historicalInterest[index].longIO;
    }

    function interestHeight() external view returns (uint256) {
        return historicalInterestHeight;
    }

    // Batch operations
    function closeAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).closeAllShort(msg.sender, address(this));
        executeInterestUpdates();
        emit PositionsClosed(count);
    }

    function cancelAllShort() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).cancelAllShort(msg.sender, address(this));
        executeInterestUpdates();
        emit PositionsCancelled(count);
    }

    function closeAllLongs() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).closeAllLongs(msg.sender, address(this));
        executeInterestUpdates();
        emit PositionsClosed(count);
    }

    function cancelAllLong() external nonReentrant {
        require(positionLibrary != address(0), "PositionLibrary not set");
        uint256 count = ICSDPositionLibrary(positionLibrary).cancelAllLong(msg.sender, address(this));
        executeInterestUpdates();
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