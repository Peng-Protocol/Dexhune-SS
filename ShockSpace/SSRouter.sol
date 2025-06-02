// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.13
// Changes:
// - v0.0.13: Fixed TypeError in initializeListing by using distinct local variable names (tokenAAddress, tokenBAddress) to avoid shadowing tokenA and tokenB mappings. Updated liquidityAddresses assignment to call listingTemplate.liquidityAddressView() to match SSListingTemplate.sol (v0.0.8).
// - v0.0.12: Removed setRegistry and registryAddress references, as registry management moved to ISSListingTemplate to align with SSListingTemplate.sol (v0.0.8).
// - v0.0.11: Removed listingAgent state variable and setListingAgent function, using inherited agent and setAgent from SSMainPartial.sol (v0.0.10). Updated setRegistry to use inherited agent.
// - v0.0.10: Renamed _listingAgent parameter in setListingAgent to newListingAgent for clarity and consistency with listingAgent state variable.
// - v0.0.9: Fixed TypeError in liquidShortPayout by updating to use payout.amount instead of payout.required to match ISSListingTemplate.ShortPayoutStruct in SSSettlementPartial.sol (v0.0.11) and SSListingTemplate.sol (v0.0.7).
// - v0.0.8: Renamed isValidListing function to checkValidListing to resolve conflict with isValidListing state variable in SSMainPartial.sol.
// - v0.0.7: Removed ISSAgent.globalizeOrders and globalizeLiquidity calls, globalization handled by SSListingTemplate/SSLiquidityTemplate.
// - v0.0.7: Added setRegistry function, registryAddress mapping in SSMainPartial.
// - v0.0.7: Removed setRouters calls from initializeListing, router checked via ISSLiquidityTemplate.routers.
// - v0.0.7: Kept mutable listingAgent, added setListingAgent.
// - v0.0.7: Renamed functions: createBuyOrder, createSellOrder, settleBuyOrders, settleSellOrders, settleBuyLiquid, settleSellLiquid.
// - v0.0.7: Added liquidity functions (deposit, withdraw, claimFees, changeSlotDepositor) for SSLiquidityTemplate v0.0.4.
// - v0.0.7: Updated initializeListing to populate mappings, validate listing via ISSAgent.getListing.
// - Compatible with SSListingTemplate.sol (v0.0.8), SSLiquidityTemplate.sol (v0.0.4), SSSettlementPartial.sol (v0.0.13).

import "./utils/SSSettlementPartial.sol";

