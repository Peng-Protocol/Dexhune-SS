// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.5
// - Updated from v0.0.4: Added payout ID querying from SS-ListingTemplate
// - Ensured settlement calls via SS-ProxyRouter respect liquidity vs market-based distinction
// - Uses separately deployed HopLibrary, CrossLibrary, IsolatedLibrary
// - Calls settlement/order functions through SS-ProxyRouter
// - Compatible with SSCrossDriver.sol v0.0.10, SSIsolatedDriver.sol v0.0.14
// - Integrates with SS-ProxyRouter.sol v0.0.4

import "./imports/Ownable.sol";
import "./imports/ReentrancyGuard.sol";
import "./imports/SafeERC20.sol";

interface IHopLibrary {
    struct StalledHop {
        uint8 stage;
        address currentListing;
        uint256 positionId;
        uint256 minPrice;
        uint256 maxPrice;
        address hopMaker;
        address[] remainingListings;
        uint256 principalAmount;
        address startToken;
        address endToken;
        uint8 settleType;
        uint8 hopStatus;
        uint8 driverType;
        bool entry;
        uint8 positionType;
        uint256 payoutId;
    }

    function prepHop(
        HopLibrary.HopRequest memory request,
        uint256 hopId,
        address shockhopper
    ) external view returns (HopLibrary.HopPrepData memory);

    function executeHop(
        HopLibrary.HopRequest memory request,
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        address proxyRouter
    ) external;

    function prepStalls(
        address user,
        uint256[] memory userHops,
        mapping(uint256 => IHopLibrary.StalledHop) storage hopID,
        address shockhopper
    ) external returns (HopLibrary.StallData[] memory);

    function executeStalls(
        HopLibrary.StallData[] memory stalls,
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        address proxyRouter
    ) external;

    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        IHopLibrary.StalledHop memory hop,
        address proxyRouter
    ) external;

    function cancelAll(
        address user,
        address shockhopper,
        address crossDriver,
        address isolatedDriver,
        address crossLibrary,
        address isolatedLibrary,
        uint256[] memory userHops,
        mapping(uint256 => IHopLibrary.StalledHop) storage hopID,
        address proxyRouter
    ) external returns (uint256);
}

interface ICrossLibrary {
    function entryExitHop(
        HopLibrary.HopRequest memory request,
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external;

    function continueHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external;

    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address crossDriver,
        address proxyRouter
    ) external;
}

interface IIsolatedLibrary {
    function entryExitHop(
        HopLibrary.HopRequest memory request,
        uint256 hopId,
        address user,
        address shockhopper,
        address isolatedDriver,
        address proxyRouter
    ) external;

    function continueHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address isolatedDriver,
        address proxyRouter
    ) external;

    function cancelHop(
        uint256 hopId,
        address user,
        address shockhopper,
        address isolatedDriver,
        address proxyRouter
    ) external;
}

interface ISSCrossDriver {
    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable returns (uint256);

    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable returns (uint256);

    function closeLongPosition(uint256 positionId) external;
    function closeShortPosition(uint256 positionId) external;
    function cancelPosition(uint256 positionId) external;
    function userPositions(address user, uint256 index) external view returns (uint256);
}

interface ISSIsolatedDriver {
    function enterLong(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable returns (uint256);

    function enterShort(
        address listingAddress,
        string memory entryPrice,
        uint256 initialMargin,
        uint256 excessMargin,
        uint8 leverage,
        uint256 stopLossPrice,
        uint256 takeProfitPrice
    ) external payable returns (uint256);

    function closeLongPosition(uint256 positionId) external;
    function closeShortPosition(uint256 positionId) external;
    function cancelPosition(uint256 positionId) external;
    function userPositions(address user, uint256 index) external view returns (uint256);
}

interface ISSListing {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function prices(uint256 listingId) external view returns (uint256);
}

contract SSShockhopper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public crossDriverAddress;
    address public isolatedDriverAddress;
    address public hopLibraryAddress;
    address public crossLibraryAddress;
    address public isolatedLibraryAddress;
    address public proxyRouter;

