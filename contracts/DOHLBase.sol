// SPDX-License-Identifier: BSD-3-Clause
/// @title Standard Interface for ERC20 tokens


/*
*    ||_ __  __         
*   (|| |  \/  \|__||   
*   _||)|__/\__/|  ||__ 
*    ||                 
*/

import "./Ownable.sol";
import "./interfaces/IERC20.sol";

pragma solidity ^0.8.28;
abstract contract DOHLBase is Ownable, IERC20 {
    int128 _supply = 0;
    mapping(address => int128) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    
    error InsufficientBalance();
    error DuplicateTransferAddress();
    error InvalidTransferAddress();
    error NotEnoughAllowance(uint256 value, uint256 currentAllowance);
}