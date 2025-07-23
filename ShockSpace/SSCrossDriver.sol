/*
 SPDX-License-Identifier: BSL-1.1-Peng-Protocol-2025
*/

// Recent Changes:
// - 2025-07-23: Removed pullMargin function, as it was deemed detrimental to the protocol. Version incremented to 0.0.47.
// - 2025-07-23: Removed positionToken mapping declaration, as it was moved to CSDExecutionPartial.sol to resolve DeclarationError in _updatePositionLiquidationPrices. Version incremented to 0.0.46.
// - 2025-07-23: Moved internal helpers (_transferMarginToListing, _updateListingMargin, _updatePositionLiquidationPrices, _updateMakerMargin, _validateAndNormalizePullMargin, _executeMarginPayout, _reduceMakerMargin) to CSDExecutionPartial.sol to unload SSCrossDriver.sol. Cleared change log except for 2025-07-23 entries. Version incremented to 0.0.45.
// - 2025-07-23: Removed unnecessary `override` from _executePositions to resolve TypeError, as base function in CSDExecutionPartial.sol is not virtual. Version incremented to 0.0.44.
// - 2025-07-23: Added _updatePositionLiquidationPrices calls to closeLongPosition, closeShortPosition, and _executePositions to update liquidation prices for maker's remaining positions after closure. Version incremented to 0.0.43.

pragma solidity ^0.8.2;

import "./driverUtils/CSDExecutionPartial.sol";

