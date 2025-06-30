// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.13 (Updated)
// Changes:
// - v0.0.13: Modified _processFeeClaim to reset dFeesAcc in the slot to the latest xFeesAcc (for ySlots) or yFeesAcc (for xSlots) after a successful fee claim to prevent double-counting of fees in future claims. Ensured reset occurs within the if (feeShare > 0) block to align with update and transact calls. Preserved all function signatures and existing logic. Aligned with SSListingTemplate.sol v0.0.10.
// - v0.0.12: Added xFeesAcc and yFeesAcc to LiquidityDetails to track cumulative fee volume, incremented by addFees and never decreased. Replaced Slot.dFees with dFeesAcc to store yFeesAcc (xSlot) or xFeesAcc (ySlot) at deposit. Modified claimFees and _claimFeeShare to use contributedFees = feesAcc - dFeesAcc, removing fixed 0.05% fee rate and feeRate variable. Fee share now based directly on contributedFees adjusted by liquidity contribution. Updated update to set dFeesAcc. Preserved all function signatures, ignoring volume in claimFees. Aligned with SSListingTemplate.sol v0.0.10.
// - v0.0.11: Modified deposit to fetch yFees for x-token deposits and xFees for y-token deposits from liquidityDetail, storing in Slot.dFees instead of dVolume. Updated claimFees and _claimFeeShare to use contributedFees (fees - dFees) instead of contributedVolume, removing price conversion in _processFeeClaim. Updated FeeClaimContext to remove volume and dVolume. Updated update function to set dFees instead of dVolume. Ignored volume param in claimFees to preserve signature. Aligned with SSListingTemplate.sol v0.0.10.
// - v0.0.10: Updated ISSListing.volumeBalances interface to return only xBalance and yBalance, matching SSListingTemplate.sol v0.0.10 implementation.
// - v0.0.9: Fixed undeclared identifier errors in _processFeeClaim by moving update, transact, and FeesClaimed event emission inside the if (feeShare > 0) block to ensure context, transferToken, and convertedFeeShare are in scope. Corrected typo in deposit function from IER20 to IERC20. Aligned with SSListingTemplate.sol v0.0.10.
// - v0.0.8: Updated claimFees to fetch price from ISSListing.getPrice() and convert feeShare to the opposite token's value (xSlots claim yFees in tokenA value, ySlots claim xFees in tokenB value). Added price to FeeClaimContext to manage stack depth. Updated FeesClaimed event to reflect converted amounts. Ensured decimal handling with normalize/denormalize. Aligned with SSListingTemplate.sol v0.0.10.
// - v0.0.7: Refactored claimFees to resolve stack too deep error by using FeeClaimContext struct to store intermediate values, reducing stack usage. Modified _processFeeClaim to accept FeeClaimContext, minimizing parameters. Aligned with SSRouter.sol v0.0.44.
// - v0.0.6: Removed transferLiquidity function entirely due to redundancy with changeSlotDepositor and potential exploit risks. Updated caller handling in changeSlotDepositor, deposit, xPrepOut, xExecuteOut, yPrepOut, yExecuteOut, claimFees to represent the user (e.g., slot owner). Ensured msg.sender is a registered router. Aligned with SSRouter.sol v0.0.44.
// - v0.0.5: Replaced safeTransferFrom with transferFrom in deposit.
// - v0.0.5: Added GlobalizeUpdateFailed and UpdateRegistryFailed events.
// - v0.0.5: Emitted error events in globalizeUpdate and updateRegistry.
// - v0.0.4: Added changeSlotDepositor, liquidityAmounts, agent, globalizeUpdate, updateRegistry.
// - v0.0.4: Simplified mappings: liquidityDetails to liquidityDetail, removed listingId key.
// - v0.0.4: Removed taxCollector and 10% fee logic.
// - v0.0.4: Updated ISSListing interface to include getPrice, getRegistryAddress.
// - v0.0.3: Modified claimFees for fee-swapping (xSlots claim yFees, ySlots claim xFees).
// - Compatible with SSListingTemplate.sol (v0.0.10), SSAgent.sol (v0.0.2).

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function getPrice() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
}

