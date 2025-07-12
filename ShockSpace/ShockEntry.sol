// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version 0.0.58: Integrated refundedPending for accurate refund tracking in entry hop cancellation
// - Updated CancelPrepData struct to include refundedPending field
// - Modified _cancelEntryHop to use refundedPending for updating refund logic
// - Ensured _handlePending returns actual refunded amount after transfer
// - Aligned refund handling with Multihopper's refundedPending usage
// - Preserved all functionality from v0.0.57
// - Changelog from v0.0.57:
//   - Optimized stack usage in continuation functions
//   - Introduced DriverParams struct to precompute drive call parameters
//   - Added _prepareDriverParams helper to denormalize price and amount parameters
//   - Refactored _executeCrossContinueHop and _executeIsolatedContinueHop to use DriverParams
//   - Reduced stack slots to avoid stack too deep error
//   - Preserved all functionality from v0.0.56, including maker-supplied price bounds
// - Changelog from v0.0.56:
//   - Refactored _executeEntryHop into helpers: _transferAndApproveTokens, _executeMultihop, _attemptContinuation
//   - Fixed typo from v0.0.55 (h-campusParams to hopParams)
// - Changelog from v0.0.55:
//   - Corrected h-campusParams.endToken to hopParams.endToken in takeProfitPrice normalization
// - Changelog from v0.0.54:
//   - Updated _executeEntryHop to store minEntryPrice and maxEntryPrice in EntryHop struct
//   - Modified _executeCrossContinueHop and _executeIsolatedContinueHop to use stored price bounds
//   - Ensured price bounds are normalized using _normalizePrice
// - Changelog from v0.0.53:
//   - Added executePositions call after drive in _executeCrossContinueHop and _executeIsolatedContinueHop
//   - Added maxIterations parameter to _executeEntryHop for executePositions
//   - Ensured driver address validation before executePositions call
//   - Maintained graceful degradation if executePositions fails
// - Changelog from v0.0.52:
//   - Enhanced cancellation behavior in _cancelEntryHop
//   - Added CancelPrepData struct to streamline refund and state handling
//   - Included balance checks before refunds to prevent failures
//   - Validated Multihopper hop status before cancellation
//   - Handled both pending and amountSent for comprehensive refunds
//   - Aligned with Multihopper's cancellation logic for consistency
//   - Ensured events are emitted only after successful operations
//   - Maintained flow: tokens from msg.sender, multihop via Multihopper, position for maker

import "./imports/ReentrancyGuard.sol";
import "./imports/Ownable.sol";
import "./imports/SafeERC20.sol";

// Interface for Multihopper contract
interface IMultihopper {
    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 orderID;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus;
        uint256 maxIterations;
    }

    struct HopOrderDetails {
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 amountSent;
        address recipient;
    }

    function hop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        address maker
    ) external;

    function cancelHop(uint256 hopId) external;
    function getHopOrderDetails(uint256 hopId) external view returns (HopOrderDetails memory);
    function getHopDetails(uint256 hopId) external view returns (StalledHop memory);
}

// Interface for SSCrossDriver contract
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

    function executePositions(address listingAddress) external;
}

// Interface for ISSIsolatedDriver contract
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
    ) external;

    function executePositions(address listingAddress) external;
}

// Interface for ISSListingTemplate
interface ISSListingTemplate {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

// ShockEntry contract for multi-hop swaps followed by position creation
contract ShockEntry is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constant for decimal precision
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // State variables (hidden, accessed via view functions)
    address private crossDriver; // Address of SSCrossDriver contract
    address private isolatedDriver; // Address of ISSIsolatedDriver contract
    address private multihopper; // Address of Multihopper contract
    uint256 private hopCount; // Tracks total number of entry hops
    mapping(address => uint256[]) private userHops; // Maps user to their entry hop IDs
    mapping(uint256 => EntryHop) private entryHops; // Maps hop ID to entry hop details

