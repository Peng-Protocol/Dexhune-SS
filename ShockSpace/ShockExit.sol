// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version 0.0.58: Added executeCrossExitHops and executeIsolatedExitHops for global pending hop processing
// - Introduced executeCrossExitHops and executeIsolatedExitHops to process up to maxIterations pending hops across all users
// - Modified _continueExitHops to accept a user parameter for reusability
// - Added _executeGlobalExitHops to iterate over all users' hops using hopCount and exitHops
// - Preserved all functionality from version 0.0.57 (stack overflow fix in _initiateMultihop)
// - Maintained modularity, graceful degradation, and adherence to style guide

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
    ) external returns (uint256);

    function cancelHop(uint256 hopId) external;
    function continueHop(uint256 maxIterations) external;
    function getHopOrderDetails(uint256 hopId) external view returns (HopOrderDetails memory);
    function getHopDetails(uint256 hopId) external view returns (StalledHop memory);
}

// Interface for SSCrossDriver contract
interface ISSCrossDriver {
    function drift(uint256 positionId, address maker) external;
}

// Interface for ISSIsolatedDriver contract
interface ISSIsolatedDriver {
    function drift(uint256 positionId, address maker) external;
}

// Interface for SSListingTemplate contract
interface ISSListingTemplate {
    struct LongPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 required;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }

    struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount;
        uint256 filled;
        uint256 orderId;
        uint8 status;
    }

    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    function getNextOrderId() external view returns (uint256);
    function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory);
    function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory);
    function settleLongLiquid(address listingAddress, uint256 maxIterations) external;
    function settleShortLiquid(address listingAddress, uint256 maxIterations) external;
    function settleLongPayouts(address listingAddress, uint256 maxIterations) external;
    function settleShortPayouts(address listingAddress, uint256 maxIterations) external;
}