interface ISSAgent {
    function globalizeLiquidity(
        uint256 listingId,
        address tokenActivated,
        address tokenDeactivated,
        address user,
        uint256 amount,
        bool isDeposit
    ) external;
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

contract SSLiquidityTemplate is ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => bool) public routers;
    bool public routersSet;
    address public listingAddress;
    address public tokenA;
    address public tokenB;
    uint256 public listingId;
    address public agent;

    struct LiquidityDetails {
        uint256 xLiquid;
        uint256 yLiquid;
        uint256 xFees;
        uint256 yFees;
        uint256 xFeesAcc; // Cumulative fee volume for x-token
        uint256 yFeesAcc; // Cumulative fee volume for y-token
    }

    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dFeesAcc; // Cumulative fees at deposit (yFeesAcc for xSlot, xFeesAcc for ySlot)
        uint256 timestamp;
    }

    struct UpdateType {
        uint8 updateType; // 0 = balance, 1 = fees, 2 = xSlot, 3 = ySlot
        uint256 index;    // 0 = xFees/xLiquid, 1 = yFees/yLiquid, or slot index
        uint256 value;    // amount or allocation (normalized)
        address addr;     // depositor
        address recipient;// not used
    }

    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    struct FeeClaimContext {
        address caller;
        bool isX;
        uint256 liquid;
        uint256 allocation;
        uint256 fees;
        uint256 dFeesAcc; // Cumulative fees at deposit time
        uint256 liquidityIndex;
    }

    LiquidityDetails public liquidityDetail;
    mapping(uint256 => Slot) public xLiquiditySlots;
    mapping(uint256 => Slot) public yLiquiditySlots;
    uint256[] public activeXLiquiditySlots;
    uint256[] public activeYLiquiditySlots;
    mapping(address => uint256[]) public userIndex;

    event LiquidityUpdated(uint256 listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 listingId, uint256 xFees, uint256 yFees);
    event FeesClaimed(uint256 listingId, uint256 liquidityIndex, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed caller, uint256 listingId, bool isX, uint256 amount);
    event UpdateRegistryFailed(address indexed caller, bool isX);

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (uint256(18) - uint256(decimals));
        else return amount / 10 ** (uint256(decimals) - uint256(18));
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (uint256(18) - uint256(decimals));
        else return amount * 10 ** (uint256(decimals) - uint256(18));
    }

    function _claimFeeShare(
        uint256 fees,
        uint256 dFeesAcc,
        uint256 liquid,
        uint256 allocation
    ) private pure returns (uint256 feeShare, UpdateType[] memory updates) {
        updates = new UpdateType[](2);
        uint256 contributedFees = fees > dFeesAcc ? fees - dFeesAcc : 0;
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        feeShare = (contributedFees * liquidityContribution) / 1e18;
        feeShare = feeShare > fees ? fees : feeShare; // Caps at available fees
        return (feeShare, updates);
    }

    function _processFeeClaim(FeeClaimContext memory context) internal {
        (uint256 feeShare, UpdateType[] memory updates) = _claimFeeShare(
            context.fees,
            context.dFeesAcc,
            context.liquid,
            context.allocation
        );
        if (feeShare > 0) {
            address transferToken = context.isX ? tokenA : tokenB;
            updates[0] = UpdateType(1, context.isX ? 1 : 0, context.fees - feeShare, address(0), address(0));
            updates[1] = UpdateType(context.isX ? 2 : 3, context.liquidityIndex, context.allocation, context.caller, address(0));
            // Reset dFeesAcc to latest feesAcc after claim
            Slot storage slot = context.isX ? xLiquiditySlots[context.liquidityIndex] : yLiquiditySlots[context.liquidityIndex];
            slot.dFeesAcc = context.isX ? liquidityDetail.yFeesAcc : liquidityDetail.xFeesAcc;
            this.update(context.caller, updates);
            this.transact(context.caller, transferToken, feeShare, context.caller);
            emit FeesClaimed(
                listingId,
                context.liquidityIndex,
                context.isX ? feeShare : 0,
                context.isX ? 0 : feeShare
            );
        }
    }

    function setRouters(address[] memory _routers) external {
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
        }
        routersSet = true;
    }

    function setListingId(uint256 _listingId) external {
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setAgent(address _agent) external {
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }

    function update(address caller, UpdateType[] memory updates) external nonReentrant {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;

        for (uint256 i = 0; i < updates.length; i++) {
            UpdateType memory u = updates[i];
            if (u.updateType == 0) {
                if (u.index == 0) details.xLiquid = u.value;
                else if (u.index == 1) details.yLiquid = u.value;
            } else if (u.updateType == 1) {
                if (u.index == 0) {
                    details.xFees += u.value;
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                } else if (u.index == 1) {
                    details.yFees += u.value;
                    emit FeesUpdated(listingId, details.xFees, details.yFees);
                }
            } else if (u.updateType == 2) {
                Slot storage slot = xLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.yFeesAcc; // Store yFeesAcc for xSlot
                    activeXLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                details.xLiquid += u.value;
            } else if (u.updateType == 3) {
                Slot storage slot = yLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    slot.dFeesAcc = details.xFeesAcc; // Store xFeesAcc for ySlot
                    activeYLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dFeesAcc = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                details.yLiquid += u.value;
            }
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function globalizeUpdate(address caller, bool isX, uint256 amount, bool isDeposit) internal {
        if (agent == address(0)) return;
        address token = isX ? tokenA : tokenB;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);
        try ISSAgent(agent).globalizeLiquidity(
            listingId,
            tokenA,
            tokenB,
            caller,
            normalizedAmount,
            isDeposit
        ) {} catch {
            emit GlobalizeUpdateFailed(caller, listingId, isX, amount);
        }
    }

    function updateRegistry(address caller, bool isX) internal {
        address registry = address(0);
        try ISSListing(listingAddress).getRegistryAddress() returns (address reg) {
            registry = reg;
        } catch {
            emit UpdateRegistryFailed(caller, isX);
            return;
        }
        if (registry == address(0)) {
            emit UpdateRegistryFailed(caller, isX);
            return;
        }
        address token = isX ? tokenA : tokenB;
        address[] memory users = new address[](1);
        users[0] = caller;
        try ITokenRegistry(registry).initializeBalances(token, users) {} catch {
            emit UpdateRegistryFailed(caller, isX);
        }
    }

    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant {
        require(routers[msg.sender], "Router only");
        require(newDepositor != address(0), "Invalid new depositor");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == caller, "Caller not depositor");
        require(slot.allocation > 0, "Invalid slot");
        address oldDepositor = slot.depositor;
        slot.depositor = newDepositor;
        for (uint256 i = 0; i < userIndex[oldDepositor].length; i++) {
            if (userIndex[oldDepositor][i] == slotIndex) {
                userIndex[oldDepositor][i] = userIndex[oldDepositor][userIndex[oldDepositor].length - 1];
                userIndex[oldDepositor].pop();
                break;
            }
        }
        userIndex[newDepositor].push(slotIndex);
        emit SlotDepositorChanged(isX, slotIndex, oldDepositor, newDepositor);
    }

    function deposit(address caller, address token, uint256 amount) external payable nonReentrant {
        require(routers[msg.sender], "Router only");
        require(token == tokenA || token == tokenB, "Invalid token");
        require(caller != address(0), "Invalid caller");
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 preBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(token).transferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        uint256 normalizedAmount = normalize(receivedAmount, decimals);

        UpdateType[] memory updates = new UpdateType[](1);
        uint256 index = token == tokenA ? activeXLiquiditySlots.length : activeYLiquiditySlots.length;
        updates[0] = UpdateType(token == tokenA ? 2 : 3, index, normalizedAmount, caller, address(0));
        this.update(caller, updates);
        globalizeUpdate(caller, token == tokenA, receivedAmount, true);
        updateRegistry(caller, token == tokenA);
    }

    function xPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant returns (PreparedWithdrawal memory) {
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        require(slot.allocation >= amount, "Amount exceeds allocation");

        uint256 withdrawAmountA = amount > details.xLiquid ? details.xLiquid : amount;
        uint256 deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0;
        uint256 withdrawAmountB = 0;

        if (deficit > 0) {
            uint256 currentPrice = ISSListing(listingAddress).getPrice();
            require(currentPrice > 0, "Price cannot be zero");
            uint256 compensation = (deficit * 1e18) / currentPrice;
            withdrawAmountB = compensation > details.yLiquid ? details.yLiquid : compensation;
        }

        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function xExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external nonReentrant {
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = xLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amountA, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                (bool success, ) = caller.call{value: amountA}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(caller, amountA);
            }
            globalizeUpdate(caller, true, withdrawal.amountA, false);
            updateRegistry(caller, true);
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                (bool success, ) = caller.call{value: amountB}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(caller, amountB);
            }
            globalizeUpdate(caller, false, withdrawal.amountB, false);
            updateRegistry(caller, false);
        }
    }

    function yPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant returns (PreparedWithdrawal memory) {
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");
        require(slot.allocation >= amount, "Amount exceeds allocation");

        uint256 withdrawAmountB = amount > details.yLiquid ? details.yLiquid : amount;
        uint256 deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0;
        uint256 withdrawAmountA = 0;

        if (deficit > 0) {
            uint256 currentPrice = ISSListing(listingAddress).getPrice();
            require(currentPrice > 0, "Price cannot be zero");
            uint256 compensation = (deficit * currentPrice) / 1e18;
            withdrawAmountA = compensation > details.xLiquid ? details.xLiquid : compensation;
        }

        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function yExecuteOut(address caller, uint256 index, PreparedWithdrawal memory withdrawal) external nonReentrant {
        require(routers[msg.sender], "Router only");
        require(caller != address(0), "Invalid caller");
        Slot storage slot = yLiquiditySlots[index];
        require(slot.depositor == caller, "Caller not depositor");

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amountB, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                (bool success, ) = caller.call{value: amountB}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(caller, amountB);
            }
            globalizeUpdate(caller, false, withdrawal.amountB, false);
            updateRegistry(caller, false);
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                (bool success, ) = caller.call{value: amountA}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(caller, amountA);
            }
            globalizeUpdate(caller, true, withdrawal.amountA, false);
            updateRegistry(caller, true);
        }
    }

    function claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 /* volume */) external nonReentrant {
        require(routers[msg.sender], "Router only");
        require(_listingAddress == listingAddress, "Invalid listing address");
        require(caller != address(0), "Invalid caller");
        (uint256 xBalance, ) = ISSListing(_listingAddress).volumeBalances(listingId);
        require(xBalance > 0, "Invalid listing");
        FeeClaimContext memory context;
        context.caller = caller;
        context.isX = isX;
        context.liquidityIndex = liquidityIndex;
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = isX ? xLiquiditySlots[liquidityIndex] : yLiquiditySlots[liquidityIndex];
        require(slot.depositor == caller, "Caller not depositor");
        context.liquid = isX ? details.xLiquid : details.yLiquid;
        context.fees = isX ? details.yFees : details.xFees;
        context.allocation = slot.allocation;
        context.dFeesAcc = slot.dFeesAcc;
        _processFeeClaim(context);
    }

    function addFees(address caller, bool isX, uint256 fee) external nonReentrant {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        UpdateType[] memory feeUpdates = new UpdateType[](1);
        feeUpdates[0] = UpdateType(1, isX ? 0 : 1, fee, address(0), address(0));
        if (isX) {
            details.xFeesAcc += fee; // Increment cumulative xFeesAcc
        } else {
            details.yFeesAcc += fee; // Increment cumulative yFeesAcc
        }
        this.update(caller, feeUpdates);
    }

    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 normalizedAmount = normalize(amount, decimals);

        if (token == tokenA) {
            require(details.xLiquid >= normalizedAmount, "Insufficient xLiquid");
            details.xLiquid -= normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else if (token == tokenB) {
            require(details.yLiquid >= normalizedAmount, "Insufficient yLiquid");
            details.yLiquid -= normalizedAmount;
            if (token == address(0)) {
                (bool success, ) = recipient.call{value: amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(token).safeTransfer(recipient, amount);
            }
        } else {
            revert("Invalid token");
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function updateLiquidity(address caller, bool isX, uint256 amount) external nonReentrant {
        require(routers[msg.sender], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        if (isX) {
            require(details.xLiquid >= amount, "Insufficient xLiquid");
            details.xLiquid -= amount;
        } else {
            require(details.yLiquid >= amount, "Insufficient yLiquid");
            details.yLiquid -= amount;
        }
        emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
    }

    function getListingAddress(uint256) external view returns (address) {
        return listingAddress;
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees, uint256 xFeesAcc, uint256 yFeesAcc) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees, details.xFeesAcc, details.yFeesAcc);
    }

    function activeXLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeXLiquiditySlots;
    }

    function activeYLiquiditySlotsView() external view returns (uint256[] memory) {
        return activeYLiquiditySlots;
    }

    function userIndexView(address user) external view returns (uint256[] memory) {
        return userIndex[user];
    }

    function getXSlotView(uint256 index) external view returns (Slot memory) {
        return xLiquiditySlots[index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory) {
        return yLiquiditySlots[index];
    }
}