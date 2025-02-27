// SPDX-License-Identifier: BSD-3-Clause
/// @title MarkerDAO

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;
import "./Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MarkerDAO is Ownable {
    IERC721Enumerable public nftCollection;

    mapping(uint256 => address) private _holders;
    mapping(address => uint256) private _addressUsed;
    uint256 private _gatherId;

    event NATIVETransferred(uint256 amount, address targetAddr);

    error ZeroBalance();
    error ZeroNFTs();
    error InsufficientDistributionBalance(uint256 balance);

    function setNFTCollection(address nftAddr) external onlyOwner {
        nftCollection = IERC721Enumerable(nftAddr);
    }

    function _gatherHolders() private returns (uint256 holderCount) {
        uint256 n;

        uint256 eSupply = 0;
        uint256 totalSupply = nftCollection.totalSupply();
        _gatherId++;

        while (eSupply < totalSupply && n < totalSupply) {
            uint256 tokenId = nftCollection.tokenByIndex(n++);
            address own = nftCollection.ownerOf(tokenId);

            if (own != address(0) && _addressUsed[own] != _gatherId) {
                _addressUsed[own] = _gatherId;
                _holders[holderCount++] = own;

                eSupply += nftCollection.balanceOf(own);
            }
        }
    }

    function _getDec(
        IERC20Metadata token
    ) private view returns (uint8 decimals) {
        try token.decimals() returns (uint8 dec) {
            decimals = dec;
        } catch {
            decimals = 18;
        }
    }

    function distributeNative() external {
        uint256 contractBal = address(this).balance;

        if (contractBal <= 0) {
            revert ZeroBalance();
        }

        uint256 holderCount = _gatherHolders();
        uint256 nftSupply = nftCollection.totalSupply();

        if (nftSupply <= 0) {
            revert ZeroNFTs();
        }

        uint256 toShare = contractBal / nftSupply;

        if (toShare <= 0) {
            revert InsufficientDistributionBalance(contractBal);
        }

        for (uint256 i = 0; i < holderCount; i++) {
            address holder = _holders[i];

            if (holder == address(this)) {
                continue;
            }

            uint256 holderBalance = nftCollection.balanceOf(holder);

            uint256 cut = toShare * holderBalance;

            if (cut > 0) {
                _sendNATIVE(payable(holder), cut);
            }
        }
    }

    function distributeToken(address tokenAddr) external {
        IERC20Metadata token = IERC20Metadata(tokenAddr);
        uint256 contractBal = token.balanceOf(address(this));
        if (contractBal <= 0) {
            revert ZeroBalance();
        }

        uint256 holderCount = _gatherHolders();
        uint256 nftSupply = nftCollection.totalSupply();

        if (nftSupply <= 0) {
            revert ZeroNFTs();
        }

        uint256 toShare = contractBal / nftSupply;

        if (toShare <= 0) {
            revert InsufficientDistributionBalance(contractBal);
        }

        for (uint256 i = 0; i < holderCount; i++) {
            address holder = _holders[i];

            if (holder == address(this)) {
                continue;
            }

            uint256 holderBalance = nftCollection.balanceOf(holder);

            uint256 cut = toShare * holderBalance;

            if (cut > 0) {
                token.transfer(holder, cut);
            }
        }
    }

    function _sendNATIVE(
        address payable to,
        uint256 amount
    ) internal returns (bool) {
        if (to.send(amount)) {
            emit NATIVETransferred(amount, to);
            return true;
        }

        return false;
    }

    receive() external payable {}
    fallback() external payable {}
}
