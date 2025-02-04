// SPDX-License-Identifier: BSD-3-Clause
/// @title Dexhune ERC20 Root Implementation


/*
*    ||_ __  __         
*   (|| |  \/  \|__||   
*   _||)|__/\__/|  ||__ 
*    ||                 
*/

pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DOHL is ERC20 {
    constructor() ERC20("Link Dollar", "DOHL") {   
    }

    
}