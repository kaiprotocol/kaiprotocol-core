// SPDX-License-Identifier: MIT
pragma solidity >= 0.5.0;

interface ITreasury {
    function round() external view returns (uint256);

    function nextRoundPoint() external view returns (uint256);

    function getKAIPrice() external view returns (uint256);

    function buyBKAI(uint256 amount, uint256 targetPrice) external;

    function redeemBKAI(uint256 amount, uint256 targetPrice) external;
}
