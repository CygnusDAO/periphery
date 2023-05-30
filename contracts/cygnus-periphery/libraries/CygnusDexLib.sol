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
        uint256 a = (1000 + swapFee) * reservesA;
        uint256 b = amountA * 1000 * reservesA * 4 * swapFee;
        uint256 c = FixedPointMathLib.sqrt(a * a + b);
        uint256 d = 2 * swapFee;
        return (c - a) / d;
    }
}