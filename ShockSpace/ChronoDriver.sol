// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.14
// Change Log:
// - 2025-07-12: Updated to v0.0.14, added view functions
//   - Added totalDrives to return count of all chrono drives
//   - Added viewDrive to return StalledChronoDrive details for a given driveId
//   - Added getUserDrives to return array of drive IDs for a user
//   - Added getActiveDrivesCount to return count of active drives for a user
//   - Added getTotalActiveDrives to return count of all active drives globally
//   - Preserved all functionality from v0.0.13
// - Previous (v0.0.13):
//   - Fixed stack too deep in _executeChronoDrive
//   - Refactored _executeChronoDrive into internal call tree with helpers
//   - Updated continueChronoDrive and executeChronoDrive to set isCross explicitly
// - Previous (v0.0.12):
//   - Replaced maxIterations with isCross in chronoDrive
//   - Modified settleParams to parse positionType-isCross
//   - Updated _parseSettleParams to return positionType and isCross
//   - Updated _executeChronoDrive to use isCross for driver selection
// - Previous (v0.0.11):
//   - Added cancelChronoDrive, continueChronoDrive, executeChronoDrive
//   - Replaced shockEntry and isCrossDriver with crossDriverAddress and isolatedDriverAddress
//   - Added mappings and arrays for drive tracking
// - Previous (v0.0.10):
//   - Fixed stack too deep in chronoDrive
//   - Added ChronoDriveParams struct
// - Previous (v0.0.9):
//   - Changed listings to singular listing in pathParams
// - Previous (v0.0.8):
//   - Removed tokens string from pathParams
//   - Computed stopLossPrice and takeProfitPrice using pricePercent
// - Previous (v0.0.7):
//   - Fixed stack too deep in _initializeChronoDrive
// - Previous (v0.0.6):
//   - Combined chronoDrive inputs into four hyphen-delimited strings
// - Previous (v0.0.5):
//   - Optimized chronoDrive by reducing local variables
// - Previous (v0.0.4):
//   - Removed redundant IERC20 interface
// - Previous (v0.0.3):
//   - Initial implementation of ChronoDriver

import "./imports/Ownable.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

// Interface for ISSCrossDriver (minimal, only used functions)
interface ISSCrossDriver {
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

    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType);
}

// Interface for ISSIsolatedDriver (minimal, only used functions)
interface ISSIsolatedDriver {
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

    event PositionEntered(
        uint256 indexed positionId,
        address indexed maker,
        uint8 positionType,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address mux
    );
}

// Interface for ISSListingTemplate (minimal, only used functions)
interface ISSListingTemplate {
    function listingPriceView() external view returns (uint256);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

// ChronoDriver contract for time-based position execution via ISSCrossDriver or ISSIsolatedDriver
contract ChronoDriver is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constant for decimal precision
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Constant for fee calculation
    uint256 private constant FEE_BASIS_POINTS = 5; // 0.05% fee

    // State variables (hidden, accessed via view functions)
    address private crossDriverAddress; // ISSCrossDriver contract address
    address private isolatedDriverAddress; // ISSIsolatedDriver contract address
    uint256 private nextChronoDriveId; // Tracks next drive ID
    uint256[] private totalChronoDrives; // Global list of drive IDs
    mapping(address => uint256[]) private chronoDrivesByAddress; // Maps maker to their drive IDs
    mapping(uint256 => StalledChronoDrive) private chronoDriveID; // Stores drive details
    mapping(uint256 => bool) private isChronoDrive; // Flags time-based drives

    // Struct to hold stalled chronoDrive data
    struct StalledChronoDrive {
        address listingAddress;
        uint8 positionType;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 pricePercent;
        uint256 timestamp;
        address maker;
        address token;
        uint256 principalAmount;
        uint256 feeAmount;
        uint8 driveStatus; // 1 = active, 2 = completed/canceled
        uint256 positionId; // ID from driver contract
    }

    // Struct to hold chronoDrive parameters
    struct ChronoDriveParams {
        address listingAddress;
        uint8 positionType;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 pricePercent;
        uint256 timestamp;
        address maker;
        address token;
        uint256 rawPrincipal;
        uint256 normalizedPrincipal;
        uint256 feeAmount;
        uint256 principal;
        uint256 rawPrincipalAfterFee;
        uint256 maxEntryPrice;
        uint256 minEntryPrice;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 driveStatus; // 1 = active, 2 = completed/canceled
        uint256 driveId; // Unique ID for the drive
        bool isCross; // True for CrossDriver, false for IsolatedDriver
    }

