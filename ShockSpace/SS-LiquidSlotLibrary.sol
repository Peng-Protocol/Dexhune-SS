// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.1;

// Version: 0.0.2 (Updated)
// Changes:
// - Modified xClaimFees to call claimFees with isX=false to claim yFees (tokenB) for tokenA providers (new in v0.0.2).
// - Modified yClaimFees to call claimFees with isX=true to claim xFees (tokenA) for tokenB providers (new in v0.0.2).
// - Side effects: Aligns fee claims with intended behavior (xSlots claim yFees, ySlots claim xFees).
// - No changes to xDeposit, yDeposit, xWithdraw, yWithdraw, xPrepOut, yPrepOut.
// - Note: decimalsA/decimalsB not addressed, as per user instruction to defer.

import "./imports/SafeERC20.sol";

interface ISS {
    function isValidListing(address listing) external view returns (bool);
}

interface ISSListing {
    function tokenA() external view returns (address);
    function tokenB() external view returns (address);
    function liquidityAddresses(uint256 index) external view returns (address);
    function volumeBalances(uint256 listingId) external view returns (uint256 xBalance, uint256 yBalance, uint256 xVolume, uint256 yVolume);
    function prices(uint256 listingId) external view returns (uint256);
}

interface ISSLiquidity {
    struct Slot {
        address depositor;
        address recipient;
        uint256 allocation;
        uint256 dVolume;
        uint256 timestamp;
    }

    function deposit(address caller, address token, uint256 amount) external payable;
    function updateLiquidity(address caller, bool isX, uint256 amount) external;
    function getXSlotView(uint256 index) external view returns (Slot memory);
    function getYSlotView(uint256 index) external view returns (Slot memory);
    function xExecuteOut(address caller, uint256 index, SSLiquidSlotLibrary.PreparedWithdrawal memory withdrawal) external;
    function yExecuteOut(address caller, uint256 index, SSLiquidSlotLibrary.PreparedWithdrawal memory withdrawal) external;
    function claimFees(address caller, address _listingAddress, uint256 liquidityIndex, bool isX, uint256 volume) external;
}

library SSLiquidSlotLibrary {
    using SafeERC20 for IERC20;

    struct PreparedWithdrawal {
        uint256 amountA;
        uint256 amountB;
    }

    function normalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount * 10 ** (18 - decimals);
        else return amount / 10 ** (decimals - 18);
    }

    function denormalize(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        else if (decimals < 18) return amount / 10 ** (18 - decimals);
        else return amount * 10 ** (decimals - 18);
    }

    function xPrepOut(
        address listingAddress,
        uint256 amount,
        uint256 index
    ) internal view returns (PreparedWithdrawal memory) {
        ISSListing listing = ISSListing(listingAddress);
        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        ISSLiquidity.Slot memory slot = liquidity.getXSlotView(index);
        require(slot.allocation >= amount, "Amount exceeds allocation");

        (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(0);
        uint256 withdrawAmountA = amount > xBalance ? xBalance : amount;
        uint256 deficit = amount > withdrawAmountA ? amount - withdrawAmountA : 0;
        uint256 withdrawAmountB = 0;

        if (deficit > 0) {
            uint256 currentPrice = listing.prices(0);
            require(currentPrice > 0, "Price cannot be zero");
            uint256 compensation = (deficit * 1e18) / currentPrice;
            withdrawAmountB = compensation > yBalance ? yBalance : compensation;
        }

        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function yPrepOut(
        address listingAddress,
        uint256 amount,
        uint256 index
    ) internal view returns (PreparedWithdrawal memory) {
        ISSListing listing = ISSListing(listingAddress);
        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        ISSLiquidity.Slot memory slot = liquidity.getYSlotView(index);
        require(slot.allocation >= amount, "Amount exceeds allocation");

        (uint256 xBalance, uint256 yBalance, , ) = listing.volumeBalances(0);
        uint256 withdrawAmountB = amount > yBalance ? yBalance : amount;
        uint256 deficit = amount > withdrawAmountB ? amount - withdrawAmountB : 0;
        uint256 withdrawAmountA = 0;

        if (deficit > 0) {
            uint256 currentPrice = listing.prices(0);
            require(currentPrice > 0, "Price cannot be zero");
            uint256 compensation = (deficit * currentPrice) / 1e18;
            withdrawAmountA = compensation > xBalance ? xBalance : compensation;
        }

        return PreparedWithdrawal(withdrawAmountA, withdrawAmountB);
    }

    function xDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        require(amount > 0, "Amount is zero");

        ISSListing listing = ISSListing(listingAddress);
        address token = listing.tokenA();
        require(token != address(0), "TokenA is zero");

        IERC20(token).safeTransferFrom(msg.sender, proxy, amount);

        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        liquidity.deposit(proxy, token, amount);
    }

    function yDeposit(address listingAddress, uint256 amount, address listingAgent, address proxy) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        require(amount > 0, "Amount is zero");

        ISSListing listing = ISSListing(listingAddress);
        address token = listing.tokenB();
        require(token != address(0), "TokenB is zero");

        IERC20(token).safeTransferFrom(msg.sender, proxy, amount);

        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        liquidity.deposit(proxy, token, amount);
    }

    function xWithdraw(
        address listingAddress,
        uint256 amount,
        uint256 index,
        address listingAgent,
        address proxy
    ) external returns (PreparedWithdrawal memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        ISSLiquidity.Slot memory slot = liquidity.getXSlotView(index);
        require(slot.depositor == msg.sender, "Not depositor");

        PreparedWithdrawal memory withdrawal = xPrepOut(listingAddress, amount, index);
        liquidity.xExecuteOut(proxy, index, withdrawal);

        return withdrawal;
    }

    function yWithdraw(
        address listingAddress,
        uint256 amount,
        uint256 index,
        address listingAgent,
        address proxy
    ) external returns (PreparedWithdrawal memory) {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");

        ISSListing listing = ISSListing(listingAddress);
        ISSLiquidity liquidity = ISSLiquidity(listing.liquidityAddresses(0));
        ISSLiquidity.Slot memory slot = liquidity.getYSlotView(index);
        require(slot.depositor == msg.sender, "Not depositor");

        PreparedWithdrawal memory withdrawal = yPrepOut(listingAddress, amount, index);
        liquidity.yExecuteOut(proxy, index, withdrawal);

        return withdrawal;
    }

    function xClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSLiquidity liquidity = ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(0));
        liquidity.claimFees(proxy, listingAddress, liquidityIndex, false, 0); // Claim yFees (tokenB) for xSlots
    }

    function yClaimFees(address listingAddress, uint256 liquidityIndex, address listingAgent, address proxy) external {
        require(ISS(listingAgent).isValidListing(listingAddress), "Invalid listing");
        ISSLiquidity liquidity = ISSLiquidity(ISSListing(listingAddress).liquidityAddresses(0));
        liquidity.claimFees(proxy, listingAddress, liquidityIndex, true, 0); // Claim xFees (tokenA) for ySlots
    }
}