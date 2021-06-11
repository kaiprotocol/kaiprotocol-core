// SPDX-License-Identifier: MIT
pragma solidity >= 0.5.0;

interface IKlayswapStore {
    function reserveA(address) external view returns (uint112);

    function reserveB(address) external view returns (uint112);

    function getReserves(address) external view returns(uint112 _reserveA, uint112 _reserveB, uint32 _blockTimestampLast);

    function priceACumulativeLast(address) external view returns(uint256);

    function priceBCumulativeLast(address) external view returns(uint256);

    function blockTimestampLast(address) external view returns(uint32);

    event Sync(address pool, uint112 reserveA, uint112 reserveB);
}
