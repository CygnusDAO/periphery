//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusTransmission.sol
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

// Interfaces
import {IHangar18} from "./core/IHangar18.sol";
import {ICygnusBorrow} from "./core/ICygnusBorrow.sol";

/**
 *  @notice Cygnus lens interface
 */
interface ICygnusTransmissions {

    /**
     *  @return Name of the transmitter
     */
    function name() external view returns (string memory);

    /**
     *  @return version The version of the transmitter
     */
    function version() external view returns (string memory);

    /**
     *  @notice Get the borrower`s full position
     *  @param borrowable The address of the borrowable contract
     *  @param borrower The address of the borrower
     *  @return cygLPBalance The user's balance of collateral (CygLP)
     *  @return principal The original loaned USDC amount (without interest)
     *  @return borrowBalance The original loaned USDC amount plus interest (ie. what the user must pay back)
     *  @return price The current liquidity token price
     *  @return rate The current exchange rate between CygLP and LP Token
     *  @return lpBalance The borrower`s position in LP Tokens
     *  @return positionUsd The borrower's position in USD. position = CygLP Balance * Exchange Rate * LP Token Price
     *  @return health The user's current loan health (once it reaches 100% the user becomes liquidatable)
     */
    function latestBorrowerPosition(
        ICygnusBorrow borrowable,
        address borrower
    )
        external
        returns (
            uint256 cygLPBalance,
            uint256 principal,
            uint256 borrowBalance,
            uint256 price,
            uint256 rate,
            uint256 lpBalance,
            uint256 positionUsd,
            uint256 health
        );

    /**
     *  @notice Get the lender`s full position
     *  @param borrowable The address of the borrowable contract
     *  @param lender The address of the lender
     *  @return cygUsdBalance The `lender's` balance of CygUSD
     *  @return rate The currente exchange rate
     *  @return usdBalance The lender's balance of the stablecoin
     *  @return positionUsd The lender's position in USD
     */
    function latestLenderPosition(
        ICygnusBorrow borrowable,
        address lender
    ) external returns (uint256 cygUsdBalance, uint256 rate, uint256 usdBalance, uint256 positionUsd);

    /**
     *  @notice Get the borrower's latest account liquidity
     *  @param borrowable The address of the borrowable contract
     *  @param borrower The address of the borrower
     *  @return liquidity The position's liquidity in stablecoins (if any)
     *  @return shortfall The position's shortfall in stablecoins (if any)
     */
    function latestAccountLiquidity(ICygnusBorrow borrowable, address borrower) external returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Get the whole lending pool info with latest interest rate accruals
     *  @param borrowable The address of the borrowable contract
     *  @return supplyApr The latest annualized return for lenders
     *  @return borrowApr The latest interest rate for borrowers
     *  @return util The latest utilization rate
     *  @return totalBorrows The latest total borrows
     *  @return totalBalance The latest available cash
     *  @return exchangeRate The latest exchange rate between USD and CygUSD
     */
    function latestShuttleInfo(
        ICygnusBorrow borrowable
    )
        external
        returns (uint256 supplyApr, uint256 borrowApr, uint256 util, uint256 totalBorrows, uint256 totalBalance, uint256 exchangeRate);

    /**
     *  @notice Get the borrower's TVL in Cygnus
     *  @param hangar18 The address of the hangar18 contract on this chain
     *  @param borrower The address of the borrower
     *  @return principal The original loaned USDC amount (without interest)
     *  @return borrowBalance The original loaned USDC amount plus interest (ie. what the user must pay back)
     *  @return positionUsd The borrower's position in USD. position = CygLP Balance * Exchange Rate * LP Token Price
     */
    function latestBorrowerAll(IHangar18 hangar18, address borrower) external returns (uint256 principal, uint256 borrowBalance, uint256 positionUsd);

    /**
     *  @notice Get the lender's TVL in Cygnus
     *  @param hangar18 The address of the hangar18 contract on this chain
     *  @param lender The address of the lender
     *  @return cygUsdBalance The `lender's` balance of CygUSD
     *  @return usdBalance The lender`s stablecoin balance
     *  @return positionUsd The lender's position in USD
     */
    function latestLenderAll(IHangar18 hangar18, address lender) external returns (uint256 cygUsdBalance, uint256 usdBalance, uint256 positionUsd);
}
