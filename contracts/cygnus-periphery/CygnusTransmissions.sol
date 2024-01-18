//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusAltair.sol
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

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  
    .         🛰️    .            .               .      🛰️     .           .                .           .
           █████████           ---======*.                                                .           ⠀
          ███░░░░░███                                               📡                🌔      🛰️                   . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .          
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀🛰️
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                       ███ ░███  ███ ░███                .                 .                 .  ⠀
     🛰️  .             ░░██████  ░░██████                 🛰️                             .                 .           
                      ░░░░░░    ░░░░░░      -------=========*             🛰️         .                     ⠀
           .                            .🛰️       .          .            .                         🛰️ .             .⠀
    
        CYGNUS PERIPHERY ROUTER - `Altair`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusTransmissions} from "./interfaces/ICygnusTransmissions.sol";

// Cygnus Core
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";

/**
 *  @title  CygnusTransmissions
 *  @author CygnusDAO
 *  @notice Simple lens contract to only view/get data from cygnus core via static calls
 */
contract CygnusTransmissions is ICygnusTransmissions {
    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusTransmissions
     */
    string public constant override name = "Cygnus: Transmissions";

    /**
     *  @inheritdoc ICygnusTransmissions
     */
    string public constant override version = "1.0.0";

    /**
     *  @notice Accrues interest and syncs balance
     *  @inheritdoc ICygnusTransmissions
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
        )
    {
        // Accrue interest and update balance
        borrowable.sync();

        // Get collateral contract
        ICygnusCollateral collateral = ICygnusCollateral(borrowable.collateral());

        // CygLP Balance of borrower
        cygLPBalance = collateral.balanceOf(borrower);

        // Principal (borrowed amount) + borrow balance (borrowed amount + interest)
        (principal, borrowBalance) = borrowable.getBorrowBalance(borrower);

        // Get price of LP
        price = collateral.getLPTokenPrice();

        // Exchange rate between 1 CygLP and LP
        rate = collateral.exchangeRate();

        // The balance of the borrower
        (lpBalance, positionUsd, health) = collateral.getBorrowerPosition(borrower);
    }

    /**
     *  @notice Accrues interest and syncs balance
     *  @inheritdoc ICygnusTransmissions
     */
    function latestLenderPosition(
        ICygnusBorrow borrowable,
        address lender
    ) external override returns (uint256 cygUsdBalance, uint256 rate, uint256 usdBalance, uint256 positionUsd) {
        // Accrue interest and update balance
        borrowable.sync();

        // CygUSd balance of lender
        cygUsdBalance = borrowable.balanceOf(lender);

        // Exchange rate between 1 CygUSD and USD
        rate = borrowable.exchangeRate();

        (usdBalance, positionUsd) = borrowable.getLenderPosition(lender);
    }

    /**
     *  @notice Accrues interest and syncs balance
     *  @inheritdoc ICygnusTransmissions
     */
    function latestAccountLiquidity(
        ICygnusBorrow borrowable,
        address borrower
    ) external override returns (uint256 liquidity, uint256 shortfall) {
        // Accrue interest and update balance
        borrowable.sync();

        // Get collateral contract
        address collateral = borrowable.collateral();

        // Liquidity info
        (liquidity, shortfall) = ICygnusCollateral(collateral).getAccountLiquidity(borrower);
    }

    /**
     *  @notice Accrues interest and syncs balance
     *  @inheritdoc ICygnusTransmissions
     */
    function latestShuttleInfo(
        ICygnusBorrow borrowable
    )
        external
        override
        returns (uint256 supplyApr, uint256 borrowApr, uint256 util, uint256 totalBorrows, uint256 totalBalance, uint256 exchangeRate)
    {
        // Accrue interest and update balance
        borrowable.sync();

        // For APRs
        uint256 secondsPerYear = 24 * 60 * 60 * 365;

        // The APR for lenders
        supplyApr = borrowable.supplyRate() * secondsPerYear;

        // The interest rate for borrowers
        borrowApr = borrowable.borrowRate() * secondsPerYear;

        // Utilization rate
        util = borrowable.utilizationRate();

        // Total borrows stored in the contract
        totalBorrows = borrowable.totalBorrows();

        // Available cash
        totalBalance = borrowable.totalBalance();

        // The latest exchange rate
        exchangeRate = borrowable.exchangeRate();
    }

    /**
     *  @notice Get all positions for borrower in Cygnus protocol
     *  @notice Accrues interest and syncs balance
     *  @inheritdoc ICygnusTransmissions
     */
    function latestBorrowerAll(
        IHangar18 hangar18,
        address borrower
    ) external override returns (uint256 principal, uint256 borrowBalance, uint256 positionUsd) {
        // Total lending pools in Cygnus
        uint256 totalShuttles = hangar18.shuttlesDeployed();

        // Loop through each pool and update borrower's position
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Get borrowale and collateral for shuttle `i`
            (, , address borrowable, address collateral, ) = hangar18.allShuttles(i);

            // Accrue interest in borrowable
            ICygnusBorrow(borrowable).sync();

            // Get collateral position
            (uint256 _principal, uint256 _borrowBalance) = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

            // The balance of the borrower
            (, uint256 _positionUsd, ) = ICygnusCollateral(collateral).getBorrowerPosition(borrower);

            // Increase total principal
            principal += _principal;

            // Increase total borrowed balance
            borrowBalance += _borrowBalance;

            // Increase the borrower`s position in USD
            positionUsd += _positionUsd;
        }
    }

    /**
     *  @notice Get all positions for lender in Cygnus protocol
     *  @notice Accrues interest and syncs balance
     *  @inheritdoc ICygnusTransmissions
     */
    function latestLenderAll(
        IHangar18 hangar18,
        address lender
    ) external override returns (uint256 cygUsdBalance, uint256 usdBalance, uint256 positionUsd) {
        // Total lending pools in Cygnus
        uint256 totalShuttles = hangar18.shuttlesDeployed();

        // Loop through each pool and update lender's position
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Get borrowable contract for shuttle `i`
            (, , address borrowable, , ) = hangar18.allShuttles(i);

            // Accrue interest
            ICygnusBorrow(borrowable).sync();

            // Get lender position
            (uint256 _usdBalance, uint256 _positionUsd) = ICygnusBorrow(borrowable).getLenderPosition(lender);

            // Increase shares balance
            cygUsdBalance += ICygnusBorrow(borrowable).balanceOf(lender);

            // Increase stablecoin balance
            usdBalance += _usdBalance;

            // Increase position denominated in USD using stablecoin's price
            positionUsd += _positionUsd;
        }
    }
}
