/*
 SPDX-License-Identifier: BSL-1.1 - Peng Protocol 2025

 // Version: 0.1.20
// Changes:
// - v0.1.20: Added updateType 8 to subtract fees from xFees/yFees in ccUpdate, ensuring compatibility with CCLiquidPartial.sol v0.0.41 fee deductions.
// - v0.1.19: Modified transactToken and transactNative to limit withdrawals based on xLiquid/yLiquid.
 // - v0.1.18: Added updateType 6 (xSlot dFeesAcc update) and 7 (ySlot dFeesAcc update) in ccUpdate to update dFeesAcc without modifying allocation or liquidity, for fee claim corrections.
 // - v0.1.17: Removed xLiquid/yLiquid reduction in transactToken and transactNative to prevent double reduction, as ccUpdate handles liquidity adjustments for slot allocation changes. Removed redundant LiquidityUpdated emission, as ccUpdate emits it.
 // - v0.1.16: Added logic for updateType 4 (xSlot depositor change) and 5 (ySlot depositor change) in ccUpdate to update depositor field and userXIndex/userYIndex mappings. Emits SlotDepositorChanged event. Ensured no impact on xLiquid/yLiquid.
// - v0.1.15: Removed unnecessary checks innccUpdate. 
// - v0.1.14: Modified ccUpdate to skip allocation check for new slots (slot.depositor == address(0)) for updateType 2 and 3, allowing deposits to initialize slots with zero allocation.
// - v0.1.13: Updated ccUpdate for updateType 2 and 3 to subtract allocation difference from xLiquid/yLiquid, preventing liquidity inflation during withdrawals. Added validation for slot.allocation >= u.value.
// - v0.1.12: Added updateType 4 (xSlot depositor change) and 5 (ySlot depositor change) to ccUpdate to update only depositor address without modifying xLiquid/yLiquid. Ensures correct depositor change behavior.
 * - v0.1.11: Hid routerAddresses as routerAddresses view is better. 
 * - v0.1.10: Removed updateLiquidity as ccUpdate is sufficient.
 * - v0.1.7: Removed xPrepOut, xExecuteOut, yPrepOut, yExecuteOut, moving withdrawal logic to CCLiquidityPartial.sol. Renamed update to ccUpdate to avoid call forwarding and ensure router is msg.sender.
 * - v0.1.6: Added resetRouters function to fetch lister from agent, restrict to lister, and update routers array with agent's routers.
// - v0.1.5: Removed routers[msg.sender] check from xPrepOut and yPrepOut to allow user-initiated calls via CCLiquidityRouter.sol. Kept restriction in xExecuteOut and yExecuteOut for state-changing operations.
 - v0.1.4: Removed fixed gas limit in globalizeUpdate for ICCAgent.globalizerAddress and ITokenRegistry.initializeBalances. Modified globalizeUpdate to emit event on failure without reverting, ensuring deposits succeed. Consolidated registry update into globalizeUpdate for atomicity. Maintained compatibility with CCGlobalizer.sol v0.2.1, CCSEntryPartial.sol v0.0.18.
 - v0.1.3: Removed duplicate subtraction in transactToken and transactNative, as xExecuteOut/yExecuteOut already handle subtraction via update calls. Modified balance checks in transactToken and transactNative to use xLiquid/yLiquid instead of total contract balance, ensuring fees are excluded from liquidity operations.
 - v0.1.2: Integrated update function calls with updateType == 0 for subtraction. No new updateType added. Maintained fee segregation and compatibility with CCGlobalizer.sol v0.2.1, CCSEntryPartial.sol v0.0.18.
 Compatible with CCListingTemplate.sol (v0.0.10), CCMainPartial.sol (v0.0.10), CCLiquidityRouter.sol (v0.0.25), ICCLiquidity.sol (v0.0.4), ICCListing.sol (v0.0.7), CCSEntryPartial.sol (v0.0.18), CCGlobalizer.sol (v0.2.1).
*/

