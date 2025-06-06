// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.4 (Updated)
// Changes:
// - v0.0.4: Added changeSlotDepositor to transfer x or y slot ownership, with note that SS router must implement a function to utilize it (lines 376-401).
// - v0.0.4: Added liquidityAmounts() view function for ISSListingTemplate compatibility (lines 583-587).
// - v0.0.4: Added agent state variable and setAgent function for SSAgent compatibility (lines 54, 248-253).
// - v0.0.4: Added globalizeUpdate to sync liquidity with SSAgent.globalizeLiquidity, called in deposit, xExecuteOut, yExecuteOut (lines 314-329, 411, 448, 486).
// - v0.0.4: Added updateRegistry to sync depositor balances with TokenRegistry, called in deposit, xExecuteOut, yExecuteOut (lines 331-347, 412, 449, 487).
// - v0.0.4: Updated xPrepOut, yPrepOut to use ISSListing.getPrice() instead of prices(listingId) (lines 418, 452).
// - v0.0.4: Simplified mappings: liquidityDetails to liquidityDetail, x/yLiquiditySlots to remove listingId key, activeX/YLiquiditySlots to arrays (lines 68-73).
// - v0.0.4: Removed taxCollector, taxCollectorSet, and setCollector; removed 10% fee logic in xExecuteOut, yExecuteOut (lines 54-58, 429-430, 465-467).
// - v0.0.4: Updated ISSListing interface to include getPrice, getRegistryAddress (lines 34-37).
// - v0.0.4: Added ISSAgent interface for globalizeLiquidity (lines 28-34).
// - v0.0.4: Added ITokenRegistry interface for updateRegistry (lines 39-41).
// - v0.0.3: Modified claimFees to align with fee-swapping: xSlots claim yFees (tokenB), ySlots claim xFees (tokenA); updated FeesClaimed event (lines 496-523).
// - Note: Preserved fee-swapping in claimFees, unlike OMF-LiquidityTemplate.sol's same-token fees.
// - Note: Maintained routers mapping instead of OMF's single router.
// - Note: Maintained ETH support unlike OMF's non-native token requirement.
// - Note: DecimalsA/decimalsB not addressed, as deferred previously.
// - Compatible with SS-ListingTemplate.sol (v0.0.5), SSAgent.sol (v0.0.2).

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";

interface ISSListing {
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
    function getPrice() external view returns (uint256);
    function getRegistryAddress() external view returns (address);
}