    // Events
    event FeePaid(address indexed recipient, address token, uint256 amount);
    event CrossDriverSet(address indexed crossDriverAddress);
    event IsolatedDriverSet(address indexed isolatedDriverAddress);
    event ChronoDriveStarted(uint256 indexed driveId, address indexed maker);
    event ChronoDriveContinued(uint256 indexed driveId, address indexed maker);
    event ChronoDriveCanceled(uint256 indexed driveId, address indexed maker);
    event AllChronoDrivesCanceled(address indexed maker, uint256 count);

    // Modifier for valid driver address
    modifier onlyValidDriver() {
        require(crossDriverAddress != address(0) || isolatedDriverAddress != address(0), "No driver set");
        _;
    }

    // Constructor
    constructor() {
        _transferOwnership(msg.sender); // Sets msg.sender as owner
        nextChronoDriveId = 1; // Initialize drive ID counter
    }

    // Sets CrossDriver address
    // @param _crossDriverAddress New ISSCrossDriver contract address
    function setCrossDriverAddress(address _crossDriverAddress) external onlyOwner {
        require(_crossDriverAddress != address(0), "Invalid CrossDriver address");
        crossDriverAddress = _crossDriverAddress; // Updates CrossDriver address
        emit CrossDriverSet(_crossDriverAddress);
    }

    // Sets IsolatedDriver address
    // @param _isolatedDriverAddress New ISSIsolatedDriver contract address
    function setIsolatedDriverAddress(address _isolatedDriverAddress) external onlyOwner {
        require(_isolatedDriverAddress != address(0), "Invalid IsolatedDriver address");
        isolatedDriverAddress = _isolatedDriverAddress; // Updates IsolatedDriver address
        emit IsolatedDriverSet(_isolatedDriverAddress);
    }

    // View function to get CrossDriver address
    // @return CrossDriver address
    function crossDriverAddressView() external view returns (address) {
        return crossDriverAddress;
    }

    // View function to get IsolatedDriver address
    // @return IsolatedDriver address
    function isolatedDriverAddressView() external view returns (address) {
        return isolatedDriverAddress;
    }

    // View function to get total number of chrono drives
    // @return Total count of chrono drives
    function totalDrives() external view returns (uint256) {
        return totalChronoDrives.length;
    }

    // View function to get details of a specific drive
    // @param driveId ID of the chrono drive
    // @return StalledChronoDrive struct with drive details
    function viewDrive(uint256 driveId) external view returns (StalledChronoDrive memory) {
        require(isChronoDrive[driveId], "Drive does not exist");
        return chronoDriveID[driveId];
    }

    // View function to get drive IDs for a user
    // @param user Address of the user
    // @return Array of drive IDs
    function getUserDrives(address user) external view returns (uint256[] memory) {
        return chronoDrivesByAddress[user];
    }

    // View function to get count of active drives for a user
    // @param user Address of the user
    // @return Count of active drives
    function getActiveDrivesCount(address user) external view returns (uint256) {
        uint256 count = 0;
        uint256[] memory drives = chronoDrivesByAddress[user];
        for (uint256 i = 0; i < drives.length; i++) {
            if (chronoDriveID[drives[i]].driveStatus == 1) {
                count++;
            }
        }
        return count;
    }

