//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusNebula.sol
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

/**
 *  @title ICygnusNebula Interface to interact with Cygnus' LP Oracle
 *  @author CygnusDAO
 */
interface ICygnusNebula {
    /**
     *  @notice Gets the latest price of the LP Token's token0 and token1 denominated in denomination token
     *  @notice Used by Cygnus Altair contract to calculate optimal amount of leverage
     *
     *  @param lpTokenPair The address of the LP Token
     *  @return Array of the LP's asset prices
     */
    function assetPricesUsd(address lpTokenPair) external view returns (uint256[] memory);
}