// ShockExit contract for closing positions and initiating multi-hop swaps
contract ShockExit is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constant for decimal precision
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // State variables (hidden, accessed via view functions)
    address private crossDriver; // Address of SSCrossDriver contract
    address private isolatedDriver; // Address of ISSIsolatedDriver contract
    address private multihopper; // Address of Multihopper contract
    uint256 private hopCount; // Tracks total number of exit hops
    mapping(address => uint256[]) private userHops; // Maps user to their exit hop IDs
    mapping(uint256 => ExitHop) private exitHops; // Maps hop ID to exit hop details

    // Struct for exit hop details
    struct ExitHop {
        address maker; // Hop initiator
        uint256 multihopId; // Multihopper hop ID
        uint256 positionId; // Position ID to close
        address listingAddress; // Listing for position closure
        uint8 positionType; // 0 for long, 1 for short
        uint256 payoutOrderId; // Order ID of payout from drift
        address startToken; // Token received from position closure
        address endToken; // Expected end token from multihop
        uint8 settleType; // 0 = market, 1 = liquid
        uint8 status; // 0 = initializing, 1 = pending, 2 = completed, 3 = cancelled
        bool isCrossDriver; // True for CrossDriver, false for IsolatedDriver
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
        uint256 positionId;
        uint8 positionType;
    }

    // Events
    event ExitHopStarted(address indexed maker, uint256 indexed exitHopId, uint256 multihopId, bool isCrossDriver);
    event ExitHopCompleted(address indexed maker, uint256 indexed exitHopId);
    event ExitHopCancelled(address indexed maker, uint256 indexed exitHopId);

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
            string memory positionId,
            string memory positionType
        )
    {
        bytes memory paramsBytes = bytes(params);
        uint256[] memory indices = new uint256[](2);
        uint256 count = 0;
        for (uint256 i = 0; i < paramsBytes.length; i++) {
            if (paramsBytes[i] == "-") {
                indices[count] = i;
                count++;
            }
        }
        require(count == 2, "Invalid position params");

        listing = _substring(paramsBytes, 0, indices[0]);
        positionId = _substring(paramsBytes, indices[0] + 1, indices[1]);
        positionType = _substring(paramsBytes, indices[1] + 1, paramsBytes.length);
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

    // Validates position token
    // @param listingAddress Listing address for position
    // @param startToken Multihop start token
    // @param positionType 0 for long, 1 for short
    function _validatePositionToken(address listingAddress, address startToken, uint8 positionType) private view {
        address requiredToken = positionType == 0
            ? ISSListingTemplate(listingAddress).tokenB() // Long payout in tokenB
            : ISSListingTemplate(listingAddress).tokenA(); // Short payout in tokenA
        require(startToken == requiredToken, "Start token mismatch");
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
            string memory positionIdStr,
            string memory positionTypeStr
        ) = _splitPositionParams(params);

        PositionParams memory posParams;
        posParams.listingAddress = _parseAddress(listingStr);
        posParams.positionId = _parseUint(positionIdStr);
        posParams.positionType = uint8(_parseUint(positionTypeStr));

        require(posParams.listingAddress != address(0), "Invalid listing address");
        require(posParams.positionType <= 1, "Invalid position type");

        return posParams;
    }

    // Prepares continuation parameters
    // @param exitHopId Exit hop ID
    // @return canContinue, amountReceived
    function _prepContinueParams(uint256 exitHopId) private view returns (bool canContinue, uint256 amountReceived) {
        IMultihopper.StalledHop memory stalledHop = IMultihopper(multihopper).getHopDetails(exitHops[exitHopId].multihopId);
        if (stalledHop.hopStatus != 2) {
            return (false, 0);
        }

        IMultihopper.HopOrderDetails memory orderDetails = IMultihopper(multihopper).getHopOrderDetails(exitHops[exitHopId].multihopId);
        return (true, orderDetails.amountSent);
    }

    // Executes continuation for a CrossDriver hop
    // @param hop ExitHop storage reference
    // @param exitHopId Exit hop ID
    // @param amountReceived Amount received from Multihopper
    function _executeCrossContinueHop(ExitHop storage hop, uint256 exitHopId, uint256 amountReceived) private {
        // Transfer end token to maker
        IERC20(hop.endToken).safeTransfer(hop.maker, amountReceived);

        // Update hop status
        hop.status = 2; // Completed
        emit ExitHopCompleted(hop.maker, exitHopId);
    }

    // Executes continuation for an IsolatedDriver hop
    // @param hop ExitHop storage reference
    // @param exitHopId Exit hop ID
    // @param amountReceived Amount received from Multihopper
    function _executeIsolatedContinueHop(ExitHop storage hop, uint256 exitHopId, uint256 amountReceived) private {
        // Transfer end token to maker
        IERC20(hop.endToken).safeTransfer(hop.maker, amountReceived);

        // Update hop status
        hop.status = 2; // Completed
        emit ExitHopCompleted(hop.maker, exitHopId);
    }

    // Iterates over a user's pending exit hops and attempts to continue them
    // @param user User address whose hops to process
    // @param maxIterations Maximum number of hops to process
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _continueExitHops(address user, uint256 maxIterations, bool isCrossDriver) private {
        require(maxIterations > 0, "Zero max iterations");
        uint256[] memory hops = userHops[user];
        uint256 processed = 0;

        for (uint256 i = 0; i < hops.length && processed < maxIterations; i++) {
            uint256 exitHopId = hops[i];
            ExitHop storage hop = exitHops[exitHopId];
            if (hop.status != 1 || hop.isCrossDriver != isCrossDriver) {
                continue;
            }

            // Attempt to settle position closure
            if (hop.settleType == 0) {
                // Market settlement
                if (hop.positionType == 0) {
                    ISSListingTemplate(hop.listingAddress).settleLongPayouts(hop.listingAddress, maxIterations);
                } else {
                    ISSListingTemplate(hop.listingAddress).settleShortPayouts(hop.listingAddress, maxIterations);
                }
            } else {
                // Liquid settlement
                if (hop.positionType == 0) {
                    ISSListingTemplate(hop.listingAddress).settleLongLiquid(hop.listingAddress, maxIterations);
                } else {
                    ISSListingTemplate(hop.listingAddress).settleShortLiquid(hop.listingAddress, maxIterations);
                }
            }

            // Check payout status
            uint256 amountReceived;
            if (hop.positionType == 0) {
                ISSListingTemplate.LongPayoutStruct memory payout = ISSListingTemplate(hop.listingAddress).getLongPayout(hop.payoutOrderId);
                if (payout.status != 3) { // Not filled
                    continue;
                }
                amountReceived = payout.filled;
            } else {
                ISSListingTemplate.ShortPayoutStruct memory payout = ISSListingTemplate(hop.listingAddress).getShortPayout(hop.payoutOrderId);
                if (payout.status != 3) { // Not filled
                    continue;
                }
                amountReceived = payout.filled;
            }

            // Validate start token
            _validatePositionToken(hop.listingAddress, hop.startToken, hop.positionType);

            // Approve Multihopper to spend startToken
            IERC20(hop.startToken).safeApprove(multihopper, amountReceived);

            // Attempt multihop continuation
            try IMultihopper(multihopper).continueHop(maxIterations) {
                // Check multihop status
                (bool canContinue, uint256 finalAmount) = _prepContinueParams(exitHopId);
                if (canContinue) {
                    if (isCrossDriver) {
                        _executeCrossContinueHop(hop, exitHopId, finalAmount);
                    } else {
                        _executeIsolatedContinueHop(hop, exitHopId, finalAmount);
                    }
                    processed++;
                }
            } catch {
                // Refund and cancel if continueHop fails
                IERC20(hop.startToken).safeTransfer(hop.maker, amountReceived);
                hop.status = 3; // Cancelled
                _removeHopIndex(hop.maker, exitHopId);
                emit ExitHopCancelled(hop.maker, exitHopId);
            }
        }
    }

    // Iterates over all pending exit hops globally and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _executeGlobalExitHops(uint256 maxIterations, bool isCrossDriver) private {
        require(maxIterations > 0, "Zero max iterations");
        uint256 processed = 0;

        for (uint256 exitHopId = 1; exitHopId <= hopCount && processed < maxIterations; exitHopId++) {
            ExitHop storage hop = exitHops[exitHopId];
            if (hop.status != 1 || hop.isCrossDriver != isCrossDriver) {
                continue;
            }

            // Process hops for the user
            _continueExitHops(hop.maker, maxIterations, isCrossDriver);
            processed++;
        }
    }

    // Cancels an exit hop before multihop initiation
    // @param exitHopId Exit hop ID to cancel
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _cancelExitHop(uint256 exitHopId, bool isCrossDriver) private {
        ExitHop storage hop = exitHops[exitHopId];
        require(hop.status == 0, "Hop already in Multihopper");
        require(hop.maker == msg.sender, "Not hop maker");
        require(hop.isCrossDriver == isCrossDriver, "Driver mismatch");

        // Update hop status
        hop.status = 3; // Cancelled
        _removeHopIndex(hop.maker, exitHopId);
        emit ExitHopCancelled(hop.maker, exitHopId);
    }

    // Initiates drift to close position
    // @param posParams Position parameters
    // @param hopMaker Maker address
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    // @return payoutOrderId Order ID for payout
    function _initiateDrift(
        PositionParams memory posParams,
        address hopMaker,
        bool isCrossDriver
    ) private returns (uint256) {
        uint256 payoutOrderId = ISSListingTemplate(posParams.listingAddress).getNextOrderId();
        if (isCrossDriver) {
            ISSCrossDriver(crossDriver).drift(posParams.positionId, hopMaker);
        } else {
            ISSIsolatedDriver(isolatedDriver).drift(posParams.positionId, hopMaker);
        }
        return payoutOrderId;
    }

    // Settles payout based on settlement type and position type
    // @param posParams Position parameters
    // @param hopParams Hop parameters
    function _settlePayout(
        PositionParams memory posParams,
        HopParams memory hopParams
    ) private {
        ISSListingTemplate listing = ISSListingTemplate(posParams.listingAddress);
        if (hopParams.settleType == 0) {
            // Market settlement
            if (posParams.positionType == 0) {
                listing.settleLongPayouts(posParams.listingAddress, hopParams.maxIterations);
            } else {
                listing.settleShortPayouts(posParams.listingAddress, hopParams.maxIterations);
            }
        } else {
            // Liquid settlement
            if (posParams.positionType == 0) {
                listing.settleLongLiquid(posParams.listingAddress, hopParams.maxIterations);
            } else {
                listing.settleShortLiquid(posParams.listingAddress, hopParams.maxIterations);
            }
        }
    }

    // Checks payout status and retrieves amount
    // @param posParams Position parameters
    // @param payoutOrderId Order ID for payout
    // @return startToken, amountReceived
    function _checkPayout(
        PositionParams memory posParams,
        uint256 payoutOrderId
    ) private view returns (address startToken, uint256 amountReceived) {
        ISSListingTemplate listing = ISSListingTemplate(posParams.listingAddress);
        startToken = posParams.positionType == 0
            ? listing.tokenB()
            : listing.tokenA();
        
        if (posParams.positionType == 0) {
            ISSListingTemplate.LongPayoutStruct memory payout = listing.getLongPayout(payoutOrderId);
            require(payout.status == 3, "Payout not filled");
            amountReceived = payout.filled;
        } else {
            ISSListingTemplate.ShortPayoutStruct memory payout = listing.getShortPayout(payoutOrderId);
            require(payout.status == 3, "Payout not filled");
            amountReceived = payout.filled;
        }
    }

    // Calls IMultihopper.hop and returns the multihop ID
    // @param hopParams Hop parameters
    // @param startToken Start token for multihop
    // @param hopMaker Maker address
    // @return multihopId Multihopper hop ID or 0 if failed
    function _callMultihop(
        HopParams memory hopParams,
        address startToken,
        address hopMaker
    ) private returns (uint256 multihopId) {
        try IMultihopper(multihopper).hop(
            hopParams.listingAddresses[0],
            hopParams.listingAddresses[1],
            hopParams.listingAddresses[2],
            hopParams.listingAddresses[3],
            hopParams.impactPercent,
            startToken,
            hopParams.endToken,
            hopParams.settleType,
            hopParams.maxIterations,
            hopMaker
        ) returns (uint256 _multihopId) {
            return _multihopId;
        } catch {
            return 0;
        }
    }

    // Initiates multihop and stores hop data
    // @param hopMaker Maker address
    // @param hopParams Hop parameters
    // @param posParams Position parameters
    // @param payoutOrderId Order ID for payout
    // @param startToken Start token for multihop
    // @param amountReceived Amount received from payout
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _initiateMultihop(
        address hopMaker,
        HopParams memory hopParams,
        PositionParams memory posParams,
        uint256 payoutOrderId,
        address startToken,
        uint256 amountReceived,
        bool isCrossDriver
    ) private {
        // Increment hop count
        hopCount++;
        uint256 exitHopId = hopCount;

        // Store exit hop data with initializing status
        exitHops[exitHopId] = ExitHop({
            maker: hopMaker,
            multihopId: 0, // Will be set after successful hop
            positionId: posParams.positionId,
            listingAddress: posParams.listingAddress,
            positionType: posParams.positionType,
            payoutOrderId: payoutOrderId,
            startToken: startToken,
            endToken: hopParams.endToken,
            settleType: hopParams.settleType,
            status: 0, // Initializing
            isCrossDriver: isCrossDriver
        });

        // Update user hops
        userHops[hopMaker].push(exitHopId);

        // Approve Multihopper to spend startToken
        IERC20(startToken).safeApprove(multihopper, amountReceived);

        // Attempt multihop
        uint256 multihopId = _callMultihop(hopParams, startToken, hopMaker);
        if (multihopId != 0) {
            // Multihop initiated, store multihopId and update status
            exitHops[exitHopId].multihopId = multihopId;
            exitHops[exitHopId].status = 1; // Pending
            emit ExitHopStarted(hopMaker, exitHopId, multihopId, isCrossDriver);
        } else {
            // Refund and cancel if multihop fails
            IERC20(startToken).safeTransfer(hopMaker, amountReceived);
            _cancelExitHop(exitHopId, isCrossDriver);
        }
    }

    // Executes exit hop for either CrossDriver or IsolatedDriver
    // @param hopMaker Maker address
    // @param hopParams Hop parameters
    // @param posParams Position parameters
    // @param isCrossDriver True for CrossDriver, false for IsolatedDriver
    function _executeExitHop(
        address hopMaker,
        HopParams memory hopParams,
        PositionParams memory posParams,
        bool isCrossDriver
    ) private {
        // Initiate drift to close position
        uint256 payoutOrderId = _initiateDrift(posParams, hopMaker, isCrossDriver);

        // Settle payout
        _settlePayout(posParams, hopParams);

        // Check payout status and get amount
        (address startToken, uint256 amountReceived) = _checkPayout(posParams, payoutOrderId);

        // Validate start token
        _validatePositionToken(posParams.listingAddress, startToken, posParams.positionType);

        // Initiate multihop
        _initiateMultihop(hopMaker, hopParams, posParams, payoutOrderId, startToken, amountReceived, isCrossDriver);
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

    // Initiates a position closure followed by CrossDriver multihop
    // @param listings Hyphen-delimited string of listing addresses (e.g., "0x1-0x2-0x3-0x4")
    // @param impactPercent Price impact percent (scaled to 1000)
    // @param tokens Hyphen-delimited string of start and end tokens (e.g., "0xStart-0xEnd")
    // @param settleType Settlement type (0 = market, 1 = liquid)
    // @param maxIterations Max iterations for Multihopper settlement
    // @param positionParams Hyphen-delimited position parameters (e.g., "0xListing-123-0")
    // @param maker Hop initiator (defaults to msg.sender if address(0))
    function crossExitHop(
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
        _executeExitHop(hopMaker, hopParams, posParams, true);
    }

    // Initiates a position closure followed by IsolatedDriver multihop
    // @param listings Hyphen-delimited string of listing addresses (e.g., "0x1-0x2-0x3-0x4")
    // @param impactPercent Price impact percent (scaled to 1000)
    // @param tokens Hyphen-delimited string of start and end tokens (e.g., "0xStart-0xEnd")
    // @param settleType Settlement type (0 = market, 1 = liquid)
    // @param maxIterations Max iterations for Multihopper settlement
    // @param positionParams Hyphen-delimited position parameters (e.g., "0xListing-123-0")
    // @param maker Hop initiator (defaults to msg.sender if address(0))
    function isolatedExitHop(
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
        _executeExitHop(hopMaker, hopParams, posParams, false);
    }

    // Iterates over a user's pending CrossDriver exit hops and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    function continueCrossExitHops(uint256 maxIterations) external nonReentrant {
        _continueExitHops(msg.sender, maxIterations, true);
    }

    // Iterates over a user's pending IsolatedDriver exit hops and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    function continueIsolatedExitHops(uint256 maxIterations) external nonReentrant {
        _continueExitHops(msg.sender, maxIterations, false);
    }

    // Iterates over all pending CrossDriver exit hops globally and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    function executeCrossExitHops(uint256 maxIterations) external nonReentrant {
        _executeGlobalExitHops(maxIterations, true);
    }

    // Iterates over all pending IsolatedDriver exit hops globally and attempts to continue them
    // @param maxIterations Maximum number of hops to process
    function executeIsolatedExitHops(uint256 maxIterations) external nonReentrant {
        _executeGlobalExitHops(maxIterations, false);
    }

    // View function to get exit hop details
    // @param exitHopId Exit hop ID
    // @return ExitHop struct
    function getExitHopDetails(uint256 exitHopId) external view returns (ExitHop memory) {
        return exitHops[exitHopId];
    }

    // View function to get user's exit hops
    // @param user User address
    // @return Array of exit hop IDs
    function getUserExitHops(address user) external view returns (uint256[] memory) {
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