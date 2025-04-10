// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.1 (Updated)
// Changes:
// - Renamed MFPAgent to SSAgent, updated MFP to SS in interfaces and comments.
// - Replaced routerAddress with proxyRouter, isolatedDriver, crossDriver; updated setRouter to setProxyRouter.
// - Added taxCollector with determineCollector; required in listToken/listNative.
// - Added queryByAddress (tokenA/tokenB to listing indices) and queryByIndex (listingAddress by index).
// - Added helpers _deployPair, _initializePair, _updateState to listToken and listNative.

import "./imports/Ownable.sol";

interface ISSListingTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setLiquidityAddress(address _liquidityAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
}

interface ISSLiquidityTemplate {
    function setRouters(address[] memory _routers) external;
    function setListingId(uint256 _listingId) external;
    function setListingAddress(address _listingAddress) external;
    function setTokens(address _tokenA, address _tokenB) external;
    function setCollector(address _taxCollector) external;
}

interface ISSListingLibrary {
    function deploy(bytes32 salt) external returns (address);
}

interface ISSLiquidityLibrary {
    function deploy(bytes32 salt) external returns (address);
}

contract SSAgent is Ownable {
    address public proxyRouter;
    address public isolatedDriver;
    address public crossDriver;
    address public listingLibraryAddress;
    address public liquidityLibraryAddress;
    address public taxCollector;
    uint256 public listingCount;

    mapping(address => mapping(address => address)) public getListing;
    address[] public allListings;
    address[] public allListedTokens;
    mapping(address => uint256[]) public queryByAddress;

    event ListingCreated(address indexed tokenA, address indexed tokenB, address listingAddress, address liquidityAddress, uint256 listingId);

    // Internal helpers
    function tokenExists(address token) internal view returns (bool) {
        for (uint256 i = 0; i < allListedTokens.length; i++) {
            if (allListedTokens[i] == token) {
                return true;
            }
        }
        return false;
    }

    function _deployPair(address tokenA, address tokenB, uint256 listingId) internal returns (address listingAddress, address liquidityAddress) {
        bytes32 listingSalt = keccak256(abi.encodePacked(tokenA, tokenB, listingId));
        bytes32 liquiditySalt = keccak256(abi.encodePacked(tokenB, tokenA, listingId));
        listingAddress = ISSListingLibrary(listingLibraryAddress).deploy(listingSalt);
        liquidityAddress = ISSLiquidityLibrary(liquidityLibraryAddress).deploy(liquiditySalt);
        return (listingAddress, liquidityAddress);
    }

    function _initializePair(address listingAddress, address liquidityAddress, address tokenA, address tokenB, uint256 listingId) internal {
        address[] memory routers = new address[](3);
        routers[0] = proxyRouter;
        routers[1] = isolatedDriver;
        routers[2] = crossDriver;
        ISSListingTemplate(listingAddress).setRouters(routers);
        ISSListingTemplate(listingAddress).setListingId(listingId);
        ISSListingTemplate(listingAddress).setLiquidityAddress(liquidityAddress);
        ISSListingTemplate(listingAddress).setTokens(tokenA, tokenB);
        ISSLiquidityTemplate(liquidityAddress).setRouters(routers);
        ISSLiquidityTemplate(liquidityAddress).setCollector(taxCollector);
        ISSLiquidityTemplate(liquidityAddress).setListingId(listingId);
        ISSLiquidityTemplate(liquidityAddress).setListingAddress(listingAddress);
        ISSLiquidityTemplate(liquidityAddress).setTokens(tokenA, tokenB);
    }

    function _updateState(address tokenA, address tokenB, address listingAddress, uint256 listingId) internal {
        getListing[tokenA][tokenB] = listingAddress;
        allListings.push(listingAddress);
        if (!tokenExists(tokenA)) allListedTokens.push(tokenA);
        if (!tokenExists(tokenB)) allListedTokens.push(tokenB);
        queryByAddress[tokenA].push(listingId);
        queryByAddress[tokenB].push(listingId);
    }

    // Setup functions
    function setProxyRouter(address _proxyRouter) external onlyOwner {
        require(_proxyRouter != address(0), "Invalid proxy router address");
        proxyRouter = _proxyRouter;
    }

    function setIsolatedDriver(address _isolatedDriver) external onlyOwner {
        require(_isolatedDriver != address(0), "Invalid SSD address");
        isolatedDriver = _isolatedDriver;
    }

    function setCrossDriver(address _crossDriver) external onlyOwner {
        require(_crossDriver != address(0), "Invalid CSD address");
        crossDriver = _crossDriver;
    }

    function setListingLibrary(address _listingLibrary) external onlyOwner {
        require(_listingLibrary != address(0), "Invalid library address");
        listingLibraryAddress = _listingLibrary;
    }

    function setLiquidityLibrary(address _liquidityLibrary) external onlyOwner {
        require(_liquidityLibrary != address(0), "Invalid library address");
        liquidityLibraryAddress = _liquidityLibrary;
    }

    function determineCollector(address _taxCollector) external onlyOwner {
        require(_taxCollector != address(0), "Invalid tax collector address");
        taxCollector = _taxCollector;
    }

    // Core functions
    function listToken(address tokenA, address tokenB) external returns (address listingAddress, address liquidityAddress) {
        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(proxyRouter != address(0), "Proxy router not set");
        require(listingLibraryAddress != address(0), "Listing library not set");
        require(liquidityLibraryAddress != address(0), "Liquidity library not set");
        require(taxCollector != address(0), "Tax collector not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializePair(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    function listNative(address token, bool isA) external returns (address listingAddress, address liquidityAddress) {
        address nativeAddress = address(0);
        address tokenA = isA ? nativeAddress : token;
        address tokenB = isA ? token : nativeAddress;

        require(tokenA != tokenB, "Identical tokens");
        require(getListing[tokenA][tokenB] == address(0), "Pair already listed");
        require(proxyRouter != address(0), "Proxy router not set");
        require(listingLibraryAddress != address(0), "Listing library not set");
        require(liquidityLibraryAddress != address(0), "Liquidity library not set");
        require(taxCollector != address(0), "Tax collector not set");

        (listingAddress, liquidityAddress) = _deployPair(tokenA, tokenB, listingCount);
        _initializePair(listingAddress, liquidityAddress, tokenA, tokenB, listingCount);
        _updateState(tokenA, tokenB, listingAddress, listingCount);

        emit ListingCreated(tokenA, tokenB, listingAddress, liquidityAddress, listingCount);
        listingCount++;
        return (listingAddress, liquidityAddress);
    }

    // View functions
    function queryByIndex(uint256 index) external view returns (address) {
        require(index < allListings.length, "Invalid index");
        return allListings[index];
    }

    function queryByAddress(address target, uint256 maxIteration, uint256 step) external view returns (uint256[] memory) {
        uint256[] memory indices = queryByAddress[target];
        uint256 start = step * maxIteration;
        uint256 end = (step + 1) * maxIteration > indices.length ? indices.length : (step + 1) * maxIteration;
        uint256[] memory result = new uint256[](end - start);
        for (uint256 i = start; i < end; i++) {
            result[i - start] = indices[i];
        }
        return result;
    }

    function queryByAddressLength(address target) external view returns (uint256) {
        return queryByAddress[target].length;
    }

    function allListingsLength() external view returns (uint256) {
        return allListings.length;
    }

    function allListedTokensLength() external view returns (uint256) {
        return allListedTokens.length;
    }
}