    mapping(uint256 => IHopLibrary.StalledHop) public hopID;
    mapping(address => uint256[]) public hopsByAddress;
    uint256[] public totalHops;
    uint256 private nextHopId;

    // Events
    event HopCreated(uint256 indexed hopId, address indexed maker, uint256 numListings);
    event HopContinued(uint256 indexed hopId, uint8 newStage);
    event HopCanceled(uint256 indexed hopId);
    event AllHopsCanceled(address indexed maker, uint256 count);
    event StallsPrepared(uint256 indexed hopId, uint256 count);
    event StallsExecuted(uint256 indexed hopId, uint256 count);
    event LibrarySet(address indexed libraryAddress, string libraryType);
    event DriverSet(address indexed driverAddress, string driverType);
    event ProxyRouterSet(address indexed proxyRouter);

    // Modifiers
    modifier onlySelf() {
        require(msg.sender == address(this), "Only self");
        _;
    }

    // Set driver addresses
    function setCrossDriver(address _crossDriverAddress) external onlyOwner {
        require(_crossDriverAddress != address(0), "Invalid driver address");
        crossDriverAddress = _crossDriverAddress;
        emit DriverSet(_crossDriverAddress, "CrossDriver");
    }

    function setIsolatedDriver(address _isolatedDriverAddress) external onlyOwner {
        require(_isolatedDriverAddress != address(0), "Invalid driver address");
        isolatedDriverAddress = _isolatedDriverAddress;
        emit DriverSet(_isolatedDriverAddress, "IsolatedDriver");
    }

    // Set library addresses
    function setHopLibrary(address _hopLibraryAddress) external onlyOwner {
        require(_hopLibraryAddress != address(0), "Invalid library address");
        hopLibraryAddress = _hopLibraryAddress;
        emit LibrarySet(_hopLibraryAddress, "HopLibrary");
    }

    function setCrossLibrary(address _crossLibraryAddress) external onlyOwner {
        require(_crossLibraryAddress != address(0), "Invalid library address");
        crossLibraryAddress = _crossLibraryAddress;
        emit LibrarySet(_crossLibraryAddress, "CrossLibrary");
    }

    function setIsolatedLibrary(address _isolatedLibraryAddress) external onlyOwner {
        require(_isolatedLibraryAddress != address(0), "Invalid library address");
        isolatedLibraryAddress = _isolatedLibraryAddress;
        emit LibrarySet(_isolatedLibraryAddress, "IsolatedLibrary");
    }

    // Set proxy router
    function setProxyRouter(address _proxyRouter) external onlyOwner {
        require(_proxyRouter != address(0), "Invalid proxy router address");
        proxyRouter = _proxyRouter;
        emit ProxyRouterSet(_proxyRouter);
    }

    // Update stalled hop
    function updateStalledHop(uint256 hopId, IHopLibrary.StalledHop memory hop) external onlySelf {
        hopID[hopId] = hop;
    }

    // Update hops by address
    function updateHopsByAddress(address maker, uint256 hopId) external onlySelf {
        hopsByAddress[maker].push(hopId);
    }

    // Update total hops
    function updateTotalHops(uint256 hopId) external onlySelf {
        totalHops.push(hopId);
    }

    // Remove hop from hopsByAddress
    function removeHopByAddress(address maker, uint256 hopId) external onlySelf {
        uint256[] storage userHops = hopsByAddress[maker];
        for (uint256 i = 0; i < userHops.length; i++) {
            if (userHops[i] == hopId) {
                userHops[i] = userHops[userHops.length - 1];
                userHops.pop();
                break;
            }
        }
    }