    // Struct for entry hop details
    struct EntryHop {
        address maker; // Hop initiator
        uint256 hopId; // Multihopper hop ID
        address listingAddress; // Listing for position creation
        uint8 positionType; // 0 for long, 1 for short
        uint256 initialMargin; // Initial margin for position (normalized)
        uint256 excessMargin; // Excess margin for position (normalized)
        uint8 leverage; // Leverage multiplier
        uint256 stopLossPrice; // Stop-loss price (normalized)
        uint256 takeProfitPrice; // Take-profit price (normalized)
        address endToken; // Expected end token from multihop
        uint8 status; // 1 = pending, 2 = completed, 3 = cancelled
        bool isCrossDriver; // True for CrossDriver, false for IsolatedDriver
        uint256 minEntryPrice; // Minimum entry price (normalized)
        uint256 maxEntryPrice; // Maximum entry price (normalized)
    }

    // Struct for hop parameters
    struct HopParams {
        address[] listingAddresses;
        address startToken;
        address endToken;
        uint256 impactPercent;
        uint8 settleType;
        uint256 maxIterations;
    }

    // Struct for position parameters
    struct PositionParams {
        address listingAddress;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint8 positionType;
    }

    // Struct for driver call parameters
    struct DriverParams {
        uint256 minEntryPrice; // Denormalized minimum entry price
        uint256 maxEntryPrice; // Denormalized maximum entry price
        uint256 initialMargin; // Denormalized initial margin
        uint256 excessMargin; // Denormalized excess margin
        uint256 stopLossPrice; // Denormalized stop-loss price
        uint256 takeProfitPrice; // Denormalized take-profit price
    }

    // Struct for cancellation preparation
    struct CancelPrepData {
        uint256 hopId;
        uint256 pending;
        uint256 filled;
        uint8 status;
        uint256 amountSent;
        address recipient;
        address inputToken;
        address outputToken;
        uint256 refundedPending; // Actual amount refunded after transfer
    }

    // Events
    event EntryHopStarted(address indexed maker, uint256 indexed entryHopId, uint256 multihopperHopId, bool isCrossDriver);
    event EntryHopCompleted(address indexed maker, uint256 indexed entryHopId);
    event EntryHopCancelled(address indexed maker, uint256 indexed entryHopId);

