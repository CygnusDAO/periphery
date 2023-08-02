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
     *  @notice Get the lender`s full position
     *  @param lender The address of the lender
     *  @return cygUsdBalance The `lender's` balance of CygUSD
     *  @return rate The currente exchange rate
     *  @return positionInUsd The lender's position in USD
     */
    function getLenderPosition(address lender) external view returns (uint256 cygUsdBalance, uint256 rate, uint256 positionInUsd);

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

    /**
     *  @return collateral The address of this borrowable's collateral
     */
    function collateral() external view returns (address);

    /**
     *  @return supplyRate The current APR for lenders
     */
    function supplyRate() external view returns (uint256);

    /**
     *  @return borrowRate The current per-second borrow rate stored for this pool.
     */
    function borrowRate() external view returns (uint48);

    /**
     *  @return utilizationRate The total amount of borrowed funds divided by the total cash the pool has available
     */
    function utilizationRate() external view returns (uint256);

    /**
     *  @return totalBorrows Total borrows stored in the lending pool
     */
    function totalBorrows() external view returns (uint96);

    /**
     *  @return totalBalance Total USD balance in the pool
     */
    function totalBalance() external view returns (uint160);

    /**
     *  @return exchangeRate The latest exchange rate
     */
    function exchangeRate() external view returns (uint256);

    /**
     *  @notice Syncs the total balance to the underlying balance and accrues interest
     *  @custom:security non-reentrant
     */
    function sync() external;
}