    // Standard hop
    function hop(HopLibrary.HopRequest memory request) external payable nonReentrant {
        require(hopLibraryAddress != address(0), "HopLibrary not set");
        require(proxyRouter != address(0), "ProxyRouter not set");
        require(crossDriverAddress != address(0) || isolatedDriverAddress != address(0), "No driver set");

        uint256 hopId = nextHopId++;
        IHopLibrary(hopLibraryAddress).executeHop(
            request,
            msg.sender,
            address(this),
            crossDriverAddress,
            isolatedDriverAddress,
            crossLibraryAddress,
            isolatedLibraryAddress,
            proxyRouter
        );

        emit HopCreated(hopId, msg.sender, request.numListings);
    }

    // Entry/exit hop
    function entryExitHop(HopLibrary.HopRequest memory request) external payable nonReentrant {
        require(hopLibraryAddress != address(0), "HopLibrary not set");
        require(proxyRouter != address(0), "ProxyRouter not set");
        require(crossLibraryAddress != address(0) || isolatedLibraryAddress != address(0), "No library set");
        require(request.driverType <= 1, "Invalid driver type");

        uint256 hopId = nextHopId++;
        if (request.driverType == 0) {
            require(crossDriverAddress != address(0) && crossLibraryAddress != address(0), "CrossDriver not set");
            ICrossLibrary(crossLibraryAddress).entryExitHop(
                request,
                hopId,
                msg.sender,
                address(this),
                crossDriverAddress,
                proxyRouter
            );
        } else {
            require(isolatedDriverAddress != address(0) && isolatedLibraryAddress != address(0), "IsolatedDriver not set");
            IIsolatedLibrary(isolatedLibraryAddress).entryExitHop(
                request,
                hopId,
                msg.sender,
                address(this),
                isolatedDriverAddress,
                proxyRouter
            );
        }

        emit HopCreated(hopId, msg.sender, request.numListings);
    }

    // Continue hop
    function continueHop() external nonReentrant {
        require(hopLibraryAddress != address(0), "HopLibrary not set");
        require(proxyRouter != address(0), "ProxyRouter not set");
        HopLibrary.StallData[] memory stalls = IHopLibrary(hopLibraryAddress).prepStalls(
            msg.sender,
            hopsByAddress[msg.sender],
            hopID,
            address(this)
        );
        if (stalls.length > 0) {
            IHopLibrary(hopLibraryAddress).executeStalls(
                stalls,
                msg.sender,
                address(this),
                crossDriverAddress,
                isolatedDriverAddress,
                crossLibraryAddress,
                isolatedLibraryAddress,
                proxyRouter
            );
        }
    }

    // Cancel hop
    function cancelHop(uint256 hopId) external nonReentrant {
        require(hopLibraryAddress != address(0), "HopLibrary not set");
        require(proxyRouter != address(0), "ProxyRouter not set");
        IHopLibrary(hopLibraryAddress).cancelHop(
            hopId,
            msg.sender,
            address(this),
            crossDriverAddress,
            isolatedDriverAddress,
            crossLibraryAddress,
            isolatedLibraryAddress,
            hopID[hopId],
            proxyRouter
        );
    }

    // Cancel all hops
    function cancelAll() external nonReentrant {
        require(hopLibraryAddress != address(0), "HopLibrary not set");
        require(proxyRouter != address(0), "ProxyRouter not set");
        uint256 canceled = IHopLibrary(hopLibraryAddress).cancelAll(
            msg.sender,
            address(this),
            crossDriverAddress,
            isolatedDriverAddress,
            crossLibraryAddress,
            isolatedLibraryAddress,
            hopsByAddress[msg.sender],
            hopID,
            proxyRouter
        );
        emit AllHopsCanceled(msg.sender, canceled);
    }

    // View functions
    function getHopDetails(uint256 hopId) external view returns (IHopLibrary.StalledHop memory) {
        return hopID[hopId];
    }

    function getHopsByAddress(address maker) external view returns (uint256[] memory) {
        return hopsByAddress[maker];
    }

    function getTotalHops() external view returns (uint256[] memory) {
        return totalHops;
    }
}