    // View function to get total count of active drives globally
    // @return Count of all active drives
    function getTotalActiveDrives() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < totalChronoDrives.length; i++) {
            if (chronoDriveID[totalChronoDrives[i]].driveStatus == 1) {
                count++;
            }
        }
        return count;
    }

    // Gets token decimals
    // @param token Token address
    // @return Token decimals, defaults to 18 for native currency
    function _getTokenDecimals(address token) private view returns (uint8) {
        if (token == address(0)) return 18;
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return decimals;
    }

    // Normalizes amount
    // @param token Token address
    // @param amount Amount to normalize
    // @return Normalized amount
    function _normalizeAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 decimals = _getTokenDecimals(token);
        if (decimals == 18) return amount;
        return (amount * DECIMAL_PRECISION) / (10 ** decimals);
    }

    // Denormalizes amount
    // @param token Token address
    // @param amount Normalized amount
    // @return Denormalized amount
    function _denormalizeAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 decimals = _getTokenDecimals(token);
        if (decimals == 18) return amount;
        return (amount * (10 ** decimals)) / DECIMAL_PRECISION;
    }

    // Normalizes price
    // @param token Token address
    // @param price Price to normalize
    // @param listingAddress Listing address for context
    // @return Normalized price
    function _normalizePrice(address token, uint256 price, address listingAddress) private view returns (uint256) {
        uint8 decimals = _getTokenDecimals(token);
        if (decimals == 18) return price;
        return (price * DECIMAL_PRECISION) / (10 ** decimals);
    }

    // Parses uint from string
    // @param str String to parse
    // @return Parsed uint
    function _parseUint(string memory str) private pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        uint256 result = 0;
        for (uint256 i = 0; i < strBytes.length; i++) {
            uint8 char = uint8(strBytes[i]);
            require(char >= 48 && char <= 57, "Invalid uint character");
            result = result * 10 + (char - 48);
        }
        return result;
    }

    // Parses boolean from string
    // @param str String to parse ("0" for false, "1" for true)
    // @return Parsed boolean
    function _parseBool(string memory str) private pure returns (bool) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 1, "Invalid bool length");
        uint8 char = uint8(strBytes[0]);
        require(char == 48 || char == 49, "Invalid bool character");
        return char == 49;
    }

    // Parses address from string
    // @param str String to parse
    // @return Parsed address
    function _parseAddress(string memory str) private pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        uint160 addr;
        for (uint256 i = 2; i < 42; i++) {
            uint8 char = uint8(strBytes[i]);
            uint160 value;
            if (char >= 48 && char <= 57) {
                value = uint160(char - 48);
            } else if (char >= 97 && char <= 102) {
                value = uint160(char - 87);
            } else if (char >= 65 && char <= 70) {
                value = uint160(char - 55);
            } else {
                revert("Invalid address character");
            }
            addr = addr * 16 + value;
        }
        return address(addr);
    }

    // Extracts substring
    // @param data Bytes to extract from
    // @param start Start index
    // @param end End index
    // @return Extracted string
    function _substring(bytes memory data, uint256 start, uint256 end) private pure returns (string memory) {
        bytes memory result = new bytes(end - start);
        for (uint256 i = 0; i < end - start; i++) {
            result[i] = data[start + i];
        }
        return string(result);
    }

    // Parses path parameters
    // @param pathParams Hyphen-delimited string: listing-impactPercent
    // @return listingAddress, impactPercent
    function _parsePathParams(string memory pathParams)
        private
        pure
        returns (address listingAddress, uint256 impactPercent)
    {
        bytes memory paramsBytes = bytes(pathParams);
        uint256 hyphenIndex;
        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == "-") {
                hyphenIndex = i;
                break;
            }
        }
        require(hyphenIndex > 0, "Invalid path params");
        string memory listing = _substring(paramsBytes, 0, hyphenIndex);
        string memory impactStr = _substring(paramsBytes, hyphenIndex + 1, paramsBytes.length);
        listingAddress = _parseAddress(listing);
        impactPercent = _parseUint(impactStr);
    }

    // Parses settle parameters
    // @param settleParams Hyphen-delimited string: positionType-isCross
    // @return positionType, isCross
    function _parseSettleParams(string memory settleParams)
        private
        pure
        returns (uint8 positionType, bool isCross)
    {
        bytes memory paramsBytes = bytes(settleParams);
        uint256 hyphenIndex;
        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == "-") {
                hyphenIndex = i;
                break;
            }
        }
        require(hyphenIndex > 0, "Invalid settle params");
        string memory positionTypeStr = _substring(paramsBytes, 0, hyphenIndex);
        string memory isCrossStr = _substring(paramsBytes, hyphenIndex + 1, paramsBytes.length);
        positionType = uint8(_parseUint(positionTypeStr));
        isCross = _parseBool(isCrossStr);
    }

    // Parses position data
    // @param positionData Hyphen-delimited string: initialMargin-excessMargin-leverage
    // @return initialMargin, excessMargin, leverage
    function _parsePositionData(string memory positionData)
        private
        pure
        returns (uint256 initialMargin, uint256 excessMargin, uint8 leverage)
    {
        bytes memory paramsBytes = bytes(positionData);
        uint256[] memory indices = new uint256[](2);
        uint256 count = 0;
        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == "-") {
                indices[count] = i;
                count++;
            }
        }
        require(count == 2, "Invalid position data");
        string memory initialMarginStr = _substring(paramsBytes, 0, indices[0]);
        string memory excessMarginStr = _substring(paramsBytes, indices[0] + 1, indices[1]);
        string memory leverageStr = _substring(paramsBytes, indices[1] + 1, paramsBytes.length);
        initialMargin = _parseUint(initialMarginStr);
        excessMargin = _parseUint(excessMarginStr);
        leverage = uint8(_parseUint(leverageStr));
    }

    // Parses execution data
    // @param executionData Hyphen-delimited string: pricePercent-timestamp-maker
    // @return pricePercent, timestamp, maker
    function _parseExecutionData(string memory executionData)
        private
        pure
        returns (uint256 pricePercent, uint256 timestamp, address maker)
    {
        bytes memory paramsBytes = bytes(executionData);
        uint256[] memory indices = new uint256[](2);
        uint256 count = 0;
        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == "-") {
                indices[count] = i;
                count++;
            }
        }
        require(count == 2, "Invalid execution data");
        string memory pricePercentStr = _substring(paramsBytes, 0, indices[0]);
        string memory timestampStr = _substring(paramsBytes, indices[0] + 1, indices[1]);
        string memory makerStr = _substring(paramsBytes, indices[1] + 1, paramsBytes.length);
        pricePercent = _parseUint(pricePercentStr);
        timestamp = _parseUint(timestampStr);
        maker = _parseAddress(makerStr);
    }

    // Gets position token based on listing address and position type
    // @param listingAddress Address of the listing contract
    // @param positionType 0 for long (tokenA), 1 for short (tokenB)
    // @return Token address
    function _getPositionToken(address listingAddress, uint8 positionType) private view returns (address) {
        require(positionType <= 1, "Invalid position type");
        if (positionType == 0) {
            return ISSListingTemplate(listingAddress).tokenA();
        } else {
            return ISSListingTemplate(listingAddress).tokenB();
        }
    }

    // Checks and transfers tokens
    // @param token Token address
    // @param from Sender address
    // @param to Recipient address
    // @param amount Amount to transfer
    // @return Actual transferred amount
    function _checkTransfer(address token, address from, address to, uint256 amount) private returns (uint256) {
        uint256 balanceBefore = token == address(0) ? address(to).balance : IERC20(token).balanceOf(to);
        if (token == address(0)) {
            require(msg.value >= amount, "Insufficient msg.value");
            payable(to).transfer(amount);
        } else {
            IERC20(token).safeTransferFrom(from, to, amount);
        }
        uint256 balanceAfter = token == address(0) ? address(to).balance : IERC20(token).balanceOf(to);
        require(balanceAfter > balanceBefore, "Transfer failed");
        return balanceAfter - balanceBefore;
    }

    // Computes entry and exit prices
    // @param listingAddress Listing address for price query
    // @param token Token address for price normalization
    // @param pricePercent Percentage for price calculation
    // @param positionType 0 for long, 1 for short
    // @return maxEntryPrice, minEntryPrice, stopLossPrice, takeProfitPrice (normalized)
    function _computeEntryPrices(address listingAddress, address token, uint256 pricePercent, uint8 positionType)
        private
        view
        returns (uint256 maxEntryPrice, uint256 minEntryPrice, uint256 stopLossPrice, uint256 takeProfitPrice)
    {
        uint256 currentPrice = ISSListingTemplate(listingAddress).listingPriceView();
        uint256 priceDelta = (currentPrice * pricePercent) / 100;
        maxEntryPrice = _normalizePrice(token, currentPrice + priceDelta, listingAddress);
        minEntryPrice = _normalizePrice(token, currentPrice - priceDelta, listingAddress);
        if (positionType == 0) {
            // Long: stop-loss below current price, take-profit above
            stopLossPrice = _normalizePrice(token, currentPrice - priceDelta, listingAddress);
            takeProfitPrice = _normalizePrice(token, currentPrice + priceDelta, listingAddress);
        } else {
            // Short: stop-loss above current price, take-profit below
            stopLossPrice = _normalizePrice(token, currentPrice + priceDelta, listingAddress);
            takeProfitPrice = _normalizePrice(token, currentPrice - priceDelta, listingAddress);
        }
    }

    // Parses chronoDrive input parameters
    // @param pathParams Hyphen-delimited string: listing-impactPercent
    // @param settleParams Hyphen-delimited string: positionType-isCross
    // @param positionData Hyphen-delimited string: initialMargin-excessMargin-leverage
    // @param executionData Hyphen-delimited string: pricePercent-timestamp-maker
    // @return ChronoDriveParams with parsed inputs
    function _parseChronoDriveInputs(
        string memory pathParams,
        string memory settleParams,
        string memory positionData,
        string memory executionData
    ) private pure returns (ChronoDriveParams memory params) {
        (address listingAddress, ) = _parsePathParams(pathParams);
        (uint8 positionType, bool isCross) = _parseSettleParams(settleParams);
        (uint256 initialMargin, uint256 excessMargin, uint8 leverage) = _parsePositionData(positionData);
        (uint256 pricePercent, uint256 timestamp, address maker) = _parseExecutionData(executionData);
        params.listingAddress = listingAddress;
        params.positionType = positionType;
        params.initialMargin = initialMargin;
        params.excessMargin = excessMargin;
        params.leverage = leverage;
        params.pricePercent = pricePercent;
        params.timestamp = timestamp;
        params.maker = maker;
        params.isCross = isCross;
    }

    // Validates chronoDrive input parameters
    // @param params ChronoDriveParams to validate
    function _validateChronoDriveInputs(ChronoDriveParams memory params) private view {
        require(params.timestamp >= block.timestamp, "Timestamp in past");
        require(params.pricePercent <= 100, "Price percent exceeds 100");
        require(params.positionType <= 1, "Invalid position type");
    }

    // Handles token transfer and fee calculation
    // @param params ChronoDriveParams to update
    function _handleTokenTransfer(ChronoDriveParams memory params) private {
        params.token = _getPositionToken(params.listingAddress, params.positionType);
        params.rawPrincipal = params.token == address(0) ? msg.value : 0;
        if (params.token != address(0)) {
            params.rawPrincipal = _checkTransfer(params.token, msg.sender, address(this), params.rawPrincipal);
        }
        params.normalizedPrincipal = _normalizeAmount(params.token, params.rawPrincipal);
        params.feeAmount = (params.normalizedPrincipal * FEE_BASIS_POINTS) / 10000; // 0.05% fee
        require(params.normalizedPrincipal > params.feeAmount, "Principal too low for fee");
        params.principal = params.normalizedPrincipal - params.feeAmount;
        params.rawPrincipalAfterFee = _denormalizeAmount(params.token, params.principal);
    }

    // Computes chronoDrive prices
    // @param params ChronoDriveParams to update
    function _computeChronoDrivePrices(ChronoDriveParams memory params) private view {
        (params.maxEntryPrice, params.minEntryPrice, params.stopLossPrice, params.takeProfitPrice) = 
            _computeEntryPrices(params.listingAddress, params.token, params.pricePercent, params.positionType);
    }

    // Prepares driver selection and validation
    // @param params ChronoDriveParams with driver selection data
    // @return driverAddress Selected driver address
    function _prepareDriverExecution(ChronoDriveParams memory params) private view returns (address) {
        address driverAddress = params.isCross ? crossDriverAddress : isolatedDriverAddress;
        require(driverAddress != address(0), "Selected driver not set");
        return driverAddress;
    }

    // Handles token approval for driver contract
    // @param params ChronoDriveParams with token and amount data
    // @param driverAddress Address of the driver contract
    function _handleTokenApproval(ChronoDriveParams memory params, address driverAddress) private {
        if (params.token != address(0)) {
            IERC20(params.token).safeApprove(driverAddress, params.rawPrincipalAfterFee);
        }
    }

    // Executes the drive call on the selected driver
    // @param params ChronoDriveParams with execution data
    // @param driverAddress Address of the driver contract
    // @return positionId Position ID from driver call
    function _executeDriverCall(ChronoDriveParams memory params, address driverAddress) private returns (uint256) {
        address effectiveMaker = params.maker == address(0) ? msg.sender : params.maker;
        uint256 positionId;
        if (params.isCross) {
            ISSCrossDriver(driverAddress).drive(
                effectiveMaker,
                params.listingAddress,
                params.minEntryPrice,
                params.maxEntryPrice,
                params.rawPrincipalAfterFee,
                params.excessMargin,
                params.leverage,
                params.stopLossPrice,
                params.takeProfitPrice,
                params.positionType
            );
        } else {
            positionId = ISSIsolatedDriver(driverAddress).drive(
                effectiveMaker,
                params.listingAddress,
                params.minEntryPrice,
                params.maxEntryPrice,
                params.rawPrincipalAfterFee,
                params.excessMargin,
                params.leverage,
                params.stopLossPrice,
                params.takeProfitPrice,
                params.positionType
            );
        }
        return positionId;
    }

    // Processes fee payout to msg.sender
    // @param params ChronoDriveParams with fee data
    function _processFeePayout(ChronoDriveParams memory params) private {
        if (params.feeAmount > 0) {
            uint256 rawFee = _denormalizeAmount(params.token, params.feeAmount);
            if (params.token == address(0)) {
                payable(msg.sender).transfer(rawFee);
            } else {
                IERC20(params.token).safeTransfer(msg.sender, rawFee);
            }
            emit FeePaid(msg.sender, params.token, rawFee);
        }
    }

    // Executes the drive call and handles fee payout
    // @param params ChronoDriveParams with all data
    // @return positionId from driver call
    function _executeChronoDrive(ChronoDriveParams memory params) private returns (uint256) {
        address driverAddress = _prepareDriverExecution(params);
        _handleTokenApproval(params, driverAddress);
        uint256 positionId = _executeDriverCall(params, driverAddress);
        if (params.token != address(0)) {
            IERC20(params.token).safeApprove(driverAddress, 0);
        }
        _processFeePayout(params);
        return positionId;
    }

    // Initializes a stalled chronoDrive
    // @param params ChronoDriveParams with parsed data
    // @return driveId Assigned drive ID
    function _initializeChronoDrive(ChronoDriveParams memory params) private returns (uint256) {
        uint256 driveId = nextChronoDriveId++;
        StalledChronoDrive storage drive = chronoDriveID[driveId];
        drive.listingAddress = params.listingAddress;
        drive.positionType = params.positionType;
        drive.initialMargin = params.initialMargin;
        drive.excessMargin = params.excessMargin;
        drive.leverage = params.leverage;
        drive.pricePercent = params.pricePercent;
        drive.timestamp = params.timestamp;
        drive.maker = params.maker == address(0) ? msg.sender : params.maker;
        drive.token = params.token;
        drive.principalAmount = params.rawPrincipalAfterFee;
        drive.feeAmount = params.feeAmount;
        drive.driveStatus = 1; // Active
        chronoDrivesByAddress[drive.maker].push(driveId);
        totalChronoDrives.push(driveId);
        isChronoDrive[driveId] = true;
        emit ChronoDriveStarted(driveId, drive.maker);
        return driveId;
    }

    // Initiates a time-based position via ISSCrossDriver or ISSIsolatedDriver
    // @param pathParams Hyphen-delimited string: listing-impactPercent
    // @param settleParams Hyphen-delimited string: positionType-isCross
    // @param positionData Hyphen-delimited string: initialMargin-excessMargin-leverage
    // @param executionData Hyphen-delimited string: pricePercent-timestamp-maker
    function chronoDrive(
        string memory pathParams,
        string memory settleParams,
        string memory positionData,
        string memory executionData
    ) external payable nonReentrant onlyValidDriver returns (uint256) {
        ChronoDriveParams memory params = _parseChronoDriveInputs(pathParams, settleParams, positionData, executionData);
        _validateChronoDriveInputs(params);
        _handleTokenTransfer(params);
        if (params.timestamp <= block.timestamp) {
            _computeChronoDrivePrices(params);
            return _executeChronoDrive(params);
        } else {
            params.driveId = _initializeChronoDrive(params);
            params.driveStatus = 1;
            return params.driveId;
        }
    }

    // Cancels a pending chronoDrive
    // @param driveId ID of the drive to cancel
    function cancelChronoDrive(uint256 driveId) external nonReentrant {
        StalledChronoDrive storage drive = chronoDriveID[driveId];
        require(isChronoDrive[driveId], "Drive does not exist");
        require(drive.maker == msg.sender, "Not drive maker");
        require(drive.driveStatus == 1, "Drive not active");
        drive.driveStatus = 2; // Mark as canceled
        uint256 totalRefund = drive.principalAmount + _denormalizeAmount(drive.token, drive.feeAmount);
        if (drive.token == address(0)) {
            payable(drive.maker).transfer(totalRefund);
        } else {
            IERC20(drive.token).safeTransfer(drive.maker, totalRefund);
        }
        // Remove from chronoDrivesByAddress
        uint256[] storage drives = chronoDrivesByAddress[drive.maker];
        for (uint256 i = 0; i < drives.length; i++) {
            if (drives[i] == driveId) {
                drives[i] = drives[drives.length - 1];
                drives.pop();
                break;
            }
        }
        // Remove from totalChronoDrives
        for (uint256 i = 0; i < totalChronoDrives.length; i++) {
            if (totalChronoDrives[i] == driveId) {
                totalChronoDrives[i] = totalChronoDrives[totalChronoDrives.length - 1];
                totalChronoDrives.pop();
                break;
            }
        }
        emit ChronoDriveCanceled(driveId, drive.maker);
    }

    // Continues maker's pending chronoDrives
    // @param maxIterations Maximum drives to process
    function continueChronoDrive(uint256 maxIterations) external nonReentrant onlyValidDriver {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256[] storage drives = chronoDrivesByAddress[msg.sender];
        uint256 processed = 0;
        for (uint256 i = 0; i < drives.length && processed < maxIterations; ) {
            uint256 driveId = drives[i];
            StalledChronoDrive storage drive = chronoDriveID[driveId];
            if (drive.driveStatus == 1 && block.timestamp >= drive.timestamp) {
                ChronoDriveParams memory params;
                params.listingAddress = drive.listingAddress;
                params.positionType = drive.positionType;
                params.initialMargin = drive.initialMargin;
                params.excessMargin = drive.excessMargin;
                params.leverage = drive.leverage;
                params.pricePercent = drive.pricePercent;
                params.timestamp = drive.timestamp;
                params.maker = drive.maker;
                params.token = drive.token;
                params.rawPrincipalAfterFee = drive.principalAmount;
                params.feeAmount = drive.feeAmount;
                params.isCross = drive.positionType == 0; // Default to Cross for long positions, adjust as needed
                _computeChronoDrivePrices(params);
                drive.positionId = _executeChronoDrive(params);
                drive.driveStatus = 2; // Mark as completed
                drives[i] = drives[drives.length - 1];
                drives.pop();
                emit ChronoDriveContinued(driveId, drive.maker);
                processed++;
            } else {
                i++;
            }
        }
    }

    // Executes pending chronoDrives globally
    // @param maxIterations Maximum drives to process
    function executeChronoDrive(uint256 maxIterations) external nonReentrant onlyValidDriver {
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 processed = 0;
        for (uint256 i = 0; i < totalChronoDrives.length && processed < maxIterations; ) {
            uint256 driveId = totalChronoDrives[i];
            StalledChronoDrive storage drive = chronoDriveID[driveId];
            if (drive.driveStatus == 1 && block.timestamp >= drive.timestamp) {
                ChronoDriveParams memory params;
                params.listingAddress = drive.listingAddress;
                params.positionType = drive.positionType;
                params.initialMargin = drive.initialMargin;
                params.excessMargin = drive.excessMargin;
                params.leverage = drive.leverage;
                params.pricePercent = drive.pricePercent;
                params.timestamp = drive.timestamp;
                params.maker = drive.maker;
                params.token = drive.token;
                params.rawPrincipalAfterFee = drive.principalAmount;
                params.feeAmount = drive.feeAmount;
                params.isCross = drive.positionType == 0; // Default to Cross for long positions, adjust as needed
                _computeChronoDrivePrices(params);
                drive.positionId = _executeChronoDrive(params);
                drive.driveStatus = 2; // Mark as completed
                // Remove from chronoDrivesByAddress
                uint256[] storage makerDrives = chronoDrivesByAddress[drive.maker];
                for (uint256 j = 0; j < makerDrives.length; j++) {
                    if (makerDrives[j] == driveId) {
                        makerDrives[j] = makerDrives[makerDrives.length - 1];
                        makerDrives.pop();
                        break;
                    }
                }
                // Remove from totalChronoDrives
                totalChronoDrives[i] = totalChronoDrives[totalChronoDrives.length - 1];
                totalChronoDrives.pop();
                emit ChronoDriveContinued(driveId, drive.maker);
                processed++;
            } else {
                i++;
            }
        }
    }

    // View function to get contract balance
    // @param token Token address
    // @return Contract balance for token or native currency
    function getContractBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
}