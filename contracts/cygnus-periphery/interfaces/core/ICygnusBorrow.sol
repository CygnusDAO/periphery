//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusBorrow.sol
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

import {IERC20Permit} from "./IERC20Permit.sol";

interface ICygnusBorrow is IERC20Permit { 
    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *
     *  @param borrower The address of the Borrow contract.
     *  @param receiver The address of the receiver of the borrow amount.
     *  @param borrowAmount The amount of the underlying asset to borrow.
     *  @param data Calltype data passed to Router contract.
     *
     *  @custom:security non-reentrant
     */
    function borrow(address borrower, address receiver, uint256 borrowAmount, bytes calldata data) external returns (uint256);

    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *
     *  @param borrower The address of the borrower being liquidated
     *  @param receiver The address of the receiver of the collateral
     *  @param repayAmount USD amount covering the loan
     *  @param data Calltype data passed to Router contract.
     *  @return usdAmount The amount of USD deposited after taking into account liq. incentive
     *
     *  @custom:security non-reentrant
     */
    function liquidate(address borrower, address receiver, uint256 repayAmount, bytes calldata data) external returns (uint256 usdAmount);

    /**
     *  @notice This public view function is used to get the borrow balance of users based on stored data
     *
     *  @param borrower The address whose balance should be calculated
     *
     *  @return principal The USD amount borrowed without interest accrual
     *  @return borrowBalance The USD amount borrowed with interest accrual (ie. USD amount the borrower must repay)
     */
    function getBorrowBalance(address borrower) external view returns (uint256 principal, uint256 borrowBalance);

    /**
     *  @notice Applies interest accruals to borrows and reserves
     */
    function accrueInterest() external;

    /**
     *  @return underlying The address of the underlying (LP Token for collateral contracts, USDC for borrow contracts)
     */
    function underlying() external view returns (address);
}
