// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.2;

// Version 0.0.1: Initial interface for ShockEntry and ShockExit contracts
// - Defines external functions and structs for ShockEntry and ShockExit
// - Includes view functions for state access
// - Aligns with ShockEntry and ShockExit functionality from version 0.0.58
// - Ensures no naming conflicts between function names and state variables
// - Uses explicit parameter descriptions for hyphen-delimited inputs

// Interface for ShockEntry and ShockExit contracts
interface IShockhopper {
    // Struct for ShockExit hop details
    struct ExitHop {
        address maker; // Address initiating the hop
        uint256 multihopId; // ID of the associated Multihopper hop
        uint256 positionId; // ID of the position to close
        address listingAddress; // Address of the listing for position closure
        uint8 positionType; // 0 for long, 1 for short
        uint256 payoutOrderId; // Order ID for payout from drift
        address startToken; // Token received from position closure
        address endToken; // Expected end token from multihop
        uint8 settleType; // 0 for market settlement, 1 for liquid settlement
        uint8 status; // 0 = initializing, 1 = pending, 2 = completed, 3 = cancelled
        bool isCrossDriver; // True for CrossDriver, false for IsolatedDriver
    }

    // Struct for ShockEntry hop details
    struct EntryHop {
        address maker; // Address initiating the hop
        uint256 hopId; // ID of the Multihopper hop
        address listingAddress; // Address of the listing for position creation
        uint8 positionType; // 0 for long, 1 for short
        uint256 initialMargin; // Normalized initial margin for position
        uint256 excessMargin; // Normalized excess margin for position
        uint8 leverage; // Leverage multiplier for position
        uint256 stopLossPrice; // Normalized stop-loss price
        uint256 takeProfitPrice; // Normalized take-profit price
        address endToken; // Expected end token from multihop
        uint8 status; // 1 = pending, 2 = completed, 3 = cancelled
        bool isCrossDriver; // True for CrossDriver, false for IsolatedDriver
        uint256 minEntryPrice; // Normalized minimum entry price
        uint256 maxEntryPrice; // Normalized maximum entry price
    }

    // Initiates a position closure followed by a CrossDriver multihop swap
    // @param listings Hyphen-delimited string of up to 4 listing addresses (e.g., "0x1-0x2-0x3-0x4"), specifies swap path
    // @param impactPercent Price impact percent scaled to 1000, controls acceptable slippage
    // @param tokens Hyphen-delimited string of start and end token addresses (e.g., "0xStart-0xEnd"), defines token swap pair
    // @param settleType 0 for market settlement, 1 for liquid settlement, determines execution method
    // @param maxIterations Maximum number of iterations for settlement, controls processing limit
    // @param positionParams Hyphen-delimited string (e.g., "0xListing-123-0"), includes listing address, position ID, and position type (0=long, 1=short)
    // @param maker Address initiating the hop, defaults to msg.sender if address(0)
    function crossExitHop(
        string memory listings,
        uint256 impactPercent,
        string memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        string memory positionParams,
        address maker
    ) external;

    // Initiates a position closure followed by an IsolatedDriver multihop swap
    // @param listings Hyphen-delimited string of up to 4 listing addresses (e.g., "0x1-0x2-0x3-0x4"), specifies swap path
    // @param impactPercent Price impact percent scaled to 1000, controls acceptable slippage
    // @param tokens Hyphen-delimited string of start and end token addresses (e.g., "0xStart-0xEnd"), defines token swap pair
    // @param settleType 0 for market settlement, 1 for liquid settlement, determines execution method
    // @param maxIterations Maximum number of iterations for settlement, controls processing limit
    // @param positionParams Hyphen-delimited string (e.g., "0xListing-123-0"), includes listing address, position ID, and position type (0=long, 1=short)
    // @param maker Address initiating the hop, defaults to msg.sender if address(0)
    function isolatedExitHop(
        string memory listings,
        uint256 impactPercent,
        string memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        string memory positionParams,
        address maker
    ) external;

    // Initiates a multi-hop swap followed by a CrossDriver position creation
    // @param listings Hyphen-delimited string of up to 4 listing addresses (e.g., "0x1-0x2-0x3-0x4"), specifies swap path
    // @param impactPercent Price impact percent scaled to 1000, controls acceptable slippage
    // @param tokens Hyphen-delimited string of start and end token addresses (e.g., "0xStart-0xEnd"), defines token swap pair
    // @param settleType 0 for market settlement, 1 for liquid settlement, determines execution method
    // @param maxIterations Maximum number of iterations for settlement and position execution, controls processing limit
    // @param positionParams Hyphen-delimited string (e.g., "0xListing-1000-2000-1000-200-2-500-6000-0"), includes listing address, min/max entry prices, initial/excess margins, leverage, stop-loss, take-profit, and position type (0=long, 1=short)
    // @param maker Address initiating the hop, defaults to msg.sender if address(0)
    function crossEntryHop(
        string memory listings,
        uint256 impactPercent,
        string memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        string memory positionParams,
        address maker
    ) external;