contract SSCrossDriver is ReentrancyGuard, Ownable, CSDExecutionPartial {
    event PositionEntered(uint256 indexed positionId, address indexed maker, uint8 positionType);
    event PositionCancelled(uint256 indexed positionId, address indexed maker);
    event StopLossUpdated(uint256 indexed positionId, uint256 newStopLossPrice, uint256 currentPrice, uint256 timestamp);
    event TakeProfitUpdated(uint256 indexed positionId, uint256 newTakeProfitPrice, uint256 currentPrice, uint256 timestamp);
    event AllLongsClosed(address indexed maker, uint256 processed);
    event AllLongsCancelled(address indexed maker, uint256 processed);
    event AllShortsClosed(address indexed maker, uint256 processed);
    event AllShortsCancelled(address indexed maker, uint256 processed);
    event MuxAdded(address indexed mux);
    event MuxRemoved(address indexed mux);

    mapping(uint256 => uint256) public longIOByHeight;
    mapping(uint256 => uint256) public shortIOByHeight;
    mapping(uint256 => uint256) public historicalInterestTimestamps;

    // Modifier to restrict functions to authorized muxes
    modifier onlyMux() {
        require(muxes[msg.sender], "Caller is not a mux");
        _;
    }

    // Adds a new mux to the authorized list
    function addMux(address mux) external onlyOwner {
        require(mux != address(0), "Invalid mux address");
        require(!muxes[mux], "Mux already exists");
        muxes[mux] = true;
        emit MuxAdded(mux);
    }

    // Removes a mux from the authorized list
    function removeMux(address mux) external onlyOwner {
        require(muxes[mux], "Mux does not exist");
        muxes[mux] = false;
        emit MuxRemoved(mux);
    }

    // View function to return all authorized muxes
    function getMuxesView() external view returns (address[] memory) {
        uint256 count = 0;
        // Count authorized muxes (limit to 1000 for gas safety)
        for (uint256 i = 0; i < 1000; i++) {
            if (muxes[address(uint160(i))]) {
                count++;
            }
        }
        address[] memory result = new address[](count);
        uint256 index = 0;
        // Populate result array
        for (uint256 i = 0; i < 1000; i++) {
            if (muxes[address(uint160(i))]) {
                result[index] = address(uint160(i));
                index++;
            }
        }
        return result;
    }

    // Allows any address to create positions on behalf of a maker
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
    ) external nonReentrant {
        require(maker != address(0), "Invalid maker address");
        require(positionType <= 1, "Invalid position type");
        uint256 positionId = positionCount + 1;
        
        // Initialize entry context
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            positionType
        );
        context.maker = maker; // Override maker from msg.sender to provided maker
        context = _validateEntry(context);
        PrepPosition memory prep = _computeEntryParams(context);
        _storeEntryData(context, prep, stopLossPrice, takeProfitPrice);
        emit PositionEntered(positionId, maker, positionType);
    }

    // Allows muxes to close a specific position on behalf of a maker, sending payout to mux
    function drift(uint256 positionId, address maker) external nonReentrant onlyMux {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == maker, "Maker mismatch");
        
        uint256 payout;
        address token;
        if (core1.positionType == 0) {
            token = ISSListing(core1.listingAddress).tokenB();
            payout = prepCloseLong(positionId, core1.listingAddress);
        } else {
            token = ISSListing(core1.listingAddress).tokenA();
            payout = prepCloseShort(positionId, core1.listingAddress);
        }
        
        // Remove position from active/pending arrays
        removePositionIndex(positionId, core1.positionType, core1.listingAddress);
        
        // Execute payout to mux (caller)
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: core1.positionType,
            recipient: msg.sender, // Payout to mux instead of maker
            required: denormalizeAmount(token, payout)
        });
        ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
        
        emit PositionClosed(positionId, maker, payout);
    }

    function normalizePrice(address token, uint256 price) internal view override returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        if (decimals < 18) return price * (10 ** (18 - decimals));
        if (decimals > 18) return price / (10 ** (decimals - 18));
        return price;
    }

    function denormalizeAmount(address token, uint256 amount) internal view override returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    function normalizeAmount(address token, uint256 amount) internal view override returns (uint256) {
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    function updateHistoricalInterest(uint256 amount, uint8 positionType, address listing) internal {
        uint256 height = block.number;
        if (positionType == 0) {
            longIOByHeight[height] += amount;
        } else {
            shortIOByHeight[height] += amount;
        }
        historicalInterestTimestamps[height] = block.timestamp;
    }

    function setAgent(address newAgentAddress) external onlyOwner {
        require(newAgentAddress != address(0), "Invalid agent address");
        agentAddress = newAgentAddress;
    }

    function _validateAndInit(
        address listingAddress,
        uint8 positionType
    ) internal override returns (address maker, address token) {
        uint256 positionId = positionCount + 1;
        require(positionCore1[positionId].positionId == 0, "Position ID exists");
        address tokenA = ISSListing(listingAddress).tokenA();
        address tokenB = ISSListing(listingAddress).tokenB();
        address expectedListing = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(expectedListing == listingAddress, "Invalid listing");
        maker = msg.sender;
        positionCount++;
        token = positionType == 0 ? tokenA : tokenB;
        return (maker, token);
    }

    function _setCoreData(
        uint256 positionId,
        address listingAddress,
        address maker,
        uint8 positionType,
        address token
    ) internal override {
        positionCore1[positionId] = PositionCore1({
            positionId: positionId,
            listingAddress: listingAddress,
            makerAddress: maker,
            positionType: positionType
        });
        positionCore2[positionId] = PositionCore2({ status1: false, status2: 0 });
        positionToken[positionId] = token;
    }

    function _setPriceData(
        uint256 positionId,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 liquidationPrice,
        address listingAddress,
        uint8 leverage,
        address token
    ) internal override {
        (, , , uint256 priceAtEntry) = _parseEntryPriceInternal(
            normalizePrice(token, minEntryPrice),
            normalizePrice(token, maxEntryPrice),
            listingAddress
        );
        priceParams1[positionId] = PriceParams1({
            minEntryPrice: normalizePrice(token, minEntryPrice),
            maxEntryPrice: normalizePrice(token, maxEntryPrice),
            minPrice: liquidationPrice,
            priceAtEntry: priceAtEntry,
            leverage: leverage
        });
        priceParams2[positionId] = PriceParams2({ liquidationPrice: liquidationPrice });
    }

    function _setMarginData(
        uint256 positionId,
        uint256 initialMargin,
        uint256 taxedMargin,
        uint256 excessMargin,
        uint256 fee,
        uint256 initialLoan,
        address token
    ) internal override {
        marginParams1[positionId] = MarginParams1({
            initialMargin: normalizeAmount(token, initialMargin),
            taxedMargin: taxedMargin,
            excessMargin: normalizeAmount(token, excessMargin),
            fee: fee
        });
        marginParams2[positionId] = MarginParams2({
            initialLoan: normalizeAmount(token, initialLoan)
        });
    }

    function _setExitData(
        uint256 positionId,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint256 leverageAmount,
        address listingAddress,
        uint8 positionType,
        address token
    ) internal override {
        exitParams[positionId] = ExitParams({
            stopLossPrice: normalizePrice(token, stopLossPrice),
            takeProfitPrice: normalizePrice(token, takeProfitPrice),
            exitPrice: 0
        });
        openInterest[positionId] = OpenInterest({ leverageAmount: leverageAmount, timestamp: block.timestamp });
        pendingPositions[listingAddress][positionType].push(positionId);
        updateHistoricalInterest(leverageAmount, positionType, listingAddress);
    }

    function _initiateEntry(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice,
        uint8 positionType
    ) internal {
        uint256 positionId = positionCount + 1;
        EntryContext memory context = _prepareEntryContext(
            listingAddress,
            positionId,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            positionType
        );
        context = _validateEntry(context);
        PrepPosition memory prep = _computeEntryParams(context);
        _storeEntryData(context, prep, stopLossPrice, takeProfitPrice);
    }

    function enterLong(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external nonReentrant {
        _initiateEntry(
            listingAddress,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            0
        );
        uint256 positionId = positionCount;
        emit PositionEntered(positionId, msg.sender, 0);
    }

    function enterShort(
        address listingAddress,
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external nonReentrant {
        _initiateEntry(
            listingAddress,
            minEntryPrice,
            maxEntryPrice,
            initialMargin,
            excessMargin,
            leverage,
            stopLossPrice,
            takeProfitPrice,
            1
        );
        uint256 positionId = positionCount;
        emit PositionEntered(positionId, msg.sender, 1);
    }

    function addExcessMargin(address listingAddress, bool tokenA, uint256 amount, address maker) external nonReentrant {
        // Validate input parameters
        require(amount > 0, "Invalid amount");
        require(maker != address(0), "Invalid maker");
        require(listingAddress != address(0), "Invalid listing");
        (bool isValid, ) = ISSAgent(agentAddress).isValidListing(listingAddress);
        require(isValid, "Invalid listing");

        // Determine token and transfer margin
        address token = tokenA ? ISSListing(listingAddress).tokenA() : ISSListing(listingAddress).tokenB();
        uint256 normalizedAmount = _transferMarginToListing(token, amount, listingAddress);

        // Update listing contract
        _updateListingMargin(listingAddress, amount);

        // Update maker's margin
        _updateMakerMargin(maker, token, normalizedAmount);

        // Update liquidation prices
        _updatePositionLiquidationPrices(maker, token, listingAddress);

        // Record historical interest
        updateHistoricalInterest(normalizedAmount, 0, listingAddress);
    }

    function closeLongPosition(uint256 positionId) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        address tokenB = ISSListing(core1.listingAddress).tokenB();
        uint256 payout = prepCloseLong(positionId, core1.listingAddress);
        removePositionIndex(positionId, core1.positionType, core1.listingAddress);
        // Update liquidation prices for maker's remaining positions
        _updatePositionLiquidationPrices(msg.sender, ISSListing(core1.listingAddress).tokenA(), core1.listingAddress);
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: core1.positionType,
            recipient: msg.sender,
            required: denormalizeAmount(tokenB, payout)
        });
        ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
        emit PositionClosed(positionId, msg.sender, payout);
    }

    function closeShortPosition(uint256 positionId) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        address tokenA = ISSListing(core1.listingAddress).tokenA();
        uint256 payout = prepCloseShort(positionId, core1.listingAddress);
        removePositionIndex(positionId, core1.positionType, core1.listingAddress);
        // Update liquidation prices for maker's remaining positions
        _updatePositionLiquidationPrices(msg.sender, ISSListing(core1.listingAddress).tokenB(), core1.listingAddress);
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: core1.positionType,
            recipient: msg.sender,
            required: denormalizeAmount(tokenA, payout)
        });
        ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
        emit PositionClosed(positionId, msg.sender, payout);
    }

    function cancelPosition(uint256 positionId) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(!core2.status1, "Position active");
        require(core1.makerAddress == msg.sender, "Not maker");
        MarginParams1 storage margin1 = marginParams1[positionId];
        address token = positionToken[positionId];
        makerTokenMargin[msg.sender][token] -= (margin1.taxedMargin + margin1.excessMargin);
        if (makerTokenMargin[msg.sender][token] == 0) {
            _removeToken(msg.sender, token);
        }
        core2.status2 = 1;
        ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
        updates[0] = ISSListing.PayoutUpdate({
            payoutType: core1.positionType,
            recipient: msg.sender,
            required: denormalizeAmount(token, margin1.taxedMargin + margin1.excessMargin)
        });
        ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
        removePositionIndex(positionId, core1.positionType, core1.listingAddress);
        emit PositionCancelled(positionId, msg.sender);
    }

    function updateSL(uint256 positionId, uint256 newStopLossPrice) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        require(newStopLossPrice > 0 || newStopLossPrice == 0, "Invalid SL");
        address token = positionToken[positionId];
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress));
        PriceParams1 storage price1 = priceParams1[positionId];

        _updateSL(
            positionId,
            normalizePrice(token, newStopLossPrice),
            core1.listingAddress,
            core1.positionType,
            price1.minPrice,
            price1.maxEntryPrice,
            currentPrice
        );

        emit StopLossUpdated(positionId, newStopLossPrice, currentPrice, block.timestamp);
    }

    function updateTP(uint256 positionId, uint256 newTakeProfitPrice) external nonReentrant {
        PositionCore1 storage core1 = positionCore1[positionId];
        PositionCore2 storage core2 = positionCore2[positionId];
        require(core1.positionId == positionId, "Invalid position");
        require(core2.status2 == 0, "Position closed");
        require(core1.makerAddress == msg.sender, "Not maker");
        require(newTakeProfitPrice > 0 || newTakeProfitPrice == 0, "Invalid TP");
        address token = positionToken[positionId];
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress));
        PriceParams1 storage price1 = priceParams1[positionId];

        _updateTP(
            positionId,
            normalizePrice(token, newTakeProfitPrice),
            core1.listingAddress,
            core1.positionType,
            price1.priceAtEntry,
            price1.maxEntryPrice,
            currentPrice
        );

        emit TakeProfitUpdated(positionId, newTakeProfitPrice, currentPrice, block.timestamp);
    }

    function closeAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 0 || core2.status2 != 0 || !core2.status1) continue;
            address tokenB = ISSListing(core1.listingAddress).tokenB();
            uint256 payout = prepCloseLong(positionId, core1.listingAddress);
            removePositionIndex(positionId, core1.positionType, core1.listingAddress);
            // Update liquidation prices for maker's remaining positions
            _updatePositionLiquidationPrices(maker, ISSListing(core1.listingAddress).tokenA(), core1.listingAddress);
            ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
            updates[0] = ISSListing.PayoutUpdate({
                payoutType: core1.positionType,
                recipient: maker,
                required: denormalizeAmount(tokenB, payout)
            });
            ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
            emit PositionClosed(positionId, maker, payout);
            processed++;
        }
        emit AllLongsClosed(maker, processed);
    }

    function cancelAllLongs(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 0 || core2.status2 != 0 || core2.status1) continue;
            address token = positionToken[positionId];
            MarginParams1 storage margin1 = marginParams1[positionId];
            makerTokenMargin[msg.sender][token] -= (margin1.taxedMargin + margin1.excessMargin);
            if (makerTokenMargin[msg.sender][token] == 0) {
                _removeToken(msg.sender, token);
            }
            core2.status2 = 1;
            exitParams[positionId].exitPrice = 0;
            removePositionIndex(positionId, core1.positionType, core1.listingAddress);
            processed++;
        }
        emit AllLongsCancelled(maker, processed);
    }

    function closeAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 1 || core2.status2 != 0 || !core2.status1) continue;
            address tokenA = ISSListing(core1.listingAddress).tokenA();
            uint256 payout = prepCloseShort(positionId, core1.listingAddress);
            removePositionIndex(positionId, 1, core1.listingAddress);
            // Update liquidation prices for maker's remaining positions
            _updatePositionLiquidationPrices(maker, ISSListing(core1.listingAddress).tokenB(), core1.listingAddress);
            ISSListing.PayoutUpdate[] memory updates = new ISSListing.PayoutUpdate[](1);
            updates[0] = ISSListing.PayoutUpdate({
                payoutType: core1.positionType,
                recipient: maker,
                required: denormalizeAmount(tokenA, payout)
            });
            ISSListing(core1.listingAddress).ssUpdate(address(this), updates);
            emit PositionClosed(positionId, maker, payout);
            processed++;
        }
        emit AllShortsClosed(maker, processed);
    }

    function cancelAllShorts(uint256 maxIterations) external nonReentrant {
        address maker = msg.sender;
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations && gasleft() >= 50000; i++) {
            uint256 positionId = i + 1;
            PositionCore1 storage core1 = positionCore1[positionId];
            PositionCore2 storage core2 = positionCore2[positionId];
            if (core1.makerAddress != maker || core1.positionType != 1 || core2.status2 != 0 || core2.status1) continue;
            address token = positionToken[positionId];
            MarginParams1 storage margin1 = marginParams1[positionId];
            makerTokenMargin[maker][token] -= (margin1.taxedMargin + margin1.excessMargin);
            if (makerTokenMargin[maker][token] == 0) {
                _removeToken(maker, token);
            }
            core2.status2 = 1;
            exitParams[positionId].exitPrice = 0;
            removePositionIndex(positionId, 1, core1.listingAddress);
            processed++;
        }
        emit AllShortsCancelled(maker, processed);
    }

    function executePositions(address listingAddress, uint256 maxIterations) external nonReentrant {
        _executePositions(listingAddress, maxIterations);
    }

    function PositionsByTypeView(
        uint8 positionType,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        require(positionType <= 1, "Invalid position type");
        uint256 length = positionsByType[positionType].length;
        uint256 count = length > startIndex + maxIterations ? maxIterations : length - startIndex;
        positionIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            positionIds[i] = positionsByType[positionType][startIndex + i];
        }
    }

    function PositionsByAddressView(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory positionIds) {
        uint256 count = 0;
        uint256[] memory tempIds = new uint256[](positionCount);
        for (uint256 i = startIndex; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].makerAddress == maker && !positionCore2[positionId].status1) {
                tempIds[count] = positionId;
                count++;
            }
        }
        positionIds = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            positionIds[i] = tempIds[i];
        }
    }

    function positionByIndex(uint256 positionId) external view returns (
        PositionCore1 memory core1,
        PositionCore2 memory core2,
        PriceParams1 memory price1,
        PriceParams2 memory price2,
        MarginParams1 memory margin1,
        MarginParams2 memory margin2,
        ExitParams memory exit,
        address token
    ) {
        require(positionCore1[positionId].positionId == positionId, "Invalid position");
        core1 = positionCore1[positionId];
        core2 = positionCore2[positionId];
        price1 = priceParams1[positionId];
        price2 = priceParams2[positionId];
        margin1 = marginParams1[positionId];
        margin2 = marginParams2[positionId];
        exit = exitParams[positionId];
        token = positionToken[positionId];
    }

    function TotalActivePositionsView() external view returns (uint256 count) {
        for (uint256 i = 1; i <= positionCount; i++) {
            if (positionCore1[i].positionId == i && positionCore2[i].status1 && positionCore2[i].status2 == 0) {
                count++;
            }
        }
    }

    function queryInterest(uint256 startIndex, uint256 maxIterations) external view returns (
        uint256[] memory longIO,
        uint256[] memory shortIO,
        uint256[] memory timestamps
    ) {
        uint256 count = positionCount > startIndex + maxIterations ? maxIterations : positionCount - startIndex;
        longIO = new uint256[](count);
        shortIO = new uint256[](count);
        timestamps = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            uint256 height = startIndex + i;
            longIO[i] = longIOByHeight[height];
            shortIO[i] = shortIOByHeight[height];
            timestamps[i] = historicalInterestTimestamps[height];
        }
    }

    function makerMarginIndex(
        address maker,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory tokens, uint256[] memory margins) {
        address[] storage makerTokens = makerMarginTokens[maker];
        uint256 length = makerTokens.length > startIndex + maxIterations ? maxIterations : makerTokens.length - startIndex;
        tokens = new address[](length);
        margins = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            tokens[i] = makerTokens[startIndex + i];
            margins[i] = makerTokenMargin[maker][tokens[i]];
        }
    }

    function PositionHealthView(uint256 positionId) external view returns (
        uint256 marginRatio,
        uint256 distanceToLiquidation,
        uint256 estimatedProfitLoss
    ) {
        require(positionCore1[positionId].positionId == positionId, "Invalid position");
        PositionCore1 memory core1 = positionCore1[positionId];
        MarginParams1 memory margin1 = marginParams1[positionId];
        PriceParams1 memory price1 = priceParams1[positionId];
        PriceParams2 memory price2 = priceParams2[positionId];
        address token = core1.positionType == 0 ? ISSListing(core1.listingAddress).tokenB() : ISSListing(core1.listingAddress).tokenA();
        uint256 currentPrice = normalizePrice(token, ISSListing(core1.listingAddress).prices(core1.listingAddress));
        require(currentPrice > 0, "Invalid price");

        address marginToken = positionToken[positionId];
        uint256 totalMargin = makerTokenMargin[core1.makerAddress][marginToken];
        marginRatio = totalMargin * DECIMAL_PRECISION / (margin1.initialMargin * uint256(price1.leverage));

        if (core1.positionType == 0) {
            distanceToLiquidation = currentPrice > price2.liquidationPrice ? currentPrice - price2.liquidationPrice : 0;
            estimatedProfitLoss = (margin1.taxedMargin + totalMargin + uint256(price1.leverage) * margin1.initialMargin) / currentPrice - marginParams2[positionId].initialLoan;
        } else {
            distanceToLiquidation = currentPrice < price2.liquidationPrice ? price2.liquidationPrice - currentPrice : 0;
            estimatedProfitLoss = (price1.priceAtEntry - currentPrice) * margin1.initialMargin * uint256(price1.leverage) + (margin1.taxedMargin + totalMargin) * currentPrice / DECIMAL_PRECISION;
        }
    }

    function AggregateMarginByToken(
        address tokenA,
        address tokenB,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (address[] memory makers, uint256[] memory margins) {
        address listingAddress = ISSAgent(agentAddress).getListing(tokenA, tokenB);
        require(listingAddress != address(0), "Invalid listing");
        address token = ISSListing(listingAddress).tokenB();
        uint256 length = positionsByType[0].length + positionsByType[1].length;
        uint256 count = length > startIndex + maxIterations ? maxIterations : length - startIndex;
        address[] memory tempMakers = new address[](count);
        uint256[] memory tempMargins = new uint256[](count);
        uint256 index = 0;

        for (uint8 positionType = 0; positionType <= 1 && index < count; positionType++) {
            uint256[] storage positionIds = positionsByType[positionType];
            for (uint256 i = 0; i < positionIds.length && index < count; i++) {
                uint256 positionId = positionIds[i];
                address maker = positionCore1[positionId].makerAddress;
                if (maker != address(0) && makerTokenMargin[maker][token] > 0) {
                    tempMakers[index] = maker;
                    tempMargins[index] = makerTokenMargin[maker][token];
                    index++;
                }
            }
        }

        makers = new address[](index);
        margins = new uint256[](index);
        for (uint256 i = 0; i < index; i++) {
            makers[i] = tempMakers[i];
            margins[i] = tempMargins[i];
        }
    }

    function OpenInterestTrend(
        address listingAddress,
        uint256 startIndex,
        uint256 maxIterations
    ) external view returns (uint256[] memory leverageAmounts, uint256[] memory timestamps) {
        uint256 count = 0;
        uint256[] memory tempAmounts = new uint256[](positionCount);
        uint256[] memory tempTimestamps = new uint256[](positionCount);

        for (uint256 i = 0; i < positionCount && count < maxIterations; i++) {
            uint256 positionId = i + 1;
            if (positionCore1[positionId].listingAddress == listingAddress && positionCore2[positionId].status2 == 0) {
                tempAmounts[count] = openInterest[positionId].leverageAmount;
                tempTimestamps[count] = openInterest[positionId].timestamp;
                count++;
            }
        }

        leverageAmounts = new uint256[](count);
        timestamps = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            leverageAmounts[i] = tempAmounts[i];
            timestamps[i] = tempTimestamps[i];
        }
    }

    function LiquidationRiskCount(address listingAddress, uint256 maxIterations) external view returns (uint256 count) {
        uint256 processed = 0;
        for (uint256 i = 0; i < positionCount && processed < maxIterations; i++) {
            uint256 positionId = i + 1;
            PositionCore1 memory core1 = positionCore1[positionId];
            PositionCore2 memory core2 = positionCore2[positionId];
            if (core1.listingAddress != listingAddress || core2.status2 != 0) continue;
            address token = core1.positionType == 0 ? ISSListing(listingAddress).tokenB() : ISSListing(listingAddress).tokenA();
            uint256 currentPrice = normalizePrice(token, ISSListing(listingAddress).prices(token));
            uint256 liquidationPrice = priceParams2[positionId].liquidationPrice;
            uint256 threshold = liquidationPrice * 5 / 100;

            if (core1.positionType == 0) {
                if (currentPrice <= liquidationPrice + threshold) count++;
            } else {
                if (currentPrice >= liquidationPrice - threshold) count++;
            }
            processed++;
        }
    }
}