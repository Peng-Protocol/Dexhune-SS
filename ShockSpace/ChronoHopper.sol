// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version: 0.0.51
// Change Log:
// - 2025-07-06: Updated to v0.0.51, fixed fee payment in processChronoHopStep to transfer feeAmount to msg.sender (caller of executeHops/continueChronoHop) instead of hopMaker.
// - Previous (v0.0.50): Split prepChronoHop into computeListings, computeTokens, computeHopSettings to fix stack too deep.
// - Previous (v0.0.49): Fixed stack too deep in prepChronoHop with internal call tree, reduced validation to rely on IMultihopper.
// - Previous (v0.0.48): Fixed validateChronoHopRequest to view from pure for block.timestamp access.
// - Previous (v0.0.47): Inlined minimal IMultihopper interface, renamed hop to chronoHop, continueHop to continueChronoHop.
// - Retained pre/post balance checks, try-catch for IMultihopper.hop, chrono naming, compatibility with IMultihopper v0.0.2.

import "./imports/Ownable.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

// Minimal IMultihopper interface with only used functions
interface IMultihopper {
    struct HopOrderDetails {
        uint256 pending; // Pending amount in input token
        uint256 filled; // Filled amount in input token
        uint8 status; // Order status (1 = active, 2 = partially filled, 3 = completed)
        uint256 amountSent; // Amount sent in output token
        address recipient; // Recipient of the output tokens
    }

    struct HopRouteData {
        address[] listings; // Ordered list of listing addresses
        bool[] isBuy; // Buy/sell flags for each listing
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
    ) external payable returns (uint256);

    function getHopOrderDetails(uint256 hopId) external view returns (HopOrderDetails memory);

    function getHopRoute(uint256 hopId) external view returns (HopRouteData memory);
}