    // Initiates a multi-hop swap followed by an IsolatedDriver position creation
    // @param listings Hyphen-delimited string of up to 4 listing addresses (e.g., "0x1-0x2-0x3-0x4"), specifies swap path
    // @param impactPercent Price impact percent scaled to 1000, controls acceptable slippage
    // @param tokens Hyphen-delimited string of start and end token addresses (e.g., "0xStart-0xEnd"), defines token swap pair
    // @param settleType 0 for market settlement, 1 for liquid settlement, determines execution method
    // @param maxIterations Maximum number of iterations for settlement and position execution, controls processing limit
    // @param positionParams Hyphen-delimited string (e.g., "0xListing-1000-2000-1000-200-2-500-6000-0"), includes listing address, min/max entry prices, initial/excess margins, leverage, stop-loss, take-profit, and position type (0=long, 1=short)
    // @param maker Address initiating the hop, defaults to msg.sender if address(0)
    function isolatedEntryHop(
        string memory listings,
        uint256 impactPercent,
        string memory tokens,
        uint8 settleType,
        uint256 maxIterations,
        string memory positionParams,
        address maker
    ) external;

    // Continues pending CrossDriver exit hops for the caller
    // @param maxIterations Maximum number of hops to process, limits processing scope
    function continueCrossExitHops(uint256 maxIterations) external;

    // Continues pending IsolatedDriver exit hops for the caller
    // @param maxIterations Maximum number of hops to process, limits processing scope
    function continueIsolatedExitHops(uint256 maxIterations) external;

    // Continues pending CrossDriver entry hops for the caller
    // @param maxIterations Maximum number of hops to process, limits processing scope
    function continueCrossEntryHops(uint256 maxIterations) external;

    // Continues pending IsolatedDriver entry hops for the caller
    // @param maxIterations Maximum number of hops to process, limits processing scope
    function continueIsolatedEntryHops(uint256 maxIterations) external;

    // Processes pending CrossDriver exit hops globally for all users
    // @param maxIterations Maximum number of hops to process, limits processing scope
    function executeCrossExitHops(uint256 maxIterations) external;

    // Processes pending IsolatedDriver exit hops globally for all users
    // @param maxIterations Maximum number of hops to process, limits processing scope
    function executeIsolatedExitHops(uint256 maxIterations) external;

    // Cancels a CrossDriver entry hop and refunds amounts
    // @param entryHopId ID of the entry hop to cancel
    function cancelCrossEntryHop(uint256 entryHopId) external;

    // Cancels an IsolatedDriver entry hop and refunds amounts
    // @param entryHopId ID of the entry hop to cancel
    function cancelIsolatedEntryHop(uint256 entryHopId) external;

    // Retrieves details of an exit hop
    // @param exitHopId ID of the exit hop
    // @return ExitHop struct containing hop details
    function getExitHopDetails(uint256 exitHopId) external view returns (ExitHop memory);

    // Retrieves details of an entry hop
    // @param entryHopId ID of the entry hop
    // @return EntryHop struct containing hop details
    function getEntryHopDetails(uint256 entryHopId) external view returns (EntryHop memory);

    // Retrieves exit hop IDs for a user
    // @param user User address
    // @return Array of exit hop IDs
    function getUserExitHops(address user) external view returns (uint256[] memory);

    // Retrieves entry hop IDs for a user
    // @param user User address
    // @return Array of entry hop IDs
    function getUserEntryHops(address user) external view returns (uint256[] memory);

    // Retrieves the Multihopper contract address
    // @return Address of the Multihopper contract
    function multihopperView() external view returns (address);

    // Retrieves the SSCrossDriver contract address
    // @return Address of the SSCrossDriver contract
    function crossDriverView() external view returns (address);

    // Retrieves the ISSIsolatedDriver contract address
    // @return Address of the ISSIsolatedDriver contract
    function isolatedDriverView() external view returns (address);

    // Sets the Multihopper contract address
    // @param _multihopper New Multihopper contract address
    function setMultihopper(address _multihopper) external;

    // Sets the SSCrossDriver contract address
    // @param _crossDriver New SSCrossDriver contract address
    function setCrossDriver(address _crossDriver) external;

    // Sets the ISSIsolatedDriver contract address
    // @param _isolatedDriver New ISSIsolatedDriver contract address
    function setIsolatedDriver(address _isolatedDriver) external;
}