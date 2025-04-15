// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Significant changes:
// - Fully independent, no SSIsolatedDriver import.
// - Includes ISSListing interface locally for parseEntryPrice.
// - Handles normalizeAmount, parseEntryPrice, parseUint, splitString.
// - Size: ~100 lines, reflecting added interface.
// - Functionality preserved without listingAddress code by assuming ISSListing behavior.

import "imports/IERC20Metadata.sol";

library SSUtilityLibrary {
    // Interface
    interface ISSListing {
        function prices(address listingAddress) external view returns (uint256);
    }

    // Constants
    uint256 private constant DECIMAL_PRECISION = 1e18;

    // Normalize amount based on token decimals
    function normalizeAmount(address token, uint256 amount) external view returns (uint256) {
        if (token == address(0)) return amount; // Native ETH, assume 18 decimals
        uint8 decimals = IERC20Metadata(token).decimals();
        if (decimals == 18) return amount;
        return amount * DECIMAL_PRECISION / (10 ** decimals);
    }

    // Parse entry price string
    function parseEntryPrice(string memory entryPrice, address listingAddress) external view returns (uint256 minPrice, uint256 maxPrice) {
        bytes memory priceBytes = bytes(entryPrice);
        require(priceBytes.length > 0, "Empty price");
        for (uint256 i = 0; i < priceBytes.length; i++) {
            if (priceBytes[i] != ',' && (priceBytes[i] < '0' || priceBytes[i] > '9')) {
                revert("Invalid characters");
            }
        }

        // Check for comma
        bool isRange;
        for (uint256 i = 0; i < priceBytes.length; i++) {
            if (priceBytes[i] == ',') {
                isRange = true;
                break;
            }
        }

        if (!isRange) {
            // Single or market price
            uint256 price;
            if (keccak256(abi.encodePacked(entryPrice)) == keccak256(abi.encodePacked("0"))) {
                price = ISSListing(listingAddress).prices(listingAddress);
            } else {
                price = parseUint(entryPrice);
            }
            require(price > 0, "Invalid price");
            return (price, price);
        }

        // Range price
        (string memory minStr, string memory maxStr) = splitString(entryPrice, ",");
        minPrice = parseUint(minStr);
        maxPrice = parseUint(maxStr);
        require(minPrice > 0 && maxPrice > 0, "Invalid range");
        require(minPrice <= maxPrice, "Invalid range order");
        return (minPrice, maxPrice);
    }

    // Parse uint from string
    function parseUint(string memory str) public pure returns (uint256) {
        bytes memory b = bytes(str);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] >= '0' && b[i] <= '9', "Invalid digit");
            result = result * 10 + (uint8(b[i]) - 48);
        }
        return result * DECIMAL_PRECISION;
    }

    // Split string at delimiter
    function splitString(string memory str, string memory delimiter) public pure returns (string memory, string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory delimBytes = bytes(delimiter);
        require(delimBytes.length == 1, "Invalid delimiter");

        uint256 delimIndex;
        bool found;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == delimBytes[0]) {
                delimIndex = i;
                found = true;
                break;
            }
        }
        require(found, "Delimiter not found");

        bytes memory part1 = new bytes(delimIndex);
        bytes memory part2 = new bytes(strBytes.length - delimIndex - 1);
        for (uint256 i = 0; i < delimIndex; i++) {
            part1[i] = strBytes[i];
        }
        for (uint256 i = delimIndex + 1; i < strBytes.length; i++) {
            part2[i - delimIndex - 1] = strBytes[i];
        }
        return (string(part1), string(part2));
    }
}