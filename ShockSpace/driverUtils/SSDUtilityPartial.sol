/* SPDX-License-Identifier: BSD-3-Clause */
pragma solidity ^0.8.1;

// Version 0.0.5:
// - Fixed shadowing warning by consolidating 'decimals' declaration in parseEntryPrice.
// - Compatible with SSDPositionPartial.sol v0.0.3, SSDExecutionPartial.sol v0.0.2, SSIsolatedDriver.sol v0.0.2.

import "../imports/SafeERC20.sol";
import "../imports/IERC20Metadata.sol";

// Structs
struct PayoutUpdate {
    address recipient;
    uint256 required;
    uint8 payoutType; // 0: Long, 1: Short
}

struct UpdateType {
    uint8 updateType;
    uint256 index;
    uint256 value;
    address addr;
    address recipient;
}

// Interfaces
interface ISSListing {
    function prices(uint256) external view returns (uint256);
    function volumeBalances(uint256) external view returns (uint256 xBalance, uint256 yBalance);
    function liquidityAddressView() external view returns (address);
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function ssUpdate(address caller, PayoutUpdate[] calldata updates) external;
    function update(address caller, UpdateType[] memory updates) external;
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

interface ISSAgent {
    function getListing(address tokenA, address tokenB) external view returns (address);
}

interface ISSLiquidityTemplate {
    function liquidityDetailsView() external view returns (uint256 xLiquid, uint256 yLiquid, uint256 xFees, uint256 yFees);
    function addFees(address caller, bool isX, uint256 fee) external;
}

contract SSDUtilityPartial {
    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;

    // State variables
    address public agent;
    mapping(uint256 => PositionCoreBase) public positionCoreBase;
    mapping(uint256 => PositionCoreStatus) public positionCoreStatus;
    mapping(uint256 => PriceParams) public priceParams;
    mapping(uint256 => MarginParams) public marginParams;
    mapping(uint256 => LeverageParams) public leverageParams;
    mapping(uint256 => RiskParams) public riskParams;
    mapping(address => mapping(uint8 => uint256[])) public pendingPositions;
    mapping(uint8 => uint256[]) public positionsByType;
    mapping(uint256 => uint256) public longIOByHeight;
    mapping(uint256 => uint256) public shortIOByHeight;
    mapping(uint256 => uint256) public historicalInterestTimestamps;
    mapping(uint256 => address) public positionToken;
    uint256 public historicalInterestHeight;
    uint256 public nonce;
    uint256 public positionIdCounter;

    // Structs
    struct PositionCoreBase {
        address makerAddress;
        address listingAddress;
        uint256 positionId;
        uint8 positionType; // 0: Long, 1: Short
    }

    struct PositionCoreStatus {
        bool status1; // false: pending, true: executable
        uint8 status2; // 0: open, 1: closed, 2: cancelled
    }

    struct PriceParams {
        uint256 priceMin;
        uint256 priceMax;
        uint256 priceAtEntry;
        uint256 priceClose;
    }

    struct MarginParams {
        uint256 marginInitial;
        uint256 marginTaxed;
        uint256 marginExcess;
    }

    struct LeverageParams {
        uint8 leverageVal;
        uint256 leverageAmount;
        uint256 loanInitial;
    }

    struct RiskParams {
        uint256 priceLiquidation;
        uint256 priceStopLoss;
        uint256 priceTakeProfit;
    }

    struct PosParamsCore {
        PriceParams priceParams;
        MarginParams marginParams;
    }

    struct PosParamsExt {
        LeverageParams leverageParams;
        RiskParams riskParams;
    }

    struct PositionAction {
        uint256 positionId;
        uint8 actionType; // 0: Update status, 1: Close
    }

    struct EntryParamsBase {
        address listingAddr;
        string entryPriceStr;
        uint256 initMargin;
        uint256 extraMargin;
    }

    struct EntryParamsRisk {
        uint8 leverageVal;
        uint256 stopLoss;
        uint256 takeProfit;
    }

    struct EntryParamsToken {
        address tokenAddr;
        uint256 normInitMargin;
        uint256 normExtraMargin;
        address driverAddr;
    }

    struct ClosePositionBase {
        uint256 positionId;
        address listingAddress;
        address makerAddress;
        address driver;
    }

    struct ClosePositionMargin {
        uint256 taxedMargin;
        uint256 excessMargin;
    }

    struct LongCloseParams {
        uint256 leverageAmount;
        uint256 loanInitial;
    }

    struct ShortCloseParams {
        uint256 minPrice;
        uint256 initialMargin;
        uint8 leverage;
    }

    struct ExecutionContextBase {
        address listingAddress;
        address driver;
        uint256 currentPrice;
    }

    struct ExecutionContextCounts {
        uint256 actionCount;
        uint256 maxActions;
    }

    // Constructor
    constructor() {
        historicalInterestHeight = 1;
        nonce = 0;
        positionIdCounter = 1;
    }

    // Normalize amount based on token decimals
    function normalizeAmount(address token, uint256 amount) public view returns (uint256) {
        if (token == address(0)) {
            return amount * DECIMAL_PRECISION / 1e18;
        }
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Denormalize amount based on token decimals
    function denormalizeAmount(address token, uint256 normalizedAmount) public view returns (uint256) {
        if (token == address(0)) {
            return normalizedAmount / DECIMAL_PRECISION;
        }
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return normalizedAmount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    // Parse entry price string (e.g., "100-200", "0", "0-0")
    function parseEntryPrice(string memory entryPrice, address listingAddress) 
        public view returns (uint256 minPrice, uint256 maxPrice) 
    {
        require(bytes(entryPrice).length > 0, "Empty price string");
        uint8 decimals = ISSListing(listingAddress).decimalsB(); // Single declaration
        if (keccak256(abi.encodePacked(entryPrice)) == keccak256(abi.encodePacked("0")) || 
            keccak256(abi.encodePacked(entryPrice)) == keccak256(abi.encodePacked("0-0"))) {
            minPrice = ISSListing(listingAddress).prices(uint256(uint160(listingAddress)));
            maxPrice = minPrice;
            minPrice = normalizePrice(minPrice, decimals);
            maxPrice = normalizePrice(maxPrice, decimals);
            return (minPrice, maxPrice);
        }
        
        (string memory minStr, string memory maxStr) = splitString(entryPrice, "-");
        
        minPrice = parseUint(minStr);
        maxPrice = bytes(maxStr).length > 0 ? parseUint(maxStr) : minPrice;
        
        require(minPrice > 0, "Invalid min price");
        require(maxPrice >= minPrice, "Invalid price range");

        minPrice = normalizePrice(minPrice, decimals);
        maxPrice = normalizePrice(maxPrice, decimals);
    }

    // Normalize price to DECIMAL_PRECISION
    function normalizePrice(uint256 price, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) {
            return price;
        }
        if (decimals < 18) {
            return price * (10 ** (18 - uint256(decimals)));
        }
        return price / (10 ** (uint256(decimals) - 18));
    }

    // Parse string to uint
    function parseUint(string memory str) public pure returns (uint256) {
        bytes memory b = bytes(str);
        require(b.length > 0, "Empty string");
        uint256 result = 0;
        bool hasDecimal = false;
        uint256 decimalPlace = 0;

        for (uint256 i = 0; i < b.length; i++) {
            if (b[i] == 0x2E) {
                require(!hasDecimal, "Multiple decimals");
                hasDecimal = true;
                continue;
            }
            require(b[i] >= 0x30 && b[i] <= 0x39, "Invalid character");
            if (hasDecimal) {
                decimalPlace++;
                if (decimalPlace > 18) {
                    continue;
                }
            }
            result = result * 10 + (uint8(b[i]) - 0x30);
        }

        if (hasDecimal) {
            result = result * (10 ** (18 - decimalPlace));
        } else {
            result = result * DECIMAL_PRECISION;
        }
        return result;
    }

    // Split string on delimiter
    function splitString(string memory str, string memory delimiter) 
        public pure returns (string memory, string memory) 
    {
        require(bytes(str).length > 0, "Empty string");
        require(keccak256(abi.encodePacked(delimiter)) == keccak256(abi.encodePacked("-")), "Invalid delimiter");
        
        bytes memory strBytes = bytes(str);
        bytes memory delimBytes = bytes(delimiter);
        uint256 splitIndex = strBytes.length;

        for (uint256 i = 0; i < strBytes.length - delimBytes.length + 1; i++) {
            bool isMatch = true;
            for (uint256 j = 0; j < delimBytes.length; j++) {
                if (strBytes[i + j] != delimBytes[j]) {
                    isMatch = false;
                    break;
                }
            }
            if (isMatch) {
                splitIndex = i;
                break;
            }
        }

        if (splitIndex == strBytes.length) {
            return (str, "");
        }

        bytes memory first = new bytes(splitIndex);
        bytes memory second = new bytes(strBytes.length - splitIndex - delimBytes.length);
        for (uint256 i = 0; i < splitIndex; i++) {
            first[i] = strBytes[i];
        }
        for (uint256 i = 0; i < strBytes.length - splitIndex - delimBytes.length; i++) {
            second[i] = strBytes[splitIndex + delimBytes.length + i];
        }

        return (string(first), string(second));
    }

    // Convert price to listing decimals
    function convertPriceToDecimals(uint256 price, address listingAddress, uint8 targetDecimals) 
        public view returns (uint256) 
    {
        uint8 listingDecimals = ISSListing(listingAddress).decimalsB();
        if (listingDecimals == targetDecimals) {
            return price;
        }
        if (listingDecimals < targetDecimals) {
            return price * (10 ** (uint256(targetDecimals) - uint256(listingDecimals)));
        }
        return price / (10 ** (uint256(listingDecimals) - uint256(targetDecimals)));
    }
}