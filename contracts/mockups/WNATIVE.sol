// SPDX-License-Identifier: BSD-3-Clause
/// @title Mock contract for WNATIVE

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;
import "@openzeppelin-contracts-5.2.0/token/ERC20/ERC20.sol";

contract WNATIVE is ERC20 {
    uint256 private constant INITIAL_SUPPLY = 1000e18;

    constructor() ERC20("Wrapped Native Token", "WNATIVE") {
        _mint(_msgSender(), INITIAL_SUPPLY);
    }

    function decimals() public view virtual override returns(uint8) {
        return 18;
    }
}
