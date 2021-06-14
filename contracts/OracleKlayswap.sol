// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "./lib/Babylonian.sol";
import "./lib/FixedPoint.sol";
import "./utils/Epoch.sol";
import "./interfaces/IERC20Detailed.sol";
import "./interfaces/IKlayswapStore.sol";
import "./interfaces/IKlayExchange.sol";

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract OracleKlayswap is Epoch {
    using FixedPoint for *;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // klayswap
    IKlayswapStore public store;
    address public token0;
    address public token1;
    address public pair;

    uint32 public blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    uint256 public token0Decimals;
    uint256 public token1Decimals;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _store,
        address _pair,
        uint256 _period,
        uint256 _startTime
    ) public Epoch(_period, _startTime, 0) {
        store = IKlayswapStore(_store);        
        pair = _pair;
        
        token0 = IKlayExchange(pair).tokenA();
        token1 = IKlayExchange(pair).tokenB();
        token0Decimals = IERC20Detailed(token0).decimals();
        token1Decimals = IERC20Detailed(token1).decimals();

        price0CumulativeLast = store.priceACumulativeLast(pair);
        price1CumulativeLast = store.priceBCumulativeLast(pair);
        blockTimestampLast = store.blockTimestampLast(pair);        

        uint112 reserve0_;
        uint112 reserve1_;
        uint32 blockTimestampLast_;
        (reserve0_, reserve1_, blockTimestampLast_) = store.getReserves(pair);
        require(reserve0_ != 0 && reserve1_ != 0, "Oracle: NO_RESERVES"); // ensure that there's liquidity in the pair
    }

    function _update() private view returns (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) {
        price0Cumulative = store.priceACumulativeLast(pair);
        price1Cumulative = store.priceBCumulativeLast(pair);
        blockTimestamp = store.blockTimestampLast(pair);
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    /** @dev Updates 1-day EMA price from Uniswap.  */
    function update() external checkEpoch {        
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = _update();
        
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed == 0) {
            // prevent divided by zero
            return;
        }

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;

        emit Updated(price0CumulativeLast, price1CumulativeLast);
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address _token, uint256 _amountIn) external view returns (uint256 _amountOut) {
        if (_token == token0) {
            _amountOut = price0Average.mul(_amountIn.mul(10**(18-token1Decimals))).decode144();
        } else {
            require(_token == token1, "Oracle: INVALID_TOKEN");
            _amountOut = price1Average.mul(_amountIn.mul(10**(18-token0Decimals))).decode144();
        }
    }

    function twap(address _token, uint256 _amountIn) external view returns (uint256 _amountOut) {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = _update();
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0) {
            if (_token == token0) {
                _amountOut = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)).mul(_amountIn.mul(10**(18-token1Decimals))).decode144();
            } else if (_token == token1) {
                _amountOut = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)).mul(_amountIn.mul(10**(18-token0Decimals))).decode144();
            }
        }
        else {
            if (_token == token0) {
                _amountOut = price0Average.mul(_amountIn.mul(10**(18-token1Decimals))).decode144();
            } else {
                _amountOut = price1Average.mul(_amountIn.mul(10**(18-token0Decimals))).decode144();
            }
        }
    }

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);
}