pragma solidity ^0.8.2;

import "../imports/IERC20.sol";

interface ICCListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
}

interface ICCAgent {
    function getLister(address listingAddress) external view returns (address);
    function getRouters() external view returns (address[] memory);
    function globalizerAddress() external view returns (address);
    function registryAddress() external view returns (address);
}

interface ITokenRegistry {
    function initializeBalances(address token, address[] memory users) external;
}

interface ICCGlobalizer {
    function globalizeLiquidity(address depositor, address token) external;
}

contract CCLiquidityTemplate {
    mapping(address router => bool isRouter) public routers;
    address[] private routerAddresses;
    bool private routersSet;
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
        uint256 xFeesAcc;
        uint256 yFeesAcc;
    }

    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dFeesAcc;
        uint256 timestamp;
    }

    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }

    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    LiquidityDetails private liquidityDetail;
    mapping(uint256 slotID => Slot) private xLiquiditySlots;
    mapping(uint256 slotID => Slot) private yLiquiditySlots;
    uint256[] private activeXLiquiditySlots;
    uint256[] private activeYLiquiditySlots;
    mapping(address => uint256[]) private userXIndex;
    mapping(address => uint256[]) private userYIndex;

    event LiquidityUpdated(uint256 indexed listingId, uint256 xLiquid, uint256 yLiquid);
    event FeesUpdated(uint256 indexed listingId, uint256 xFees, uint256 yFees);
    event SlotDepositorChanged(bool isX, uint256 indexed slotIndex, address indexed oldDepositor, address indexed newDepositor);
    event GlobalizeUpdateFailed(address indexed depositor, uint256 listingId, bool isX, uint256 amount, bytes reason);
    event UpdateRegistryFailed(address indexed depositor, bool isX, bytes reason);
    event TransactFailed(address indexed depositor, address token, uint256 amount, string reason);

// Added Payout mappings/arrays/structs

uint256 private nextPayoutId; // Tracks next payout ID
struct LongPayoutStruct {
    address makerAddress; // Payout creator
    address recipientAddress; // Payout recipient
    uint256 required; // Amount required
    uint256 filled; // Amount filled
    uint256 amountSent; // Amount of opposite token sent
    uint256 orderId; // Payout order ID
    uint8 status; // 0: cancelled, 1: pending, 2: partially filled, 3: filled
}
struct ShortPayoutStruct {
        address makerAddress;
        address recipientAddress;
        uint256 amount;
        uint256 filled;
        uint256 amountSent; // Added for payout settlement tracking
        uint256 orderId;
        uint8 status;
    }
    
struct PayoutUpdate {
    uint8 payoutType; // 0: Long, 1: Short
    address recipient; // Payout recipient
    uint256 orderId; // Explicit orderId for targeting
    uint256 required; // Amount required for payout
    uint256 filled; // Amount filled during settlement
    uint256 amountSent; // Amount of opposite token sent
}
mapping(uint256 orderId => LongPayoutStruct) private longPayout; // Stores long payout details
mapping(uint256 orderId => ShortPayoutStruct) private shortPayout; // Stores short payout details
uint256[] private longPayoutByIndex; // Tracks long payout orderIds
uint256[] private shortPayoutByIndex; // Tracks short payout orderIds
mapping(address user => uint256[] orderIds) private userPayoutIDs; // Tracks payout orderIds per user
uint256[] private activeLongPayouts; // Tracks active long payout orderIds
uint256[] private activeShortPayouts; // Tracks active short payout orderIds
mapping(address user => uint256[] orderIds) private activeUserPayoutIDs; // Tracks active payout orderIds per user

event PayoutOrderCreated(uint256 indexed orderId, bool isLong, uint8 status);
event PayoutOrderUpdated(uint256 indexed orderId, bool isLong, uint256 filled, uint256 amountSent, uint8 status);

