// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.1:
// - Initial implementation for SSD-PositionLibrary and SSD-ExecutionLibrary.
// - Includes normalizeAmount for token decimal adjustments.
// - Provides parseEntryPrice for price range parsing with "-" delimiter.
// - Includes parseUint for string-to-uint conversion.
// - Adds splitString for string splitting on "-" delimiter.
// - Incorporates input validation for robust error handling.
// - Uses local imports for IERC20 and Strings.
// - Assumes IERC20 includes decimals() function.
// - Compatible with SSD-PositionLibrary.sol v0.0.23 and SSD-ExecutionLibrary.sol v0.0.5.

import "./imports/IERC20.sol";
import "./imports/Strings.sol";

interface ISSListing {
    function prices(uint256 listingId) external view returns (uint256);
    function decimalsA() external view returns (uint8);
    function decimalsB() external view returns (uint8);
}

library SSDUtilityLibrary {
    using Strings for string;

    // Constants
    uint256 public constant DECIMAL_PRECISION = 1e18;

    // Normalize amount based on token decimals
    function normalizeAmount(address token, uint256 amount) external view returns (uint256) {
        if (token == address(0)) {
            return amount * DECIMAL_PRECISION / 1e18;
        }
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Denormalize amount based on token decimals
    function denormalizeAmount(address token, uint256 normalizedAmount) external view returns (uint256) {
        if (token == address(0)) {
            return normalizedAmount / DECIMAL_PRECISION;
        }
        uint8 decimals = IERC20(token).decimals();
        require(decimals <= 18, "Unsupported decimals");
        return normalizedAmount * (10 ** decimals) / DECIMAL_PRECISION;
    }

    // Parse entry price string (e.g., "100-200" or "150")
    function parseEntryPrice(string memory entryPrice, address listingAddress) 
        external view returns (uint256 minPrice, uint256 maxPrice) 
    {
        require(bytes(entryPrice).length > 0, "Empty price string");
        (string memory minStr, string memory maxStr) = splitString(entryPrice, "-");
        
        minPrice = parseUint(minStr);
        maxPrice = bytes(maxStr).length > 0 ? parseUint(maxStr) : minPrice;
        
        require(minPrice > 0, "Invalid min price");
        require(maxPrice >= minPrice, "Invalid price range");

        // Adjust for listing decimals
        uint8 decimals = ISSListing(listingAddress).decimalsB();
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
            if (b[i] == 0x2E) { // Decimal point
                require(!hasDecimal, "Multiple decimals");
                hasDecimal = true;
                continue;
            }
            require(b[i] >= 0x30 && b[i] <= 0x39, "Invalid character");
            if (hasDecimal) {
                decimalPlace++;
                if (decimalPlace > 18) {
                    continue; // Ignore excessive decimal places
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
        external view returns (uint256) 
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