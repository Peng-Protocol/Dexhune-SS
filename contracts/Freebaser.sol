// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/access/Ownable.sol";

interface ILUSD {
    function rebase() external;
}

contract Freebaser is Ownable {
    ILUSD public LUSD;
    IERC721 public NFT;

    mapping(address => uint256) private lastFreebaseTime;

    event LUSDSet(address indexed newLUSD);
    event NFTSet(address indexed newNFT);
    event FreebaseExecuted(address indexed caller, bool paid);

    uint256 public constant COOLDOWN = 30 seconds;
    uint256 public constant REWARD_AMOUNT = 0.1 * 1e18; // 0.10 LUSD (18 decimals)

    /// @notice Sets the LUSD contract address
    /// @param _lusd Address of the LUSD contract
    function setLUSD(address _lusd) external onlyOwner {
        require(_lusd != address(0), "Invalid LUSD address");
        LUSD = ILUSD(_lusd);
        emit LUSDSet(_lusd);
    }

    /// @notice Sets the NFT contract address
    /// @param _nft Address of the NFT contract
    function setNFT(address _nft) external onlyOwner {
        require(_nft != address(0), "Invalid NFT address");
        NFT = IERC721(_nft);
        emit NFTSet(_nft);
    }

    /// @notice Calls the `rebase` function on LUSD and rewards the caller if possible
    function freebase() external {
        require(block.timestamp >= lastFreebaseTime[msg.sender] + COOLDOWN, "Cooldown active");
        require(NFT.balanceOf(msg.sender) > 0, "Must own at least 1 NFT");

        lastFreebaseTime[msg.sender] = block.timestamp;

        // Call the external rebase function
        try LUSD.rebase() {
            // Rebase successful
        } catch {
            // Rebase failed, but we continue execution
        }

        // Attempt to send 0.10 LUSD to the caller if balance allows
        bool paid = false;
        if (IERC20(address(LUSD)).balanceOf(address(this)) >= REWARD_AMOUNT) {
            IERC20(address(LUSD)).transfer(msg.sender, REWARD_AMOUNT);
            paid = true;
        }

        emit FreebaseExecuted(msg.sender, paid);
    }
}
