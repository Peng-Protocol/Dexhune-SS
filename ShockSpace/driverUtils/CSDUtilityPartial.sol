/*
 SPDX-License-Identifier: BSD-3-Clause
*/

// Recent Changes:
// - 2025-06-02: Added UpdateType struct and update function to ISSListing interface for volume balance updates. Version incremented to 0.0.7 for pre-testing.
// - 2025-05-31: Added positionCount state variable to resolve undeclared identifier error in CSDExecutionPartial.
// - 2025-05-31: Version incremented to 0.0.6 for pre-testing.
// - 2025-05-31: Moved PositionCore1, PositionCore2, PriceParams1, PriceParams2, MarginParams1, MarginParams2, ExitParams, and OpenInterest structs and mappings from SSCrossDriver.sol to resolve identifier errors.
// - 2025-05-30: Updated ISSLiquidityTemplate to include liquidityDetailsView for xLiquid and yLiquid.
// - 2025-05-30: Version incremented to 0.0.4 for pre-testing.
// - 2025-05-29: Added ISSAgent interface for listing validation.
// - 2025-05-29: Added agentAddress storage variable.
// - 2025-05-29: Updated parseEntryPrice to return priceAtEntry.
// - 2025-05-29: Version incremented to 0.0.2 for pre-testing.

pragma solidity 0.8.1;

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
    struct UpdateType {
        uint8 updateTipo;
        uint256 index;
        uint256 value;
        address addr;
        address recipient;
    }
    function addFees(address caller, bool isX, uint256 fee) external;
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
}

interface ISSAgent {
    function getListing(address tokenA, address tokenB) external view returns (address);
}

contract CSDUtilityPartial {
    using SafeERC20 for IERC20;

    uint256 public constant DECIMAL_PRECISION = 1e18;
    address public agentAddress;
    uint256 public positionCount;

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

    mapping(uint256 => PositionCore1) public positionCore1;
    mapping(uint256 => PositionCore2) public positionCore2;
    mapping(uint256 => PriceParams1) public priceParams1;
    mapping(uint256 => PriceParams2) public priceParams2;
    mapping(uint256 => MarginParams1) public marginParams1;
    mapping(uint256 => MarginParams2) public margin2;
    mapping(uint256 => ExitParams) public exitParams;
    mapping(uint256 => OpenInterest) public openInterest;

    mapping(address => mapping(address => uint256)) public makerTokenMargin;
    mapping(address => address[]) public makerMarginTokens;

    function parseEntryPrice(
        uint256 minEntryPrice,
        uint256 maxEntryPrice,
        address listingAddress
    ) internal view returns (uint256 currentPrice, uint256 minPrice, uint256 maxPrice, uint256 priceAtEntry) {
        currentPrice = ISSListing(listingAddress).prices(listingAddress);
        priceAtEntry = currentPrice;
        if (minEntryPrice == 0 && maxEntryPrice == 0) {
            return (currentPrice, currentPrice, currentPrice, priceAtEntry);
        }
        require(minEntryPrice <= maxEntryPrice, "Invalid price range");
        return (currentPrice, minEntryPrice, maxEntryPrice, priceAtEntry);
    }

    function transferMargin(address to, address token, uint256 amount) internal {
        if (amount > 0) {
            IERC20(token).safeTransfer(to, amount);
        }
    }

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
}