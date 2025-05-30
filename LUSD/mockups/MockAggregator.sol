// SPDX-License-Identifier: BSD-3-Clause
/// @title Mock aggregator contract

/*
 *     __    __  _______ ____
 *    / /   / / / / ___// __ \
 *   / /   / / / /\__ \/ / / /
 *  / /___/ /_/ /___/ / /_/ /
 * /_____/\____//____/_____/
 */

pragma solidity ^0.8.28;
import "../Ownable.sol";
import "../interfaces/IAggregator.sol";

contract MockAggregator is IAggregator, Ownable {
    uint256 _nextRound;

    mapping(uint256 => int256) private _answers;
    mapping(uint256 => uint256) private _timestamps;

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function latestAnswer() external view override returns (int256) {
        uint256 round = _nextRound;
        if (round > 0) round--;

        return _answers[round];
    }

    function latestTimestamp() external view override returns (uint256) {
        uint256 round = _nextRound;
        if (round > 0) round--;

        return _timestamps[round];
    }

    function latestRound() external view override returns (uint256) {
        return _nextRound - 1;
    }

    function getAnswer(
        uint256 roundId
    ) external view override returns (int256) {
        return _answers[roundId];
    }

    function getTimestamp(
        uint256 roundId
    ) external view override returns (uint256) {
        return _timestamps[roundId];
    }

    function setAnswer(int256 answer) external onlyOwner {
        _answers[_nextRound] = answer;
        _timestamps[_nextRound] = block.timestamp;

        _nextRound++;
    }
}