contract ChronoHopper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct StalledChronoHop {
        uint8 stage; // Current stage of the hop
        address currentListing; // Current listing being processed
        uint256 orderID; // Order ID for the current listing (unused, kept for compatibility)
        uint256 minPrice; // Minimum price limit for sell orders (unused, kept for compatibility)
        uint256 maxPrice; // Maximum price limit for buy orders (unused, kept for compatibility)
        address hopMaker; // Address that initiated the hop
        address[] remainingListings; // Remaining listings in the route
        uint256 principalAmount; // Current principal amount held in custody
        address startToken; // Starting token for the hop
        address endToken; // Ending token for the hop
        uint8 settleType; // Settlement type (0 = market, 1 = liquid)
        uint8 hopStatus; // Hop status (1 = active, 2 = completed/canceled)
        uint256 maxIterations; // Maximum iterations for settlement
        uint256 timestamp; // Execution timestamp
        uint256 feeAmount; // 0.05% fee in input token
        uint256[] impactPricePercents; // Impact percents for each listing
        uint256 multiHopId; // Hop ID from IMultihopper
    }

    struct ChronoHopPrepData {
        uint256 hopId; // Unique identifier for the ChronoHop
        uint256[] indices; // Ordered indices of listings
        bool[] isBuy; // Buy/sell flags for each listing
        address currentToken; // Current token in the hop
        uint256 principal; // Principal amount after fee deduction
        uint256 timestamp; // Execution timestamp
        uint256 feeAmount; // 0.05% fee in input token
        uint256[] impactPricePercents; // Impact percents for each listing
        address maker; // Effective maker address
    }

    struct ChronoHopOrderDetails {
        uint256 pending; // Pending amount in input token
        uint256 filled; // Filled amount in input token
        uint8 status; // Order status (1 = active, 2 = partially filled, 3 = completed)
        uint256 amountSent; // Amount sent in output token
        address recipient; // Recipient of the output tokens
    }

    struct ChronoHopRouteData {
        address[] listings; // Ordered list of listing addresses
        bool[] isBuy; // Buy/sell flags for each listing
    }

    address private _multiHopper; // Hidden IMultihopper address
    mapping(uint256 => StalledChronoHop) private chronoHopID; // Hidden hop storage
    mapping(address => uint256[]) private chronoHopsByAddress; // Hidden user hop list
    mapping(uint256 => bool) private isChronoHop; // Flags time-based hops
    uint256[] private totalChronoHops; // Hidden global hop list
    uint256 private nextChronoHopId; // Hidden hop ID counter
    uint256 private constant FEE_BASIS_POINTS = 5; // 0.05% fee (5/10000)

    event ChronoHopStarted(uint256 indexed hopId, address indexed maker, uint256 numListings, uint256 timestamp);
    event ChronoHopContinued(uint256 indexed hopId, uint8 newStage);
    event ChronoHopCanceled(uint256 indexed hopId);
    event AllChronoHopsCanceled(address indexed maker, uint256 count);
    event FeePaid(address indexed recipient, address token, uint256 amount);
    event MultiHopperSet(address indexed multiHopper);

    modifier onlyValidListing(address listingAddress) {
        require(listingAddress != address(0), "Invalid listing");
        _;
    }

    function setMultiHopper(address multiHopper) external onlyOwner {
        // Sets the IMultihopper contract address for hop execution
        require(multiHopper != address(0), "Invalid MultiHopper address");
        _multiHopper = multiHopper;
        emit MultiHopperSet(multiHopper);
    }

    function multiHopperView() external view returns (address) {
        // Returns the IMultihopper contract address
        return _multiHopper;
    }

    function getTokenDecimals(address token) internal view returns (uint8) {
        // Returns decimals for a token, defaulting to 18 for native currency
        if (token == address(0)) return 18;
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return decimals;
    }

    function denormalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        // Converts normalized amount to token-specific decimals
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return amount * (10 ** decimals);
    }

    function normalizeForToken(uint256 amount, address token) internal view returns (uint256) {
        // Converts token-specific amount to normalized form
        if (token == address(0)) return amount;
        uint256 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return amount / (10 ** decimals);
    }

    function _checkTransfer(address token, address from, address to, uint256 amount) internal returns (uint256) {
        // Verifies token transfer success by checking balance changes
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

    function validateChronoHopRequest(address listing1, uint256 timestamp) internal view {
        // Validates minimal ChronoHop parameters, deferring others to IMultihopper
        require(listing1 != address(0), "First listing required");
        require(timestamp >= block.timestamp, "Timestamp in past");
    }

    function computeListings(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent
    ) internal pure returns (address[] memory listings, uint256[] memory impactPricePercents, uint256 numListings) {
        // Computes listing array and impact percents for ChronoHop
        numListings = 1;
        if (listing2 != address(0)) numListings++;
        if (listing3 != address(0)) numListings++;
        if (listing4 != address(0)) numListings++;
        listings = new address[](numListings);
        impactPricePercents = new uint256[](numListings);
        listings[0] = listing1;
        impactPricePercents[0] = impactPercent;
        if (numListings >= 2) {
            listings[1] = listing2;
            impactPricePercents[1] = impactPercent;
        }
        if (numListings >= 3) {
            listings[2] = listing3;
            impactPricePercents[2] = impactPercent;
        }
        if (numListings == 4) {
            listings[3] = listing4;
            impactPricePercents[3] = impactPercent;
        }
    }

    function computeTokens(
        address startToken,
        uint256 numListings
    ) internal view returns (uint256 principal, uint256 feeAmount, uint256[] memory indices, bool[] memory isBuy) {
        // Computes token-related parameters and arrays
        principal = startToken == address(0) ? msg.value : 0;
        feeAmount = (principal * FEE_BASIS_POINTS) / 10000; // 0.05% fee
        require(principal > feeAmount, "Principal too low for fee");
        indices = new uint256[](numListings);
        isBuy = new bool[](numListings);
        for (uint256 i = 0; i < numListings; i++) {
            indices[i] = i;
            isBuy[i] = false; // Set by IMultihopper
        }
    }

    function computeHopSettings(
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp,
        address maker,
        uint256 numListings
    ) internal view returns (ChronoHopPrepData memory prepData) {
        // Assembles final ChronoHopPrepData with hop settings
        (uint256 principal, uint256 feeAmount, uint256[] memory indices, bool[] memory isBuy) = computeTokens(startToken, numListings);
        prepData = ChronoHopPrepData({
            hopId: nextChronoHopId,
            indices: indices,
            isBuy: isBuy,
            currentToken: startToken,
            principal: principal - feeAmount,
            timestamp: timestamp,
            feeAmount: feeAmount,
            impactPricePercents: new uint256[](numListings), // Set by computeListings
            maker: maker
        });
    }

    function prepChronoHop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp,
        address maker
    ) internal view returns (ChronoHopPrepData memory) {
        // Prepares ChronoHop data using parameter-specific helpers
        validateChronoHopRequest(listing1, timestamp);
        (address[] memory listings, uint256[] memory impactPricePercents, uint256 numListings) = computeListings(
            listing1, listing2, listing3, listing4, impactPercent
        );
        ChronoHopPrepData memory prepData = computeHopSettings(startToken, endToken, settleType, maxIterations, timestamp, maker, numListings);
        prepData.impactPricePercents = impactPricePercents;
        return prepData;
    }

    function initializeChronoHopData(
        address[] memory listings,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        uint256 timestamp,
        ChronoHopPrepData memory prepData
    ) internal {
        // Initializes ChronoHop data in chronoHopID mapping
        address[] memory orderedListings = new address[](prepData.indices.length);
        for (uint256 i = 0; i < prepData.indices.length; i++) {
            orderedListings[i] = listings[prepData.indices[i]];
        }
        chronoHopID[prepData.hopId] = StalledChronoHop({
            stage: 0,
            currentListing: orderedListings[0],
            orderID: 0,
            minPrice: 0,
            maxPrice: 0,
            hopMaker: prepData.maker,
            remainingListings: orderedListings,
            principalAmount: prepData.principal,
            startToken: startToken,
            endToken: endToken,
            settleType: settleType,
            hopStatus: 1,
            maxIterations: maxIterations,
            timestamp: timestamp,
            feeAmount: prepData.feeAmount,
            impactPricePercents: prepData.impactPricePercents,
            multiHopId: 0
        });
        isChronoHop[prepData.hopId] = true;
        chronoHopsByAddress[prepData.maker].push(prepData.hopId);
        totalChronoHops.push(prepData.hopId);
    }

    function executeChronoHop(
        address listing1,
        address listing2,
        address listing3,
        address listing4,
        uint256 impactPercent,
        address startToken,
        address endToken,
        uint8 settleType,
        uint256 maxIterations,
        ChronoHopPrepData memory prepData
    ) internal {
        // Stores ChronoHop data without executing, deferring to continueChronoHop/executeHops
        uint256 rawPrincipal = denormalizeForToken(prepData.principal + prepData.feeAmount, startToken);
        uint256 actualAmount = _checkTransfer(startToken, msg.sender, address(this), rawPrincipal);
        uint256 normalizedActual = normalizeForToken(actualAmount, startToken);
        uint256 actualFee = (normalizedActual * FEE_BASIS_POINTS) / 10000;
        prepData.principal = normalizedActual - actualFee;
        prepData.feeAmount = actualFee;
        address[] memory listings = new address[](prepData.indices.length);
        listings[0] = listing1;
        if (prepData.indices.length >= 2) listings[1] = listing2;
        if (prepData.indices.length >= 3) listings[2] = listing3;
        if (prepData.indices.length == 4) listings[3] = listing4;
        initializeChronoHopData(
            listings, impactPercent, startToken, endToken, settleType, maxIterations, prepData.timestamp, prepData
        );
    }

    function chronoHop(
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
    ) external payable nonReentrant onlyValidListing(listing1) returns (uint256) {
        // Initiates a time-based multi-step token swap, holding tokens until execution
        address effectiveMaker = maker == address(0) ? msg.sender : maker;
        ChronoHopPrepData memory prepData = prepChronoHop(
            listing1, listing2, listing3, listing4, impactPercent,
            startToken, endToken, settleType, maxIterations, block.timestamp, effectiveMaker
        );
        executeChronoHop(
            listing1, listing2, listing3, listing4, impactPercent,
            startToken, endToken, settleType, maxIterations, prepData
        );
        emit ChronoHopStarted(prepData.hopId, effectiveMaker, prepData.indices.length, prepData.timestamp);
        nextChronoHopId++;
        return prepData.hopId;
    }

    function processChronoHopStep(uint256 hopId) internal {
        // Executes a ChronoHop step via IMultihopper, updating multiHopId
        StalledChronoHop storage stalledHop = chronoHopID[hopId];
        if (stalledHop.hopStatus != 1 || block.timestamp < stalledHop.timestamp) return;
        require(_multiHopper != address(0), "MultiHopper not set");
        uint256 rawPrincipal = denormalizeForToken(stalledHop.principalAmount, stalledHop.startToken);
        if (stalledHop.startToken != address(0)) {
            IERC20(stalledHop.startToken).safeApprove(_multiHopper, rawPrincipal);
        }
        try IMultihopper(_multiHopper).hop{value: stalledHop.startToken == address(0) ? rawPrincipal : 0}(
            stalledHop.currentListing,
            stalledHop.remainingListings.length > 0 ? stalledHop.remainingListings[0] : address(0),
            stalledHop.remainingListings.length > 1 ? stalledHop.remainingListings[1] : address(0),
            stalledHop.remainingListings.length > 2 ? stalledHop.remainingListings[2] : address(0),
            stalledHop.impactPricePercents[0],
            stalledHop.startToken,
            stalledHop.endToken,
            stalledHop.settleType,
            stalledHop.maxIterations,
            stalledHop.hopMaker
        ) returns (uint256 multiHopId) {
            stalledHop.multiHopId = multiHopId;
        } catch {
            revert("MultiHop creation failed");
        }
        if (stalledHop.startToken != address(0)) {
            IERC20(stalledHop.startToken).safeApprove(_multiHopper, 0);
        }
        stalledHop.hopStatus = 2; // Mark as completed
        stalledHop.stage++;
        address[] memory newRemaining = new address[](stalledHop.remainingListings.length > 0 ? stalledHop.remainingListings.length - 1 : 0);
        for (uint256 i = 1; i < stalledHop.remainingListings.length; i++) {
            newRemaining[i - 1] = stalledHop.remainingListings[i];
        }
        stalledHop.remainingListings = newRemaining;
        stalledHop.currentListing = stalledHop.remainingListings.length > 0 ? stalledHop.remainingListings[0] : address(0);
        if (stalledHop.feeAmount > 0) {
            uint256 rawFee = denormalizeForToken(stalledHop.feeAmount, stalledHop.startToken);
            if (stalledHop.startToken == address(0)) {
                payable(msg.sender).transfer(rawFee);
            } else {
                IERC20(stalledHop.startToken).safeTransfer(msg.sender, rawFee);
            }
            emit FeePaid(msg.sender, stalledHop.startToken, rawFee);
        }
        emit ChronoHopContinued(hopId, stalledHop.stage);
    }

    function continueChronoHop(uint256 maxIterations) external nonReentrant {
        // Continues stalled ChronoHops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        uint256[] storage userHops = chronoHopsByAddress[msg.sender];
        for (uint256 i = 0; i < userHops.length && iterations < maxIterations; i++) {
            if (chronoHopID[userHops[i]].hopStatus != 1) continue;
            processChronoHopStep(userHops[i]);
            if (chronoHopID[userHops[i]].hopStatus == 2) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
            }
            iterations++;
        }
    }

    function executeHops(uint256 maxIterations) external nonReentrant {
        // Processes all stalled ChronoHops globally up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256 iterations = 0;
        for (uint256 i = 0; i < totalChronoHops.length && iterations < maxIterations; i++) {
            if (chronoHopID[totalChronoHops[i]].hopStatus != 1) continue;
            processChronoHopStep(totalChronoHops[i]);
            if (chronoHopID[totalChronoHops[i]].hopStatus == 2) {
                address maker = chronoHopID[totalChronoHops[i]].hopMaker;
                uint256[] storage userHops = chronoHopsByAddress[maker];
                for (uint256 j = 0; j < userHops.length; j++) {
                    if (userHops[j] == totalChronoHops[i]) {
                        userHops[j] = userHops[userHops.length - 1];
                        userHops.pop();
                        break;
                    }
                }
            }
            iterations++;
        }
    }

    function cancelChronoHop(uint256 hopId) external nonReentrant {
        // Cancels a specific ChronoHop, refunding tokens
        StalledChronoHop storage stalledHop = chronoHopID[hopId];
        require(stalledHop.hopMaker == msg.sender, "Not hop maker");
        require(stalledHop.hopStatus == 1, "Hop not stalled");
        uint256 totalRefund = stalledHop.principalAmount + stalledHop.feeAmount;
        if (totalRefund > 0) {
            uint256 rawRefund = denormalizeForToken(totalRefund, stalledHop.startToken);
            if (stalledHop.startToken == address(0)) {
                payable(msg.sender).transfer(rawRefund);
            } else {
                IERC20(stalledHop.startToken).safeTransfer(msg.sender, rawRefund);
            }
        }
        stalledHop.hopStatus = 2;
        uint256[] storage userHops = chronoHopsByAddress[msg.sender];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] == hopId) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
                break;
            }
        }
        emit ChronoHopCanceled(hopId);
    }

    function cancelAll(uint256 maxIterations) external nonReentrant {
        // Cancels all stalled ChronoHops for msg.sender up to maxIterations
        require(maxIterations > 0, "Invalid maxIterations");
        uint256[] storage userHops = chronoHopsByAddress[msg.sender];
        uint256 canceled = 0;
        for (uint256 i = userHops.length; i > 0 && canceled < maxIterations; i--) {
            uint256 hopId = userHops[i - 1];
            StalledChronoHop storage stalledHop = chronoHopID[hopId];
            if (stalledHop.hopStatus != 1) continue;
            uint256 totalRefund = stalledHop.principalAmount + stalledHop.feeAmount;
            if (totalRefund > 0) {
                uint256 rawRefund = denormalizeForToken(totalRefund, stalledHop.startToken);
                if (stalledHop.startToken == address(0)) {
                    payable(msg.sender).transfer(rawRefund);
                } else {
                    IERC20(stalledHop.startToken).safeTransfer(msg.sender, rawRefund);
                }
            }
            stalledHop.hopStatus = 2;
            userHops[i - 1] = userHops[userHops.length - 1];
            userHops.pop();
            emit ChronoHopCanceled(hopId);
            canceled++;
        }
        emit AllChronoHopsCanceled(msg.sender, canceled);
    }

    function chronoHopStatusView(uint256 hopId) public view returns (uint8) {
        // Returns the status of a specific ChronoHop
        return chronoHopID[hopId].hopStatus;
    }

    function getChronoHopDetails(uint256 hopId) public view returns (StalledChronoHop memory) {
        // Returns the full StalledChronoHop struct for a given hopId
        return chronoHopID[hopId];
    }

    function getUserChronoHops(address user) public view returns (uint256[] memory) {
        // Returns the array of ChronoHop IDs for a given user
        return chronoHopsByAddress[user];
    }

    function getChronoHopOrderDetails(uint256 hopId) public view returns (ChronoHopOrderDetails memory) {
        // Returns order details from IMultihopper for the current hop
        StalledChronoHop memory stalledHop = chronoHopID[hopId];
        require(_multiHopper != address(0), "MultiHopper not set");
        IMultihopper.HopOrderDetails memory details = IMultihopper(_multiHopper).getHopOrderDetails(stalledHop.multiHopId);
        return ChronoHopOrderDetails({
            pending: details.pending,
            filled: details.filled,
            status: details.status,
            amountSent: details.amountSent,
            recipient: details.recipient
        });
    }

    function getChronoHopRoute(uint256 hopId) public view returns (ChronoHopRouteData memory) {
        // Returns the ordered list of listings and buy/sell flags for a ChronoHop
        StalledChronoHop memory stalledHop = chronoHopID[hopId];
        require(_multiHopper != address(0), "MultiHopper not set");
        IMultihopper.HopRouteData memory route = IMultihopper(_multiHopper).getHopRoute(stalledHop.multiHopId);
        return ChronoHopRouteData({
            listings: route.listings,
            isBuy: route.isBuy
        });
    }

    function getContractBalance(address token) public view returns (uint256) {
        // Returns the contract's balance for a specified token or native currency
        if (token == address(0)) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }
}