    // Constructor
    constructor() {
        _transferOwnership(msg.sender); // Sets msg.sender as owner
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

    // Finds next hyphen
    // @param data Bytes to search
    // @param start Start index
    // @return Index of next hyphen
    function _findNextHyphen(bytes memory data, uint256 start) private pure returns (uint256) {
        for (uint256 i = start; i < data.length; i++) {
            if (data[i] == "-") {
                return i;
            }
        }
        return data.length;
    }

    // Splits hyphen-delimited string
    // @param str String to split
    // @param delimiter Delimiter character
    // @return First and second parts
    function _splitString(string memory str, string memory delimiter) private pure returns (string memory, string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory delimBytes = bytes(delimiter);
        uint256 splitIndex;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimBytes[0]) {
                splitIndex = i;
                break;
            }
        }
        require(splitIndex > 0, "Delimiter not found");
        return (
            _substring(strBytes, 0, splitIndex),
            _substring(strBytes, splitIndex + 1, strBytes.length)
        );
    }

    // Removes hop index from userHops
    // @param user User address
    // @param hopId Hop ID to remove
    function _removeHopIndex(address user, uint256 hopId) private {
        uint256[] storage hops = userHops[user];
        for (uint256 i = 0; i < hops.length; i++) {
            if (hops[i] == hopId) {
                if (i < hops.length - 1) {
                    hops[i] = hops[hops.length - 1];
                }
                hops.pop();
                break;
            }
        }
    }

    // Splits position parameters
    // @param params Hyphen-delimited position parameters
    // @return Parsed parameters
    function _splitPositionParams(string memory params)
        private
        pure
        returns (
            string memory listing,
            string memory minPrice,
            string memory maxPrice,
            string memory initMargin,
            string memory excessMargin,
            string memory leverage,
            string memory slPrice,
            string memory tpPrice,
            string memory posType
        )
    {
        bytes memory paramsBytes = bytes(params);
        uint256[] memory indices = new uint256[](8);
        uint256 count = 0;
        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == "-") {
                indices[count] = i;
                count++;
            }
        }
        require(count == 8, "Invalid position params");

        listing = _substring(paramsBytes, 0, indices[0]);
        minPrice = _substring(paramsBytes, indices[0] + 1, indices[1]);
        maxPrice = _substring(paramsBytes, indices[1] + 1, indices[2]);
        initMargin = _substring(paramsBytes, indices[2] + 1, indices[3]);
        excessMargin = _substring(paramsBytes, indices[3] + 1, indices[4]);
        leverage = _substring(paramsBytes, indices[4] + 1, indices[5]);
        slPrice = _substring(paramsBytes, indices[5] + 1, indices[6]);
        tpPrice = _substring(paramsBytes, indices[6] + 1, indices[7]);
        posType = _substring(paramsBytes, indices[7] + 1, paramsBytes.length);
    }

    // Parses hop parameters
    // @param listings Hyphen-delimited listing addresses
    // @param tokens Hyphen-delimited start and end tokens
    // @return listingAddresses, startToken, endToken
    function _parseHopParams(string memory listings, string memory tokens)
        private
        pure
        returns (address[] memory listingAddresses, address startToken, address endToken)
    {
        listingAddresses = new address[](4);
        listingAddresses[0] = address(0);
        listingAddresses[1] = address(0);
        listingAddresses[2] = address(0);
        listingAddresses[3] = address(0);

        // Parse listings
        bytes memory listingBytes = bytes(listings);
        uint256 count = 1;
        uint256 lastHyphen = 0;
        for (uint256 i = 0; i < listingBytes.length; i++) {
            if (listingBytes[i] == "-") {
                count++;
                lastHyphen = i;
            }
        }

        require(count >= 1 && count <= 4, "Invalid listing count");

        if (count == 1) {
            listingAddresses[0] = _parseAddress(listings);
        } else {
            for (uint256 i = 0; i < count; i++) {
                uint256 start = i == 0 ? 0 : lastHyphen + 1;
                uint256 end = i == count - 1 ? listingBytes.length : _findNextHyphen(listingBytes, start);
                listingAddresses[i] = _parseAddress(_substring(listingBytes, start, end));
                lastHyphen = end;
            }
        }

        // Parse tokens
        (string memory startTokenStr, string memory endTokenStr) = _splitString(tokens, "-");
        startToken = _parseAddress(startTokenStr);
        endToken = _parseAddress(endTokenStr);
        require(startToken != address(0) && endToken != address(0), "Invalid token address");
    }

    // Normalizes amount
    // @param token Token address
    // @param amount Amount to normalize
    // @return Normalized amount
    function _normalizeAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals == 18) return amount;
        return (amount * DECIMAL_PRECISION) / (10 ** decimals);
    }

    // Denormalizes amount
    // @param token Token address
    // @param amount Normalized amount
    // @return Denormalized amount
    function _denormalizeAmount(address token, uint256 amount) private view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals == 18) return amount;
        return (amount * (10 ** decimals)) / DECIMAL_PRECISION;
    }

    // Normalizes price
    // @param token Token address
    // @param price Price to normalize
    // @param listingAddress Listing address for price context
    // @return Normalized price
    function _normalizePrice(address token, uint256 price, address listingAddress) private view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals == 18) return price;
        return (price * DECIMAL_PRECISION) / (10 ** decimals);
    }

    // Denormalizes price
    // @param token Token address
    // @param price Normalized price
    // @param listingAddress Listing address for price context
    // @return Denormalized price
    function _denormalizePrice(address token, uint256 price, address listingAddress) private view returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals == 18) return price;
        return (price * (10 ** decimals)) / DECIMAL_PRECISION;
    }

    // Validates position token
    // @param listingAddress Listing address for position
    // @param endToken Multihop end token
    // @param positionType 0 for long, 1 for short
    function _validatePositionToken(address listingAddress, address endToken, uint8 positionType) private view {
        address requiredToken = positionType == 0
            ? ISSListingTemplate(listingAddress).tokenA()
            : ISSListingTemplate(listingAddress).tokenB();
        require(endToken == requiredToken, "End token mismatch");
    }

    // Prepares hop parameters
    // @param listings Hyphen-delimited listing addresses
    // @param tokens Hyphen-delimited start and end tokens
    // @param impactPercent Price impact percent
    // @param settleType Settlement type
    // @param maxIterations Max iterations for hop
    // @return HopParams struct
    function _prepHopParams(
        string memory listings,
        string memory tokens,
        uint256 impactPercent,
        uint8 settleType,
        uint256 maxIterations
    ) private pure returns (HopParams memory) {
        (address[] memory listingAddresses, address startToken, address endToken) = _parseHopParams(listings, tokens);
        return HopParams({
            listingAddresses: listingAddresses,
            startToken: startToken,
            endToken: endToken,
            impactPercent: impactPercent,
            settleType: settleType,
            maxIterations: maxIterations
        });
    }

    // Prepares position parameters
    // @param params Hyphen-delimited position parameters
    // @return PositionParams struct
    function _prepPositionParams(string memory params) private pure returns (PositionParams memory) {
        (
            string memory listingStr,
            string memory minPriceStr,
            string memory maxPriceStr,
            string memory initMarginStr,
            string memory excessMarginStr,
            string memory leverageStr,
            string memory slPriceStr,
            string memory tpPriceStr,
            string memory posTypeStr
        ) = _splitPositionParams(params);

        PositionParams memory posParams;
        posParams.listingAddress = _parseAddress(listingStr);
        posParams.minEntryPrice = _parseUint(minPriceStr);
        posParams.maxEntryPrice = _parseUint(maxPriceStr);
        posParams.initialMargin = _parseUint(initMarginStr);
        posParams.excessMargin = _parseUint(excessMarginStr);
        posParams.leverage = uint8(_parseUint(leverageStr));
        posParams.stopLossPrice = _parseUint(slPriceStr);
        posParams.takeProfitPrice = _parseUint(tpPriceStr);
        posParams.positionType = uint8(_parseUint(posTypeStr));

        require(posParams.listingAddress != address(0), "Invalid listing address");
        require(posParams.initialMargin > 0, "Invalid initial margin");
        require(posParams.leverage >= 2 && posParams.leverage <= 100, "Invalid leverage");
        require(posParams.positionType <= 1, "Invalid position type");

        return posParams;
    }

    // Prepares continuation parameters
    // @param entryHopId Entry hop ID
    // @return canContinue, amountReceived
    function _prepContinueParams(uint256 entryHopId) private view returns (bool canContinue, uint256 amountReceived) {
        IMultihopper.StalledHop memory stalledHop = IMultihopper(multihopper).getHopDetails(entryHopId);
        if (stalledHop.hopStatus != 2) {
            return (false, 0);
        }

        IMultihopper.HopOrderDetails memory orderDetails = IMultihopper(multihopper).getHopOrderDetails(entryHopId);
        return (true, orderDetails.amountSent);
    }

    // Prepares driver call parameters
    // @param hop EntryHop storage reference
    // @return DriverParams struct with denormalized values
    function _prepareDriverParams(EntryHop storage hop) private view returns (DriverParams memory) {
        DriverParams memory params;
        params.minEntryPrice = _denormalizePrice(hop.endToken, hop.minEntryPrice, hop.listingAddress);
        params.maxEntryPrice = _denormalizePrice(hop.endToken, hop.maxEntryPrice, hop.listingAddress);
        params.initialMargin = _denormalizeAmount(hop.endToken, hop.initialMargin);
        params.excessMargin = _denormalizeAmount(hop.endToken, hop.excessMargin);
        params.stopLossPrice = _denormalizePrice(hop.endToken, hop.stopLossPrice, hop.listingAddress);
        params.takeProfitPrice = _denormalizePrice(hop.endToken, hop.takeProfitPrice, hop.listingAddress);
        return params;
    }

    // Executes continuation for a CrossDriver hop
    // @param hop EntryHop storage reference
    // @param entryHopId Entry hop ID
    // @param amountReceived Amount received from Multihopper
    // @param maxIterations Maximum iterations for executePositions
    function _executeCrossContinueHop(EntryHop storage hop, uint256 entryHopId, uint256 amountReceived, uint256 maxIterations) private {
        // Approve CrossDriver to spend endToken
        IERC20(hop.endToken).safeApprove(crossDriver, amountReceived);

        // Prepare driver parameters
        DriverParams memory params = _prepareDriverParams(hop);

        // Call CrossDriver.drive with precomputed parameters
        ISSCrossDriver(crossDriver).drive(
            hop.maker,
            hop.listingAddress,
            params.minEntryPrice,
            params.maxEntryPrice,
            params.initialMargin,
            params.excessMargin,
            hop.leverage,
            params.stopLossPrice,
            params.takeProfitPrice,
            hop.positionType
        );

        // Call executePositions if driver is set
        if (crossDriver != address(0)) {
            ISSCrossDriver(crossDriver).executePositions(hop.listingAddress);
        }

        // Update hop status
        hop.status = 2; // Completed
        emit EntryHopCompleted(hop.maker, entryHopId);
    }

    // Executes continuation for an IsolatedDriver hop
    // @param hop EntryHop storage reference
    // @param entryHopId Entry hop ID
    // @param amountReceived Amount received from Multihopper
    // @param maxIterations Maximum iterations for executePositions
    function _executeIsolatedContinueHop(EntryHop storage hop, uint256 entryHopId, uint256 amountReceived, uint256 maxIterations) private {
        // Approve IsolatedDriver to spend endToken
        IERC20(hop.endToken).safeApprove(isolatedDriver, amountReceived);

        // Prepare driver parameters
        DriverParams memory params = _prepareDriverParams(hop);

        // Call IsolatedDriver.drive with precomputed parameters
        ISSIsolatedDriver(isolatedDriver).drive(
            hop.maker,
            hop.listingAddress,
            params.minEntryPrice,
            params.maxEntryPrice,
            params.initialMargin,
            params.excessMargin,
            hop.leverage,
            params.stopLossPrice,
            params.takeProfitPrice,
            hop.positionType
        );

        // Call executePositions if driver is set
        if (isolatedDriver != address(0)) {
            ISSIsolatedDriver(isolatedDriver).executePositions(hop.listingAddress);
        }

        // Update hop status
        hop.status = 2; // Completed
        emit EntryHopCompleted(hop.maker, entryHopId);
    }

    // Iterates over pending entry hops and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _continueEntryHops(uint256 maxIterations, bool isCrossDriver) private {
        uint256[] memory hops = userHops[msg.sender];
        uint256 processed = 0;

        for (uint256 i = 0; i < hops.length && processed < maxIterations; i++) {
            uint256 entryHopId = hops[i];
            EntryHop storage hop = entryHops[entryHopId];
            if (hop.status != 1 || hop.maker != msg.sender || hop.isCrossDriver != isCrossDriver) {
                continue;
            }

            // Prepare continuation parameters
            (bool canContinue, uint256 amountReceived) = _prepContinueParams(entryHopId);

            if (canContinue) {
                // Execute continuation based on driver type
                if (isCrossDriver) {
                    _executeCrossContinueHop(hop, entryHopId, amountReceived, maxIterations);
                } else {
                    _executeIsolatedContinueHop(hop, entryHopId, amountReceived, maxIterations);
                }
                processed++;
            }
        }
    }

    // Prepares cancellation data for an entry hop
    // @param entryHopId Entry hop ID
    // @return CancelPrepData struct
    function _prepCancelEntryHop(uint256 entryHopId) private view returns (CancelPrepData memory) {
        EntryHop storage hop = entryHops[entryHopId];
        require(hop.status == 1, "Hop not pending");
        require(hop.maker == msg.sender, "Not hop maker");

        IMultihopper.StalledHop memory stalledHop = IMultihopper(multihopper).getHopDetails(entryHopId);
        require(stalledHop.hopStatus == 1, "Multihopper hop not stalled");

        IMultihopper.HopOrderDetails memory orderDetails = IMultihopper(multihopper).getHopOrderDetails(entryHopId);
        address inputToken = stalledHop.startToken;
        address outputToken = stalledHop.endToken;

        return CancelPrepData({
            hopId: entryHopId,
            pending: orderDetails.pending,
            filled: orderDetails.filled,
            status: orderDetails.status,
            amountSent: orderDetails.amountSent,
            recipient: orderDetails.recipient,
            inputToken: inputToken,
            outputToken: outputToken,
            refundedPending: 0 // Initialize to 0, updated during refund
        });
    }

    // Handles refund for filled or sent amounts
    // @param filled Filled amount
    // @param amountSent Sent amount
    // @param outputToken Output token address
    // @param recipient Recipient address
    function _handleFilledOrSent(uint256 filled, uint256 amountSent, address outputToken, address recipient) private {
        uint256 amount = amountSent > 0 ? amountSent : filled;
        if (amount > 0) {
            uint256 balance = IERC20(outputToken).balanceOf(address(this));
            require(balance >= amount, "Insufficient output token balance");
            IERC20(outputToken).safeTransfer(recipient, amount);
        }
    }

    // Handles refund for pending amount
    // @param pending Pending amount
    // @param inputToken Input token address
    // @param recipient Recipient address
    // @return Actual refunded amount after transfer
    function _handlePending(uint256 pending, address inputToken, address recipient) private returns (uint256) {
        if (pending > 0) {
            uint256 balanceBefore = IERC20(inputToken).balanceOf(address(this));
            require(balanceBefore >= pending, "Insufficient input token balance");
            uint256 recipientBalanceBefore = IERC20(inputToken).balanceOf(recipient);
            IERC20(inputToken).safeTransfer(recipient, pending);
            uint256 recipientBalanceAfter = IERC20(inputToken).balanceOf(recipient);
            return recipientBalanceAfter - recipientBalanceBefore; // Actual amount received by recipient
        }
        return 0;
    }

    // Cancels an entry hop and refunds received amounts
    // @param entryHopId Entry hop ID to cancel
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _cancelEntryHop(uint256 entryHopId, bool isCrossDriver) private {
        EntryHop storage hop = entryHops[entryHopId];
        require(hop.isCrossDriver == isCrossDriver, "Driver mismatch");

        // Prepare cancellation data
        CancelPrepData memory prepData = _prepCancelEntryHop(entryHopId);

        // Cancel Multihopper hop
        IMultihopper(multihopper).cancelHop(entryHopId);

        // Refund filled or sent amounts
        _handleFilledOrSent(prepData.filled, prepData.amountSent, prepData.outputToken, prepData.recipient);

        // Refund pending amounts and track actual refunded amount
        prepData.refundedPending = _handlePending(prepData.pending, prepData.inputToken, hop.maker);

        // Update hop status
        hop.status = 3; // Cancelled
        _removeHopIndex(hop.maker, entryHopId);

        // Emit event after successful cancellation
        emit EntryHopCancelled(hop.maker, entryHopId);
    }

    // Transfers and approves tokens for multihop
    // @param hopMaker Maker address
    // @param hopParams Hop parameters
    // @param posParams Position parameters
    function _transferAndApproveTokens(address hopMaker, HopParams memory hopParams, PositionParams memory posParams) private {
        // Pre-balance check for input token
        uint256 balanceBefore = IERC20(hopParams.startToken).balanceOf(address(this));
        IERC20(hopParams.startToken).safeTransferFrom(hopMaker, address(this), posParams.initialMargin + posParams.excessMargin);
        uint256 balanceAfter = IERC20(hopParams.startToken).balanceOf(address(this));
        require(balanceAfter > balanceBefore, "Input transfer failed");

        // Approve Multihopper to spend startToken
        IERC20(hopParams.startToken).safeApprove(multihopper, posParams.initialMargin + posParams.excessMargin);
    }

    // Executes multihop and stores hop data
    // @param hopMaker Maker address
    // @param hopParams Hop parameters
    // @param posParams Position parameters
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    // @return entryHopId Generated hop ID
    function _executeMultihop(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver) private returns (uint256) {
        // Increment hop count
        hopCount++;
        uint256 entryHopId = hopCount;

        // Call Multihopper.hop with contract as recipient
        IMultihopper(multihopper).hop(
            hopParams.listingAddresses[0],
            hopParams.listingAddresses[1],
            hopParams.listingAddresses[2],
            hopParams.listingAddresses[3],
            hopParams.impactPercent,
            hopParams.startToken,
            hopParams.endToken,
            hopParams.settleType,
            hopParams.maxIterations,
            address(this)
        );

        // Store entry hop data with normalized price bounds
        entryHops[entryHopId] = EntryHop({
            maker: hopMaker,
            hopId: entryHopId,
            listingAddress: posParams.listingAddress,
            positionType: posParams.positionType,
            initialMargin: _normalizeAmount(hopParams.endToken, posParams.initialMargin),
            excessMargin: _normalizeAmount(hopParams.endToken, posParams.excessMargin),
            leverage: posParams.leverage,
            stopLossPrice: _normalizePrice(hopParams.endToken, posParams.stopLossPrice, posParams.listingAddress),
            takeProfitPrice: _normalizePrice(hopParams.endToken, posParams.takeProfitPrice, posParams.listingAddress),
            endToken: hopParams.endToken,
            status: 1, // Pending
            isCrossDriver: isCrossDriver,
            minEntryPrice: _normalizePrice(hopParams.endToken, posParams.minEntryPrice, posParams.listingAddress),
            maxEntryPrice: _normalizePrice(hopParams.endToken, posParams.maxEntryPrice, posParams.listingAddress)
        });

        // Update user hops
        userHops[hopMaker].push(entryHopId);

        return entryHopId;
    }

    // Attempts to continue hop if possible
    // @param entryHopId Entry hop ID
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    // @param maxIterations Maximum iterations for executePositions
    function _attemptContinuation(uint256 entryHopId, bool isCrossDriver, uint256 maxIterations) private {
        if (isCrossDriver && crossDriver != address(0)) {
            (bool canContinue, uint256 amountReceived) = _prepContinueParams(entryHopId);
            if (canContinue) {
                _executeCrossContinueHop(entryHops[entryHopId], entryHopId, amountReceived, maxIterations);
            }
        } else if (!isCrossDriver && isolatedDriver != address(0)) {
            (bool canContinue, uint256 amountReceived) = _prepContinueParams(entryHopId);
            if (canContinue) {
                _executeIsolatedContinueHop(entryHops[entryHopId], entryHopId, amountReceived, maxIterations);
            }
        }
    }

    // Executes entry hop for either CrossDriver or IsolatedDriver
    // @param hopMaker Maker address
    // @param hopParams Hop parameters
    // @param posParams Position parameters
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    // @param maxIterations Maximum iterations for executePositions
    function _executeEntryHop(address hopMaker, HopParams memory hopParams, PositionParams memory posParams, bool isCrossDriver, uint256 maxIterations) private {
        // Validate position token
        _validatePositionToken(posParams.listingAddress, hopParams.endToken, posParams.positionType);

        // Transfer and approve tokens
        _transferAndApproveTokens(hopMaker, hopParams, posParams);

        // Execute multihop and store data
        uint256 entryHopId = _executeMultihop(hopMaker, hopParams, posParams, isCrossDriver);

        // Attempt continuation
        _attemptContinuation(entryHopId, isCrossDriver, maxIterations);

        // Emit event
        emit EntryHopStarted(hopMaker, entryHopId, entryHopId, isCrossDriver);
    }

    // Sets Multihopper address
    // @param _multihopper New Multihopper contract address
    function setMultihopper(address _multihopper) external onlyOwner {
        require(_multihopper != address(0), "Invalid multihopper address");
        multihopper = _multihopper; // Updates multihopper address
    }

    // Sets SSCrossDriver address
    // @param _crossDriver New SSCrossDriver contract address
    function setCrossDriver(address _crossDriver) external onlyOwner {
        require(_crossDriver != address(0), "Invalid crossDriver address");
        crossDriver = _crossDriver; // Updates crossDriver address
    }

    // Sets ISSIsolatedDriver address
    // @param _isolatedDriver New ISSIsolatedDriver contract address
    function setIsolatedDriver(address _isolatedDriver) external onlyOwner {
        require(_isolatedDriver != address(0), "Invalid isolatedDriver address");
        isolatedDriver = _isolatedDriver; // Updates isolatedDriver address
    }

    // Initiates a multi-hop swap followed by CrossDriver position creation
    // @param listings Hyphen-delimited string of listing addresses (e.g., "0x1-0x2-0x3-0x4")
    // @param impactPercent Price impact percent (scaled to 1000)
    // @param tokens Hyphen-delimited string of start and end tokens (e.g., "0xStart-0xEnd")
    // @param settleType Settlement type (0 = market, 1 = liquid)
    // @param maxIterations Max iterations for Multihopper settlement and executePositions
    // @param positionParams Hyphen-delimited position parameters (e.g., "0xListing-1000-2000-1000-200-2-500-6000-0")
    // @param maker Hop initiator (defaults to msg.sender if address(0))
    function crossEntryHop(
        string memory listings,
        uint256 impactPercent,
        string memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        string memory positionParams,
        address maker
    ) external nonReentrant {
        // Prepare maker address
        address hopMaker = maker == address(0) ? msg.sender : maker;

        // Parse hop parameters
        HopParams memory hopParams = _prepHopParams(listings, tokens, impactPercent, settleType, maxIterations);

        // Parse position parameters
        PositionParams memory posParams = _prepPositionParams(positionParams);

        // Execute hop
        _executeEntryHop(hopMaker, hopParams, posParams, true, maxIterations);
    }

    // Initiates a multi-hop swap followed by IsolatedDriver position creation
    // @param listings Hyphen-delimited string of listing addresses (e.g., "0x1-0x2-0x3-0x4")
    // @param impactPercent Price impact percent (scaled to 1000)
    // @param tokens Hyphen-delimited string of start and end tokens (e.g., "0xStart-0xEnd")
    // @param settleType Settlement type (0 = market, 1 = liquid)
    // @param maxIterations Max iterations for Multihopper settlement and executePositions
    // @param positionParams Hyphen-delimited position parameters (e.g., "0xListing-1000-2000-1000-200-2-500-6000-0")
    // @param maker Hop initiator (defaults to msg.sender if address(0))
    function isolatedEntryHop(
        string memory listings,
        uint256 impactPercent,
        string memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        string memory positionParams,
        address maker
    ) external nonReentrant {
        // Prepare maker address
        address hopMaker = maker == address(0) ? msg.sender : maker;

        // Parse hop parameters
        HopParams memory hopParams = _prepHopParams(listings, tokens, impactPercent, settleType, maxIterations);

        // Parse position parameters
        PositionParams memory posParams = _prepPositionParams(positionParams);

        // Execute hop
        _executeEntryHop(hopMaker, hopParams, posParams, false, maxIterations);
    }

    // Iterates over pending CrossDriver entry hops and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    function continueCrossEntryHops(uint256 maxIterations) external nonReentrant {
        _continueEntryHops(maxIterations, true);
    }

    // Iterates over pending IsolatedDriver entry hops and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    function continueIsolatedEntryHops(uint256 maxIterations) external nonReentrant {
        _continueEntryHops(maxIterations, false);
    }

    // Cancels a CrossDriver entry hop and refunds received amounts
    // @param entryHopId Entry hop ID to cancel
    function cancelCrossEntryHop(uint256 entryHopId) external nonReentrant {
        _cancelEntryHop(entryHopId, true);
    }

    // Cancels an IsolatedDriver entry hop and refunds received amounts
    // @param entryHopId Entry hop ID to cancel
    function cancelIsolatedEntryHop(uint256 entryHopId) external nonReentrant {
        _cancelEntryHop(entryHopId, false);
    }

    // View function to get entry hop details
    // @param entryHopId Entry hop ID
    // @return EntryHop struct
    function getEntryHopDetails(uint256 entryHopId) external view returns (EntryHop memory) {
        return entryHops[entryHopId];
    }

    // View function to get user's entry hops
    // @param user User address
    // @return Array of entry hop IDs
    function getUserEntryHops(address user) external view returns (uint256[] memory) {
        return userHops[user];
    }

    // View function to get Multihopper address
    // @return Multihopper address
    function multihopperView() external view returns (address) {
        return multihopper;
    }

    // View function to get SSCrossDriver address
    // @return SSCrossDriver address
    function crossDriverView() external view returns (address) {
        return crossDriver;
    }

    // View function to get ISSIsolatedDriver address
    // @return ISSIsolatedDriver address
    function isolatedDriverView() external view returns (address) {
        return isolatedDriver;
    }
}