interface ISSAgent {
    function globalizeLiquidity(
        uint256 listingId,
        address tokenA,
        address tokenB,
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
    }

    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dVolume;
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
        uint256 volume,
        uint256 dVolume,
        uint256 liquid,
        uint256 allocation,
        uint256 fees
    ) private pure returns (uint256 feeShare, UpdateType[] memory updates) {
        updates = new UpdateType[](2);
        uint256 contributedVolume = volume > dVolume ? volume - dVolume : 0;
        uint256 feesAccrued = (contributedVolume * 5) / 10000;
        uint256 liquidityContribution = liquid > 0 ? (allocation * 1e18) / liquid : 0;
        feeShare = (feesAccrued * liquidityContribution) / 1e18;
        feeShare = feeShare > fees ? fees : feeShare;
        return (feeShare, updates);
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
        require(routers[caller], "Router only");
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
                    activeXLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dVolume = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                (, , uint256 xVolume, ) = ISSListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = xVolume;
                details.xLiquid += u.value;
            } else if (u.updateType == 3) {
                Slot storage slot = yLiquiditySlots[u.index];
                if (slot.depositor == address(0) && u.addr != address(0)) {
                    slot.depositor = u.addr;
                    slot.timestamp = block.timestamp;
                    activeYLiquiditySlots.push(u.index);
                    userIndex[u.addr].push(u.index);
                } else if (u.addr == address(0)) {
                    slot.depositor = address(0);
                    slot.allocation = 0;
                    slot.dVolume = 0;
                    for (uint256 j = 0; j < userIndex[slot.depositor].length; j++) {
                        if (userIndex[slot.depositor][j] == u.index) {
                            userIndex[slot.depositor][j] = userIndex[slot.depositor][userIndex[slot.depositor].length - 1];
                            userIndex[slot.depositor].pop();
                            break;
                        }
                    }
                }
                slot.allocation = u.value;
                (, , , uint256 yVolume) = ISSListing(listingAddress).volumeBalances(listingId);
                slot.dVolume = yVolume;
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
        ) {} catch {}
    }

    function updateRegistry(address caller, bool isX) internal {
        address registry = address(0);
        try ISSListing(listingAddress).getRegistryAddress() returns (address reg) {
            registry = reg;
        } catch {
            return;
        }
        if (registry == address(0)) return;
        address token = isX ? tokenA : tokenB;
        address[] memory users = new address[](1);
        users[0] = caller;
        try ITokenRegistry(registry).initializeBalances(token, users) {} catch {}
    }

    // Note: The SS router must implement a function to call changeSlotDepositor to facilitate slot ownership transfers.
    function changeSlotDepositor(address caller, bool isX, uint256 slotIndex, address newDepositor) external nonReentrant {
        require(routers[caller], "Router only");
        require(newDepositor != address(0), "Invalid new depositor");
        Slot storage slot = isX ? xLiquiditySlots[slotIndex] : yLiquiditySlots[slotIndex];
        require(slot.depositor == caller, "Not depositor");
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
        require(routers[caller], "Router only");
        require(token == tokenA || token == tokenB, "Invalid token");
        uint8 decimals = token == address(0) ? 18 : IERC20(token).decimals();
        uint256 preBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        if (token == address(0)) {
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
        uint256 postBalance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 receivedAmount = postBalance - preBalance;
        uint256 normalizedAmount = normalize(receivedAmount, decimals);

        UpdateType[] memory updates = new UpdateType[](1);
        uint256 index = token == tokenA ? activeXLiquiditySlots.length : activeYLiquiditySlots.length;
        updates[0] = UpdateType(token == tokenA ? 2 : 3, index, normalizedAmount, msg.sender, address(0));
        this.update(caller, updates);
        globalizeUpdate(caller, token == tokenA, receivedAmount, true);
        updateRegistry(caller, token == tokenA);
    }

    function xPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant returns (PreparedWithdrawal memory) {
        require(routers[caller], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = xLiquiditySlots[index];
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
        require(routers[caller], "Router only");
        Slot storage slot = xLiquiditySlots[index];

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(2, index, slot.allocation - withdrawal.amountA, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                (bool success, ) = slot.depositor.call{value: amountA}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(slot.depositor, amountA);
            }
            globalizeUpdate(caller, true, withdrawal.amountA, false);
            updateRegistry(caller, true);
        }
        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                (bool success, ) = slot.depositor.call{value: amountB}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(slot.depositor, amountB);
            }
            globalizeUpdate(caller, false, withdrawal.amountB, false);
            updateRegistry(caller, false);
        }
    }

    function yPrepOut(address caller, uint256 amount, uint256 index) external nonReentrant returns (PreparedWithdrawal memory) {
        require(routers[caller], "Router only");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = yLiquiditySlots[index];
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
        require(routers[caller], "Router only");
        Slot storage slot = yLiquiditySlots[index];

        UpdateType[] memory updates = new UpdateType[](1);
        updates[0] = UpdateType(3, index, slot.allocation - withdrawal.amountB, slot.depositor, address(0));
        this.update(caller, updates);

        if (withdrawal.amountB > 0) {
            uint8 decimalsB = tokenB == address(0) ? 18 : IERC20(tokenB).decimals();
            uint256 amountB = denormalize(withdrawal.amountB, decimalsB);
            if (tokenB == address(0)) {
                (bool success, ) = slot.depositor.call{value: amountB}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenB).safeTransfer(slot.depositor, amountB);
            }
            globalizeUpdate(caller, false, withdrawal.amountB, false);
            updateRegistry(caller, false);
        }
        if (withdrawal.amountA > 0) {
            uint8 decimalsA = tokenA == address(0) ? 18 : IERC20(tokenA).decimals();
            uint256 amountA = denormalize(withdrawal.amountA, decimalsA);
            if (tokenA == address(0)) {
                (bool success, ) = slot.depositor.call{value: amountA}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(tokenA).safeTransfer(slot.depositor, amountA);
            }
            globalizeUpdate(caller, true, withdrawal.amountA, false);
            updateRegistry(caller, true);
        }
    }

    function claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external nonReentrant {
        require(routers[caller], "Router only");
        require(_listingAddress == listingAddress, "Invalid listing address");
        (uint256 xBalance, , , ) = ISSListing(_listingAddress).volumeBalances(listingId);
        require(xBalance > 0, "Invalid listing");
        LiquidityDetails storage details = liquidityDetail;
        Slot storage slot = isX ? xLiquiditySlots[liquidityIndex] : yLiquiditySlots[liquidityIndex];
        require(slot.depositor == msg.sender, "Not depositor");

        uint256 liquid = isX ? details.xLiquid : details.yLiquid;
        uint256 fees = isX ? details.yFees : details.xFees;
        uint256 allocation = slot.allocation;
        uint256 dVolume = slot.dVolume;

        (uint256 feeShare, UpdateType[] memory updates) = _claimFeeShare(volume, dVolume, liquid, allocation, fees);
        if (feeShare > 0) {
            updates[0] = UpdateType(1, isX ? 1 : 0, fees - feeShare, address(0), address(0));
            updates[1] = UpdateType(isX ? 2 : 3, liquidityIndex, allocation, msg.sender, address(0));
            this.update(caller, updates);

            this.transact(caller, isX ? tokenB : tokenA, feeShare, msg.sender);
            emit FeesClaimed(listingId, liquidityIndex, isX ? 0 : feeShare, isX ? feeShare : 0);
        }
    }

    function transact(address caller, address token, uint256 amount, address recipient) external nonReentrant {
        require(routers[caller], "Router only");
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

    function addFees(address caller, bool isX, uint256 fee) external nonReentrant {
        require(routers[caller], "Router only");
        UpdateType[] memory feeUpdates = new UpdateType[](1);
        feeUpdates[0] = UpdateType(1, isX ? 0 : 1, fee, address(0), address(0));
        this.update(caller, feeUpdates);
    }

    function updateLiquidity(address caller, bool isX, uint256 amount) external nonReentrant {
        require(routers[caller], "Router only");
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

    function transferLiquidity(uint256 liquidityIndex, address newDepositor) external nonReentrant {
        Slot storage xSlot = xLiquiditySlots[liquidityIndex];
        require(xSlot.depositor == msg.sender, "Not depositor");

        UpdateType[] memory updates = new UpdateType[](2);
        updates[0] = UpdateType(2, liquidityIndex, xSlot.allocation, newDepositor, address(0));
        updates[1] = UpdateType(3, liquidityIndex, xSlot.allocation, newDepositor, address(0));
        this.update(msg.sender, updates);
    }

function getListingAddress(uint256) external view returns (address) {
        return listingAddress;
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) {
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees);
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