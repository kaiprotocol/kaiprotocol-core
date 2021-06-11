// SPDX-License-Identifier: MIT
pragma solidity >= 0.5.0;

interface IKlayExchange {
    function tokenA() external view returns(address);

    function tokenB() external view returns(address);

    function getCurrentPool() external view returns(uint256 balance0, uint256 balance1);

    function estimatePos(address token, uint256 amount) external view returns(uint256);

    function estimateNeg(address token, uint256 amount) external view returns(uint256);
}