contract SSRouter is SSSettlementPartial {
    event ListingInitialized(address listing);

    function initializeListing(address listing) external onlyOwner {
        ISSListingTemplate listingTemplate = ISSListingTemplate(listing);
        address agentAddress = listingTemplate.agent();
        require(agentAddress != address(0), "Agent not set");
        address tokenAAddress = listingTemplate.tokenA();
        address tokenBAddress = listingTemplate.tokenB();
        require(ISSAgent(agentAddress).getListing(tokenAAddress, tokenBAddress) == listing, "Invalid listing");
        isValidListing[listing] = true;
        liquidityAddresses[listing] = listingTemplate.liquidityAddressView();
        tokenA[listing] = tokenAAddress;
        tokenB[listing] = tokenBAddress;
        decimalsA[listing] = listingTemplate.decimalsA();
        decimalsB[listing] = listingTemplate.decimalsB();
        emit ListingInitialized(listing);
    }

    function createBuyOrder(
        address listing,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice
    ) external onlyValidListing(listing) nonReentrant {
        OrderPrep memory prep = _handleOrderPrep(listing, msg.sender, recipient, amount, maxPrice, minPrice, true);
        address tokenBAddress = tokenB[listing];
        uint256 preBalance = tokenBAddress == address(0) ? address(this).balance : 0;
        if (tokenBAddress == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(tokenBAddress).safeTransferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = tokenBAddress == address(0) ? address(this).balance : IERC20(tokenBAddress).balanceOf(address(this));
        uint256 amountReceived = postBalance - preBalance;
        require(amountReceived >= amount, "Insufficient tokens received");
        _executeSingleOrder(listing, prep, true);
    }

    function createSellOrder(
        address listing,
        address recipient,
        uint256 amount,
        uint256 maxPrice,
        uint256 minPrice
    ) external onlyValidListing(listing) nonReentrant {
        OrderPrep memory prep = _handleOrderPrep(listing, msg.sender, recipient, amount, maxPrice, minPrice, false);
        address tokenAAddress = tokenA[listing];
        uint256 preBalance = tokenAAddress == address(0) ? address(this).balance : 0;
        if (tokenAAddress == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(tokenAAddress).safeTransferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = tokenAAddress == address(0) ? address(this).balance : IERC20(tokenB[listing]).balanceOf(address(this));
        uint256 amountReceived = postBalance - preBalance;
        require(amountReceived >= amount, "Insufficient tokens received");
        _executeSingleOrder(listing, prep, false);
    }

    function settleBuyOrders(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeBuyOrders(listing, maxIterations);
    }

    function settleSellOrders(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeSellOrders(listing, maxIterations);
    }

    function settleBuyLiquid(address listing, uint256 amount) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddresses[listing]);
        require(liquidityContract.routers(address(this)), "Router not registered");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(yAmount >= amount, "Insufficient liquidity");
        uint256 impactPrice = _computeImpact(listing, amount, true);
        uint256 maxPrice = type(uint256).max;
        uint256 minPrice = 0;
        require(impactPrice <= maxPrice && impactPrice >= minPrice, "Price out of range");
        uint256 preBalance = tokenA[listing] == address(0) ? address(this).balance : 0;
        listingContract.transact(address(this), tokenA[listing], amount, msg.sender);
        uint256 postBalance = tokenA[listing] == address(0) ? address(this).balance : IERC20(tokenA[listing]).balanceOf(address(this));
        uint256 amountReceived = postBalance - preBalance;
        liquidityContract.updateLiquidity(address(this), false, amountReceived);
    }

    function settleSellLiquid(address listing, uint256 amount) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddresses[listing]);
        require(liquidityContract.routers(address(this)), "Router not registered");
        (uint256 xAmount, uint256 yAmount) = liquidityContract.liquidityAmounts();
        require(xAmount >= amount, "Insufficient liquidity");
        uint256 impactPrice = _computeImpact(listing, amount, false);
        uint256 maxPrice = type(uint256).max;
        uint256 minPrice = 0;
        require(impactPrice <= maxPrice && impactPrice >= minPrice, "Price out of range");
        uint256 preBalance = tokenB[listing] == address(0) ? address(this).balance : 0;
        listingContract.transact(address(this), tokenB[listing], amount, msg.sender);
        uint256 postBalance = tokenB[listing] == address(0) ? address(this).balance : IERC20(tokenB[listing]).balanceOf(address(this));
        uint256 amountReceived = postBalance - preBalance;
        liquidityContract.updateLiquidity(address(this), true, amountReceived);
    }

    function settleLongPayout(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeLongPayouts(listing, maxIterations);
    }

    function settleShortPayout(address listing, uint256 maxIterations) external onlyValidListing(listing) nonReentrant {
        executeShortPayouts(listing, maxIterations);
    }

    function liquidLongPayout(address listing, uint256 orderId) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.LongPayoutStruct memory payout = listingContract.getLongPayout(orderId);
        require(payout.required > 0, "No payout required");
        _processPayoutUpdate(listing, orderId, payout.required, true);
    }

    function liquidShortPayout(address listing, uint256 orderId) external onlyValidListing(listing) nonReentrant {
        ISSListingTemplate listingContract = ISSListingTemplate(listing);
        ISSListingTemplate.ShortPayoutStruct memory payout = listingContract.getShortPayout(orderId);
        require(payout.amount > 0, "No payout required");
        _processPayoutUpdate(listing, orderId, payout.amount, false);
    }

    function deposit(address listing, address token, uint256 amount) external payable onlyValidListing(listing) nonReentrant {
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddresses[listing]);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(token == tokenA[listing] || token == tokenB[listing], "Invalid token");
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
            liquidityContract.deposit{value: amount}(address(this), token, amount);
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            IERC20(token).approve(address(liquidityContract), amount);
            liquidityContract.deposit(address(this), token, amount);
        }
    }

    function claimFees(address listing, uint256 liquidityIndex, bool isX, uint256 volume) external onlyValidListing(listing) nonReentrant {
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddresses[listing]);
        require(liquidityContract.routers(address(this)), "Router not registered");
        liquidityContract.claimFees(address(this), listing, liquidityIndex, isX, volume);
    }

    function withdraw(address listing, uint256 amount, uint256 index, bool isX) external onlyValidListing(listing) nonReentrant {
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddresses[listing]);
        require(liquidityContract.routers(address(this)), "Router not registered");
        ISSLiquidityTemplate.PreparedWithdrawal memory withdrawal = isX
            ? liquidityContract.xPrepOut(address(this), amount, index)
            : liquidityContract.yPrepOut(address(this), amount, index);
        isX
            ? liquidityContract.xExecuteOut(address(this), index, withdrawal)
            : liquidityContract.yExecuteOut(address(this), index, withdrawal);
    }

    function changeLiquiditySlotDepositor(address listing, bool isX, uint256 slotIndex, address newDepositor) external onlyValidListing(listing) nonReentrant {
        ISSLiquidityTemplate liquidityContract = ISSLiquidityTemplate(liquidityAddresses[listing]);
        require(liquidityContract.routers(address(this)), "Router not registered");
        require(newDepositor != address(0), "Invalid new depositor");
        liquidityContract.changeSlotDepositor(address(this), isX, slotIndex, newDepositor);
    }

    function clearSingleOrder(address listing, uint256 orderId, bool isBuy) external onlyValidListing(listing) nonReentrant {
        _clearOrderData(listing, orderId, isBuy);
    }

    function clearOrders(address listing, uint256[] memory orderIds, bool[] memory isBuyIds) external onlyValidListing(listing) nonReentrant {
        for (uint256 i = 0; i < orderIds.length; i++) {
            _clearOrderData(listing, orderIds[i], isBuyIds[i]);
        }
    }

    function checkValidListing(address listing) public view returns (bool) {
        ISSListingTemplate listingTemplate = ISSListingTemplate(listing);
        address agentAddress = listingTemplate.agent();
        if (agentAddress == address(0)) return false;
        address tokenAAddress = listingTemplate.tokenA();
        address tokenBAddress = listingTemplate.tokenB();
        return ISSAgent(agentAddress).getListing(tokenAAddress, tokenBAddress) == listing;
    }
}