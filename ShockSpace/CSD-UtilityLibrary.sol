// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.2:
// - Enhanced parseEntryPrice to parse price ranges with "-" delimiter.
// - Updated splitString to split on "-" and validate numeric parts.
// - Added input validation to reject non-standard inputs.
// - Clarified pure/view functions, no storage used.
// - Used local imports (./imports/...).
// - Assumed IERC20 includes decimals().

import "./imports/IERC20.sol";
import "./imports/Strings.sol";

contract CSDUtilityLibrary {
    using Strings for string;

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Interface
    interface ISSListing {
        function prices(address listingAddress) external view returns (uint256);
    }

    // Normalize amount based on token decimals
    function normalizeAmount(address token, uint256 amount) external view returns (uint256) {
        if (token == address(0)) {
            return amount * DECIMAL_PRECISION / 1e18;
        }
        uint8 decimals = IERC20(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Parse entry price
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice) {
        require(bytes(entryPrice).length > 0, "Empty price string");
        (string memory minStr, string memory maxStr) = splitString(entryPrice, "-");
        minPrice = parseUint(minStr);
        maxPrice = bytes(maxStr).length > 0 ? parseUint(maxStr) : minPrice;
        require(minPrice > 0 && minPrice <= maxPrice, "Invalid price range");
    }

    // Parse string to uint
    function parseUint(string memory str) public pure returns (uint256) {
        bytes memory b = bytes(str);
        require(b.length > 0, "Empty string");
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] >= 0x30 && b[i] <= 0x39, "Invalid character");
            result = result * 10 + (uint8(b[i]) - 0x30);
        }
        return result * DECIMAL_PRECISION;
    }

    // Split string on delimiter
    function splitString(string memory str, string memory delimiter) public pure returns (string memory, string memory) {
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
}