function removePendingOrder(uint256[] storage orders, uint256 orderId) internal {
    // Removes order ID from array
    for (uint256 i = 0; i < orders.length; i++) {
        if (orders[i] == orderId) {
            orders[i] = orders[orders.length - 1];
            orders.pop();
            break;
        }
    }
}

function getNextPayoutID() external view returns (uint256 payoutId) {
    // Returns the next available payout ID
    return nextPayoutId;
}

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256 normalizedAmount) {
        // Normalizes amount to 18 decimals
        if (decimals == 18) return amount;
        if (decimals < 18) return amount * 10 ** (18 - decimals);
        return amount / 10 ** (decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256 denormalizedAmount) {
        // Denormalizes amount from 18 decimals
        if (decimals == 18) return amount;
        if (decimals < 18) return amount / 10 ** (18 - decimals);
        return amount * 10 ** (decimals - 18);
    }

    function globalizeUpdate(address depositor, address token, bool isX, uint256 amount) internal {
        // Handles globalization and registry updates, emits events on failure without reverting
        if (agent != address(0)) {
            address globalizer;
            try ICCAgent(agent).globalizerAddress() returns (address glob) {
                globalizer = glob;
            } catch (bytes memory reason) {
                emit GlobalizeUpdateFailed(depositor, listingId, isX, amount, reason);
                return;
            }
            if (globalizer != address(0)) {
                try ICCGlobalizer(globalizer).globalizeLiquidity(depositor, token) {
                } catch (bytes memory reason) {
                    emit GlobalizeUpdateFailed(depositor, listingId, isX, amount, reason);
                    return;
                }
            }
            address registry;
            try ICCAgent(agent).registryAddress() returns (address reg) {
                registry = reg;
            } catch (bytes memory reason) {
                emit UpdateRegistryFailed(depositor, isX, reason);
                return;
            }
            if (registry != address(0)) {
                address[] memory users = new address[](1);
                users[0] = depositor;
                try ITokenRegistry(registry).initializeBalances(token, users) {
                } catch (bytes memory reason) {
                    emit UpdateRegistryFailed(depositor, isX, reason);
                }
            }
        }
    }

    function setRouters(address[] memory _routers) external {
        // Sets router addresses, callable once
        require(!routersSet, "Routers already set");
        require(_routers.length > 0, "No routers provided");
        for (uint256 i = 0; i < _routers.length; i++) {
            require(_routers[i] != address(0), "Invalid router address");
            routers[_routers[i]] = true;
            routerAddresses.push(_routers[i]);
        }
        routersSet = true;
    }

    function setListingId(uint256 _listingId) external {
        // Sets listing ID, callable once
        require(listingId == 0, "Listing ID already set");
        listingId = _listingId;
    }

    function setListingAddress(address _listingAddress) external {
        // Sets listing address, callable once
        require(listingAddress == address(0), "Listing already set");
        require(_listingAddress != address(0), "Invalid listing address");
        listingAddress = _listingAddress;
    }

    function setTokens(address _tokenA, address _tokenB) external {
        // Sets token pair, callable once
        require(tokenA == address(0) && tokenB == address(0), "Tokens already set");
        require(_tokenA != _tokenB, "Tokens must be different");
        require(_tokenA != address(0) || _tokenB != address(0), "Both tokens cannot be zero");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function setAgent(address _agent) external {
        // Sets agent address, callable once
        require(agent == address(0), "Agent already set");
        require(_agent != address(0), "Invalid agent address");
        agent = _agent;
    }
    
    // Resets routers array to agent's latest routers, restricted to lister
function resetRouters() external {
    // Fetch lister from agent for the current listing
    address lister = ICCAgent(agent).getLister(listingAddress);
    require(msg.sender == lister, "Only lister can reset routers");
    
    // Fetch latest routers from agent
    address[] memory newRouters = ICCAgent(agent).getRouters();
    require(newRouters.length > 0, "No routers available in agent");

    // Clear existing routers mapping and array
    for (uint256 i = 0; i < routerAddresses.length; i++) {
        routers[routerAddresses[i]] = false;
    }
    delete routerAddresses;

    // Update with new routers
    for (uint256 i = 0; i < newRouters.length; i++) {
        require(newRouters[i] != address(0), "Invalid router address");
        routers[newRouters[i]] = true;
        routerAddresses.push(newRouters[i]);
    }
    routersSet = true;
}

function transactToken(address depositor, address token, uint256 amount, address recipient) external {
    // Transfers ERC20 tokens, limited by xLiquid/yLiquid, restricted to routers
    require(routers[msg.sender], "Router only");
    require(token == tokenA || token == tokenB, "Invalid token");
    require(token != address(0), "Use transactNative for ETH");
    require(amount > 0, "Zero amount");
    require(recipient != address(0), "Invalid recipient");
    uint8 decimals = IERC20(token).decimals();
    if (decimals == 0) revert("Invalid token decimals");
    uint256 normalizedAmount = normalize(amount, decimals);
    require((token == tokenA ? liquidityDetail.xLiquid : liquidityDetail.yLiquid) >= normalizedAmount, "Insufficient liquidity");
    try IERC20(token).transfer(recipient, amount) returns (bool) {
    } catch (bytes memory reason) {
        emit TransactFailed(depositor, token, amount, "Token transfer failed");
        revert("Token transfer failed");
    }
}

function transactNative(address depositor, uint256 amount, address recipient) external {
    // Transfers ETH, limited by xLiquid/yLiquid, restricted to routers
    require(routers[msg.sender], "Router only");
    require(tokenA == address(0) || tokenB == address(0), "No native token in pair");
    require(amount > 0, "Zero amount");
    require(recipient != address(0), "Invalid recipient");
    uint256 normalizedAmount = normalize(amount, 18);
    require((tokenA == address(0) ? liquidityDetail.xLiquid : liquidityDetail.yLiquid) >= normalizedAmount, "Insufficient liquidity");
    (bool success, bytes memory reason) = recipient.call{value: amount}("");
    if (!success) {
        emit TransactFailed(depositor, address(0), amount, "ETH transfer failed");
        revert("ETH transfer failed");
    }
}

// Added payout creation/management from listing template
function ssUpdate(PayoutUpdate[] calldata updates) external {
    // Updates payout details, restricted to routers
    require(routers[msg.sender], "Router only");
    for (uint256 i = 0; i < updates.length; i++) {
        PayoutUpdate memory u = updates[i];
        if (u.recipient == address(0)) {
            emit UpdateRegistryFailed(u.recipient, u.payoutType == 0, "Invalid recipient");
            continue;
        }
        if (u.payoutType > 1) {
            emit UpdateRegistryFailed(u.recipient, u.payoutType == 0, "Invalid payout type");
            continue;
        }
        if (u.required == 0 && u.filled == 0) {
            emit UpdateRegistryFailed(u.recipient, u.payoutType == 0, "Invalid required or filled amount");
            continue;
        }
        bool isLong = u.payoutType == 0;
        uint256 orderId = u.orderId;
        if (isLong) {
            LongPayoutStruct storage payout = longPayout[orderId];
            if (payout.orderId == 0) { // New payout
                payout.makerAddress = u.recipient;
                payout.recipientAddress = u.recipient;
                payout.required = u.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = u.required > 0 ? 1 : 0;
                longPayoutByIndex.push(orderId);
                userPayoutIDs[u.recipient].push(orderId);
                if (payout.status == 1) { // Add to active arrays only if pending
                    activeLongPayouts.push(orderId);
                    activeUserPayoutIDs[u.recipient].push(orderId);
                }
                emit PayoutOrderCreated(orderId, true, payout.status);
            } else { // Update existing payout
                if (u.filled > 0) payout.filled = u.filled;
                if (u.amountSent > 0) payout.amountSent = u.amountSent;
                if (u.required > 0) payout.required = u.required;
                uint8 oldStatus = payout.status;
                payout.status = u.filled >= payout.required ? 3 : (u.filled > 0 ? 2 : 1);
                if ((payout.status == 0 || payout.status == 3) && oldStatus == 1) {
                    removePendingOrder(activeLongPayouts, orderId);
                    removePendingOrder(activeUserPayoutIDs[u.recipient], orderId);
                } else if (payout.status == 1 && oldStatus != 1) {
                    activeLongPayouts.push(orderId);
                    activeUserPayoutIDs[u.recipient].push(orderId);
                }
                emit PayoutOrderUpdated(orderId, true, payout.filled, payout.amountSent, payout.status);
            }
        } else {
            ShortPayoutStruct storage payout = shortPayout[orderId];
            if (payout.orderId == 0) { // New payout
                payout.makerAddress = u.recipient;
                payout.recipientAddress = u.recipient;
                payout.amount = u.required;
                payout.filled = 0;
                payout.orderId = orderId;
                payout.status = u.required > 0 ? 1 : 0;
                shortPayoutByIndex.push(orderId);
                userPayoutIDs[u.recipient].push(orderId);
                if (payout.status == 1) { // Add to active arrays only if pending
                    activeShortPayouts.push(orderId);
                    activeUserPayoutIDs[u.recipient].push(orderId);
                }
                emit PayoutOrderCreated(orderId, false, payout.status);
            } else { // Update existing payout
                if (u.filled > 0) payout.filled = u.filled;
                if (u.amountSent > 0) payout.amountSent = u.amountSent;
                if (u.required > 0) payout.amount = u.required;
                uint8 oldStatus = payout.status;
                payout.status = u.filled >= payout.amount ? 3 : (u.filled > 0 ? 2 : 1);
                if ((payout.status == 0 || payout.status == 3) && oldStatus == 1) {
                    removePendingOrder(activeShortPayouts, orderId);
                    removePendingOrder(activeUserPayoutIDs[u.recipient], orderId);
                } else if (payout.status == 1 && oldStatus != 1) {
                    activeShortPayouts.push(orderId);
                    activeUserPayoutIDs[u.recipient].push(orderId);
                }
                emit PayoutOrderUpdated(orderId, false, payout.filled, payout.amountSent, payout.status);
            }
        }
        if (longPayout[orderId].orderId == 0 && shortPayout[orderId].orderId == 0) {
            nextPayoutId = orderId + 1; // Increment nextPayoutId for new payouts
        }
    }
}

// Renamed from "update"
// Added changeDepositor update type
// Added fee deduction update type
    function ccUpdate(address depositor, UpdateType[] memory updates) external {
    // Updates liquidity and slot details, including dFeesAcc and fee subtraction
    require(routers[msg.sender], "Router only");
    LiquidityDetails storage details = liquidityDetail;
    for (uint256 i = 0; i < updates.length; i++) {
        UpdateType memory u = updates[i];
        if (u.updateType == 0) {
            // Updates xLiquid or yLiquid directly
            if (u.index == 0) {
                details.xLiquid = u.value;
            } else if (u.index == 1) {
                details.yLiquid = u.value;
            } else revert("Invalid balance index");
        } else if (u.updateType == 1) {
            // Updates xFees or yFees (addition)
            if (u.index == 0) {
                details.xFees += u.value;
                emit FeesUpdated(listingId, details.xFees, details.yFees);
            } else if (u.index == 1) {
                details.yFees += u.value;
                emit FeesUpdated(listingId, details.xFees, details.yFees);
            } else revert("Invalid fee index");
        } else if (u.updateType == 2) {
            // Updates xSlot allocation and liquidity
            Slot storage slot = xLiquiditySlots[u.index];
            if (slot.depositor == address(0) && u.addr != address(0)) {
                slot.depositor = u.addr;
                slot.timestamp = block.timestamp;
                slot.dFeesAcc = details.yFeesAcc;
                activeXLiquiditySlots.push(u.index);
                userXIndex[u.addr].push(u.index);
            } else if (u.addr == address(0)) {
                slot.depositor = address(0);
                slot.allocation = 0;
                slot.dFeesAcc = 0;
                for (uint256 j = 0; j < userXIndex[slot.depositor].length; j++) {
                    if (userXIndex[slot.depositor][j] == u.index) {
                        userXIndex[slot.depositor][j] = userXIndex[slot.depositor][userXIndex[slot.depositor].length - 1];
                        userXIndex[slot.depositor].pop();
                        break;
                    }
                }
            }
            uint256 oldAllocation = slot.allocation;
            slot.allocation = u.value;
            if (oldAllocation > u.value) {
                details.xLiquid -= (oldAllocation - u.value);
            } else {
                details.xLiquid += (u.value - oldAllocation);
            }
            globalizeUpdate(depositor, tokenA, true, u.value);
        } else if (u.updateType == 3) {
            // Updates ySlot allocation and liquidity
            Slot storage slot = yLiquiditySlots[u.index];
            if (slot.depositor == address(0) && u.addr != address(0)) {
                slot.depositor = u.addr;
                slot.timestamp = block.timestamp;
                slot.dFeesAcc = details.xFeesAcc;
                activeYLiquiditySlots.push(u.index);
                userYIndex[u.addr].push(u.index);
            } else if (u.addr == address(0)) {
                slot.depositor = address(0);
                slot.allocation = 0;
                slot.dFeesAcc = 0;
                for (uint256 j = 0; j < userYIndex[slot.depositor].length; j++) {
                    if (userYIndex[slot.depositor][j] == u.index) {
                        userYIndex[slot.depositor][j] = userYIndex[slot.depositor][userYIndex[slot.depositor].length - 1];
                        userYIndex[slot.depositor].pop();
                        break;
                    }
                }
            }
            uint256 oldAllocation = slot.allocation;
            slot.allocation = u.value;
            if (oldAllocation > u.value) {
                details.yLiquid -= (oldAllocation - u.value);
            } else {
                details.yLiquid += (u.value - oldAllocation);
            }
            globalizeUpdate(depositor, tokenB, false, u.value);
        } else if (u.updateType == 4) {
            // Updates xSlot depositor without modifying allocation or liquidity
            Slot storage slot = xLiquiditySlots[u.index];
            require(slot.depositor == depositor, "Depositor not slot owner");
            require(u.addr != address(0), "Invalid new depositor");
            require(slot.allocation > 0, "Invalid slot allocation");
            address oldDepositor = slot.depositor;
            slot.depositor = u.addr;
            for (uint256 j = 0; j < userXIndex[oldDepositor].length; j++) {
                if (userXIndex[oldDepositor][j] == u.index) {
                    userXIndex[oldDepositor][j] = userXIndex[oldDepositor][userXIndex[oldDepositor].length - 1];
                    userXIndex[oldDepositor].pop();
                    break;
                }
            }
            userXIndex[u.addr].push(u.index);
            emit SlotDepositorChanged(true, u.index, oldDepositor, u.addr);
        } else if (u.updateType == 5) {
            // Updates ySlot depositor without modifying allocation or liquidity
            Slot storage slot = yLiquiditySlots[u.index];
            require(slot.depositor == depositor, "Depositor not slot owner");
            require(u.addr != address(0), "Invalid new depositor");
            require(slot.allocation > 0, "Invalid slot allocation");
            address oldDepositor = slot.depositor;
            slot.depositor = u.addr;
            for (uint256 j = 0; j < userYIndex[oldDepositor].length; j++) {
                if (userYIndex[oldDepositor][j] == u.index) {
                    userYIndex[oldDepositor][j] = userYIndex[oldDepositor][userYIndex[oldDepositor].length - 1];
                    userYIndex[oldDepositor].pop();
                    break;
                }
            }
            userYIndex[u.addr].push(u.index);
            emit SlotDepositorChanged(false, u.index, oldDepositor, u.addr);
        } else if (u.updateType == 6) {
            // Updates xSlot dFeesAcc for fee claims
            Slot storage slot = xLiquiditySlots[u.index];
            require(slot.depositor == depositor, "Depositor not slot owner");
            slot.dFeesAcc = u.value;
        } else if (u.updateType == 7) {
            // Updates ySlot dFeesAcc for fee claims
            Slot storage slot = yLiquiditySlots[u.index];
            require(slot.depositor == depositor, "Depositor not slot owner");
            slot.dFeesAcc = u.value;
        } else if (u.updateType == 8) {
            // Subtracts from xFees
            if (u.index == 0) {
                require(details.xFees >= u.value, "Insufficient xFees");
                details.xFees -= u.value;
                emit FeesUpdated(listingId, details.xFees, details.yFees);
            } else revert("Invalid fee index");
        } else if (u.updateType == 9) {
            // Subtracts from yFees
            if (u.index == 1) {
                require(details.yFees >= u.value, "Insufficient yFees");
                details.yFees -= u.value;
                emit FeesUpdated(listingId, details.xFees, details.yFees);
            } else revert("Invalid fee index");
        } else revert("Invalid update type");
    }
    emit LiquidityUpdated(listingId, details.xLiquid, details.yLiquid);
}
    
    function getListingAddress(uint256) external view returns (address listingAddressReturn) {
        // Returns listing address
        return listingAddress;
    }

    function liquidityAmounts() external view returns (uint256 xAmount, uint256 yAmount) {
        // Returns liquidity amounts
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid);
    }

    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees) {
        // Returns liquidity details for CCSEntryPartial compatibility
        LiquidityDetails memory details = liquidityDetail;
        return (details.xLiquid, details.yLiquid, details.xFees, details.yFees);
    }

    function userXIndexView(address user) external view returns (uint256[] memory indices) {
        // Returns user's xLiquidity slot indices
        return userXIndex[user];
    }

    function userYIndexView(address user) external view returns (uint256[] memory indices) {
        // Returns user's yLiquidity slot indices
        return userYIndex[user];
    }

    function getActiveXLiquiditySlots() external view returns (uint256[] memory slots) {
        // Returns active xLiquidity slots
        return activeXLiquiditySlots;
    }

    function getActiveYLiquiditySlots() external view returns (uint256[] memory slots) {
        // Returns active yLiquidity slots
        return activeYLiquiditySlots;
    }

    function getXSlotView(uint256 index) external view returns (Slot memory slot) {
        // Returns xLiquidity slot details
        return xLiquiditySlots[index];
    }

    function getYSlotView(uint256 index) external view returns (Slot memory slot) {
        // Returns yLiquidity slot details
        return yLiquiditySlots[index];
    }

    function routerAddressesView() external view returns (address[] memory addresses) {
        // Returns router addresses
        return routerAddresses;
    }
    
    // Added Payout view functions 

function userPayoutIDsView(address user) external view returns (uint256[] memory orderIds) {
    // Returns payout order IDs for a user
    return userPayoutIDs[user];
}

function activeLongPayoutsView() external view returns (uint256[] memory orderIds) {
    // Returns active long payout order IDs
    return activeLongPayouts;
}

function activeShortPayoutsView() external view returns (uint256[] memory orderIds) {
    // Returns active short payout order IDs
    return activeShortPayouts;
}

function activeUserPayoutIDsView(address user) external view returns (uint256[] memory orderIds) {
    // Returns active payout order IDs for a user
    return activeUserPayoutIDs[user];
}

function getLongPayout(uint256 orderId) external view returns (LongPayoutStruct memory payout) {
    // Returns long payout details
    return longPayout[orderId];
}

function getShortPayout(uint256 orderId) external view returns (ShortPayoutStruct memory payout) {
    // Returns short payout details
    return shortPayout[orderId];
}
}