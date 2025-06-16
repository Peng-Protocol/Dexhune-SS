/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-16: Updated Solidity version to ^0.8.2. Version incremented to 0.0.18.
// - 2025-06-14: Added EntryContext struct to support refactored _initiateEntry in SSCrossDriver.sol and helpers in CSDPositionPartial.sol, aligning with isolatedDriver's call tree. Version incremented to 0.0.17.
// - 2025-06-13: Confirmed PositionClosed event for inheritance. Version incremented to 0.0.16.
// - 2025-06-13: Added PositionClosed event, removed from SSCrossDriver.sol. Version incremented to 0.0.15.
// - 2025-06-13: Added DECIMAL_PRECISION, removed from SSCrossDriver.sol. Version incremented to 0.0.14.

pragma solidity ^0.8.2;

import "../imports/SafeERC20.sol";
import "../imports/ReentrancyGuard.sol";
import "../imports/Ownable.sol";

interface ISSListing {
    function prices(address) external view returns (uint256);
    function volumeBalances(address) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView(address) external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    struct PayoutUpdate {
        uint8 payoutType;
        address recipient;
        uint256 required;
    }
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
    struct UpdateType {
        uint8 updateType;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }
    function update(address caller, UpdateType[] calldata updates) external;
}

interface ISSLiquidityTemplate {
    function addFees(address caller, bool isX, uint256 fee) external;
    function liquidityDetailsView(address) external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
}

interface ISSAgent {
    struct ListingDetails {
        address listingAddress;
        address liquidityAddress;
        address tokenA;
        address tokenB;
        uint256 listingId;
    }

    function getListing(address tokenA, address tokenB) external view returns (address);
    function isValidListing(address listingAddress) external view returns (bool isValid, ListingDetails memory details);
}

contract CSDUtilityPartial {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agentAddress;

    event PositionClosed(uint256 indexed positionId, address indexed maker, uint256 payout);

    struct PositionCore1 {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        uint8 positionType;
    }

    struct PositionCore2 {
        bool status1;
        uint8 status2;
    }

    struct PriceParams1 {
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 minPrice;
        uint256 priceAtEntry;
        uint8 leverage;
    }

    struct PriceParams2 {
        uint256 liquidationPrice;
    }

    struct MarginParams1 {
        uint256 initialMargin;
        uint256 taxedMargin;
        uint256 excessMargin;
        uint256 fee;
    }

    struct MarginParams2 {
        uint256 initialLoan;
    }

    struct ExitParams {
        uint256 stopLossPrice;
        uint256 takeProfitPrice;
        uint256 exitPrice;
    }

    struct OpenInterest {
        uint256 leverageAmount;
        uint256 timestamp;
    }

    struct EntryContext {
        uint256 positionId;
        address listingAddress;
        uint256 minEntryPrice;
        uint256 maxEntryPrice;
        uint256 initialMargin;
        uint256 excessMargin;
        uint8 leverage;
        uint8 positionType;
        address maker;
        address token;
    }

    mapping(address => mapping(address => uint256)) public makerTokenMargin;
    mapping(address => address[]) public makerMarginTokens;
    mapping(uint256 => PositionCore1) public positionCore1;
    mapping(uint256 => PositionCore2) public positionCore2;
    mapping(uint256 => PriceParams1) public priceParams1;
    mapping(uint256 => PriceParams2) public priceParams2;
    mapping(uint256 => MarginParams1) public marginParams1;
    mapping(uint256 => MarginParams2) public marginParams2;
    mapping(uint256 => ExitParams) public exitParams;
    mapping(uint256 => OpenInterest) public openInterest;
    mapping(uint8 => uint256[]) public positionsByType;
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions;
    uint256 public positionCount;

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

    function removePositionIndex(uint256 positionId, uint8 positionType, address listingAddress) internal {
        uint256[] storage pending = pendingPositions[listingAddress][positionType];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i] == positionId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                break;
            }
        }
        uint256[] storage active = positionsByType[positionType];
        for (uint256 i = 0; i < active.length; i++) {
            if (active[i] == positionId) {
                active[i] = active[active.length - 1];
                active.pop();
                break;
            }
        }
    }
}