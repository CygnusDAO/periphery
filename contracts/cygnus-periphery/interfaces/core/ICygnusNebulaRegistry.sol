//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusNebulaRegistry.sol
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
pragma solidity ^0.8.17;

// Interfaces
import {IERC20} from "./IERC20.sol";

/**
 *  @title ICygnusNebulaRegistry Interface to interact with Cygnus' LP Oracle
 *  @author CygnusDAO
 */
interface ICygnusNebulaRegistry {
    /**
     *  @notice Gets the latest info for an initialized LP Token
     *  @param lpTokenPair The address of the LP Token
     *  @return tokens Array of addresses of all the LP's assets
     *  @return prices Array of prices of each asset (in denom token)
     *  @return reserves Array of reserves of each asset in the LP
     *  @return tokenDecimals Array of decimals of each token
     *  @return reservesUsd Array of reserves of each asset in USD
     */
    function getLPTokenInfo(
        address lpTokenPair
    )
        external
        view
        returns (
            IERC20[] memory tokens,
            uint256[] memory prices,
            uint256[] memory reserves,
            uint256[] memory tokenDecimals,
            uint256[] memory reservesUsd
        );
}
