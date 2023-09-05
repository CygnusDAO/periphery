//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusCollateral.sol
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
import {IAllowanceTransfer} from "./IAllowanceTransfer.sol";

interface ICygnusCollateral is IERC20Permit {
    /**
     *  @return underlying The address of the underlying (LP Token for collateral contracts, USDC for borrow contracts)
     */
    function underlying() external view returns (address);

    /**
     *  @return exchangeRate The ratio which 1 pool token can be redeemed for underlying amount.
     */
    function exchangeRate() external view returns (uint256);

    /**
     *  @return borrowable The address of the borrowable contract
     */
    function borrowable() external view returns (address);

    /**
     *  @return totalSupply The total supply of CygLP
     */
    function totalSupply() external view returns (uint256);

    /**
     *  @return totalAssets The total amount of LPs owned by the vault
     */
    function totalAssets() external view returns (uint256);

    /**
     *  @notice Gets an account's liquidity or shortfall
     *
     *  @param borrower The address of the borrower
     *  @return liquidity The account's liquidity in USDC
     *  @return shortfall If user has no liquidity, return the shortfall in USDC
     */
    function getAccountLiquidity(address borrower) external view returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Gets the account's total position value in USD (LP Tokens owned multiplied by LP price). It uses the oracle to get the
     *          price of the LP Token and uses the current exchange rate.
     *
     *  @param borrower The address of the borrower
     *
     *  @return cygLPBalance The user's balance of collateral (CygLP)
     *  @return principal The original loaned USDC amount (without interest)
     *  @return borrowBalance The original loaned USDC amount plus interest (ie. what the user must pay back)
     *  @return price The current liquidity token price
     *  @return positionUsd The borrower's position in USD. position = CygLP Balance * Exchange Rate * LP Token Price
     *  @return positionLp The borrower`s position in LP Tokens
     */
    function getBorrowerPosition(
        address borrower
    )
        external
        view
        returns (
            uint256 cygLPBalance,
            uint256 principal,
            uint256 borrowBalance,
            uint256 price,
            uint256 positionUsd,
            uint256 positionLp,
            uint256 rate,
            uint256 health
        );

    /**
     *  @notice This function must be called with the `approve` method of the underlying asset token contract for
     *          the `assets` amount on behalf of the sender before calling this function.
     *  @notice Implements the deposit of the underlying asset into the Cygnus Vault pool. This function transfers
     *          the underlying assets from the sender to this contract and mints a corresponding amount of Cygnus
     *          Vault shares to the recipient. A deposit fee may be charged by the strategy, which is deducted from
     *          the deposited assets.
     *
     *  @dev If the deposit amount is less than or equal to 0, this function will revert.
     *
     *  @param assets Amount of the underlying asset to deposit.
     *  @param recipient Address that will receive the corresponding amount of shares.
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param _signature The owner's signature over the permit data
     *  @return shares Amount of Cygnus Vault shares minted and transferred to the `recipient`.
     */
    function deposit(
        uint256 assets,
        address recipient,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata _signature
    ) external returns (uint256 shares);

    /**
     *  @notice Flash redeems the underlying LP Token
     *
     *  @dev This should be called from `Altair` contract
     *
     *  @param redeemer The address redeeming the tokens (Altair contract)
     *  @param assets The amount of the underlying assets to redeem
     *  @param data Calldata passed from and back to router contract
     *
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(address redeemer, uint256 assets, bytes calldata data) external returns (uint256 usdAmount);
}
