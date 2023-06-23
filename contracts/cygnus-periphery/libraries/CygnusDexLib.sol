//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusDexLib.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
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
}
