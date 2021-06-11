// SPDX-License-Identifier: MIT
pragma solidity >= 0.5.0;

interface IKlayswapFactory {
    function exchangeKlayPos(address token, uint amount, address[] calldata path) payable external;
    function exchangeKlayNeg(address token, uint amount, address[] calldata path) payable external;
    function exchangeKctPos(address tokenA, uint amountA, address tokenB, uint amountB, address[] calldata path) external;
    function exchangeKctNeg(address tokenA, uint amountA, address tokenB, uint amountB, address[] calldata path) external;
}
