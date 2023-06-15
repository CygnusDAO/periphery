// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

import {FixedPointMathLib} from "./FixedPointMathLib.sol";

library CygnusDexLib {
    using FixedPointMathLib for uint256;

    /**
     *  @dev Compute optimal deposit amount (https://blog.alphaventuredao.io/onesideduniswap/)
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     *  @param swapFee The fee charged by this dex for a swap (ie Uniswap = 997/1000 = 0.3%)
     *  @return optimal swap amount of tokenA to tokenB to then hold the same proportion of assets as in pool reserves
     */
    function optimalDepositA(uint256 amountA, uint256 reservesA, uint256 swapFee) internal pure returns (uint256) {
        // Calculate with dex swap fee
        uint256 _swapFee = 10000 - swapFee;
        uint256 a = (10000 + _swapFee) * reservesA;
        uint256 b = amountA * 10000 * reservesA * 4 * _swapFee;
        uint256 c = FixedPointMathLib.sqrt(a * a + b);
        uint256 d = 2 * _swapFee;
        return (c - a) / d;
    }

    function _optimalDeposit(
        uint256 _amountA,
        uint256 _amountB,
        uint256 _reserveA,
        uint256 _reserveB,
        uint256 _decimalsA,
        uint256 _decimalsB
    ) internal pure returns (uint256) {
        uint256 num;
        uint256 den;
        {
            uint256 a = _amountA.divWad(_decimalsA);
            uint256 b = _amountB.divWad(_decimalsB);
            uint256 x = _reserveA.divWad(_decimalsA);
            uint256 y = _reserveB.divWad(_decimalsB);
            uint256 p;
            {
                uint256 x2 = x.mulWad(x);
                uint256 y2 = y.mulWad(y);
                p = (y * ((x2 * 3 + y2).divWad(y2 * 3 + x2))) / x;
            }
            num = a * y - b * x;
            den = (a + x).mulWad(p) + y + b;
        }

        return ((num / den) * _decimalsA) / 1e18;
    }
}
