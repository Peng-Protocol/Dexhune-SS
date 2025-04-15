// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version 0.0.1:
// - Cloned from SSUtilityLibrary, supports SSCrossDriver.
// - Provides normalization and price parsing utilities.
// - Size: ~100 lines, lightweight and gas-efficient.
// - No storage, pure/view functions only.

import "imports/Strings.sol";
import "imports/IERC20Metadata.sol";

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
        uint8 decimals = IERC20Metadata(token).decimals();
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Parse entry price
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice) {
        // Simplified parsing: assume single price for minPrice
        minPrice = parseUint(entryPrice);
        maxPrice = minPrice; // Mock: no range
    }

    // Parse string to uint
    function parseUint(string memory str) public pure returns (uint256) {
        // Simplified: assume valid numeric string
        bytes memory b = bytes(str);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] >= 0x30 && b[i] <= 0x39, "Invalid character");
            result = result * 10 + (uint8(b[i]) - 0x30);
        }
        return result * DECIMAL_PRECISION;
    }

    // Split string (mocked)
    function splitString(string memory str, string memory delimiter) external pure returns (string memory, string memory) {
        // Mock: return single price
        return (str, str);
    }
}