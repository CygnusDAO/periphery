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
pragma solidity >=0.8.17;

// Interfaces
import {IERC20} from "./core/IERC20.sol";
import {IHangar18} from "./core/IHangar18.sol";
import {IWrappedNative} from "./IWrappedNative.sol";
import {ICygnusBorrow} from "./core/ICygnusBorrow.sol";

// Permit2
import {IAllowanceTransfer} from "./core/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "./core/ISignatureTransfer.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltair {
    /**
     *  @notice Enum for choosing dex aggregators to perform leverage, deleverage and flash liquidations
     *  @custom:member PARASWAP Uses Paraswap
     *  @custom:member ONE_INCH Uses 1inch with the legacy `swap` mmethod
     *  @custom:member ONE_INCH Uses 1inch with optimized routers
     *  @custom:member OxPROJECT Uses 0xProjects swap API
     *  @custom:member OPEN_OCEAN_V1 Uses OpenOcean  with the legacy `swap` method
     *  @custom:member OPEN_OCEAN_V2 Uses OpenOcean with `uniswapV3SwapTo` method
     */
    enum DexAggregator {
        PARASWAP,
        ONE_INCH_LEGACY,
        ONE_INCH_V2,
        OxPROJECT,
        OPEN_OCEAN_LEGACY,
        OPEN_OCEAN_V2
    }

    /**
     *  @custom:struct AltairLeverageCalldata Encoded bytes passed to Cygnus Borrow contract for leverage
     *  @custom:member lpTokenPair The address of the LP Token
     *  @custom:member collateral The address of the Cygnus collateral contract
     *  @custom:member borrowable The address of the Cygnus borrow contract
     *  @custom:member recipient The address of the user receiving the leveraged LP Tokens
     *  @custom:member lpAmountMin The minimum amount of LP Tokens to receive
     */
    struct AltairLeverageCalldata {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 lpAmountMin;
        DexAggregator dexAggregator;
        bytes[] swapdata;
    }

    /**
     *  @custom:struct AltairDeleverageCalldata Encoded bytes passed to Cygnus Collateral contract for de-leverage
     *  @custom:member lpTokenPair The address of the LP Token
     *  @custom:member collateral The address of the collateral contract
     *  @custom:member borrowable The address of the borrow contract
     *  @custom:member recipient The address of the user receiving the de-leveraged assets
     *  @custom:member redeemTokens The amount of CygLP to redeem
     *  @custom:member usdAmountMin The minimum amount of USD to receive by redeeming `redeemTokens`
     *  @custom:member swapdata The 1inch swap data byte array to convert Liquidity Tokens to USD
     */
    struct AltairDeleverageCalldata {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 redeemTokens;
        uint256 usdAmountMin;
        DexAggregator dexAggregator;
        bytes[] swapdata;
    }

    /**
     *  @custom:struct AltairLiquidateCalldata Encoded bytes passed to Cygnus Borrow contract for liquidating borrows
     *  @custom:member lpTokenPair The address of the LP Token
     *  @custom:member collateral The address of the collateral contract
     *  @custom:member borrowable The address of the borrow contract
     *  @custom:member recipient The address of the liquidator (or this contract if protocol liquidation)
     *  @custom:member borrower The address of the borrower being liquidated
     *  @custom:member repayAmount The USD amount being repaid by the liquidator
     *  @custom:member swapdata The 1inch swap data byte array to convert Liquidity Tokens to USD after burning
     */
    struct AltairLiquidateCalldata {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        address borrower;
        uint256 repayAmount;
        DexAggregator dexAggregator;
        bytes[] swapdata;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the current block.timestamp is past deadline
     *
     *  @custom:error TransactionExpired
     */
    error CygnusAltair__TransactionExpired();

    /**
     *  @dev Reverts when the msg sender is not the cygnus factory admin
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusAltair__MsgSenderNotAdmin();

    /**
     *  @dev Reverts when the paraswap transaction fails
     *
     *  @custom:error ParaswapTransactionFailed
     */
    error CygnusAltair__ParaswapTransactionFailed();

    /**
     *  @dev Reverts when the 1inch transaction fails
     *
     *  @custom:error OneInchTransactionFailed
     */
    error CygnusAltair__OneInchTransactionFailed();

    /**
     *  @dev Reverts when the 0x swap api transaction fails
     *
     *  @custom:error 0xProjectTransactionFailed
     */
    error CygnusAltair__0xProjectTransactionFailed();

    /**
     *  @dev Reverts when the OpenOcean transaction fails
     *
     *  @custom:error OpenOceanTransactionFailed
     */
    error CygnusAltair__OpenOceanTransactionFailed();

    /**
     *  @dev Reverts if an extension has not been set for the borrowable or collateral
     *
     *  @custom:error AltairXDoesNotExist
     */
    error CygnusAltair__AltairXDoesNotExist();

    /**
     *  @dev Reverts if the shuttle does not exist when initializing an extension for it
     *
     *  @custom:erro ShuttleDoesNotExist
     */
    error CygnusAltair__ShuttleDoesNotExist();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Array of all initialized extensions
     */
    function allExtensions(uint256 index) external view returns (address);

    /**
     *  @return PERMIT Uniswap's Permit2 router
     */
    function PERMIT2() external view returns (address);

    /**
     *  @return PARASWAP_AUGUSTUS_SWAPPER_V5 The address of the Paraswap router used to perform the swaps
     */
    function PARASWAP_AUGUSTUS_SWAPPER_V5() external pure returns (address);

    /**
     *  @return ONE_INCH_ROUTER_V5 The address of the 1Inch router used to perform the swaps
     */
    function ONE_INCH_ROUTER_V5() external pure returns (address);

    /**
     *  @return OxPROJECT_EXCHANGE_PROXY The address of 0x's exchange proxy
     */
    function OxPROJECT_EXCHANGE_PROXY() external pure returns (address);

    /**
     *  @return OPEN_OCEAN_EXCHANGE_PROXY The address of OpenOcean's exchange router
     */
    function OPEN_OCEAN_EXCHANGE_PROXY() external pure returns (address);

    /**
     *  @return name The human readable name this router is for
     */
    function name() external view returns (string memory);

    /**
     *  @return version The version of the router
     */
    function version() external view returns (string memory);

    /**
     *  @return hangar18 The address of the Cygnus factory contract V1 - Used to get the nativeToken and USD address
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return usd The address of USD on this chain, used for the leverage/deleverage swaps
     */
    function usd() external view returns (address);

    /**
     *  @return nativeToken The address of the native token on this chain (ie. WETH)
     */
    function nativeToken() external view returns (IWrappedNative);

    /**
     *  @notice Returns the altair extension for a borrowable or collateral contract
     *  @param poolToken The address of a Cygnus borrowable or collateral or an lp token pair
     *  @return The address of the extension
     */
    function getAltairExtension(address poolToken) external view returns (address);

    /**
     *  @notice Returns the altair extension for a shuttle id
     *  @param shuttleId The ID of the lending pool
     *  @return The address of the extension
     */
    function getShuttleExtension(uint256 shuttleId) external view returns (address);

    /**
     *  @return altairExtensionsLength How many extensions we have added to the router so far
     */
    function altairExtensionsLength() external view returns (uint256);

    /**
     *  @dev Returns the assets and amounts received by redeeming a given amount of underlying liquidity tokens.
     *  @param underlying The address of the underlying liquidity token (e.g., LP token or Balancer BPT).
     *  @param shares The amount of underlying liquidity tokens to redeem.
     *  @return tokens An array of addresses representing the received tokens.
     *  @return amounts An array of corresponding amounts received by redeeming the liquidity tokens.
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares,
        uint256 slippage
    ) external view returns (address[] memory tokens, uint256[] memory amounts);

    /**
     *  @dev Returns whether an extension is set or not
     *  @param extension The addres of CygnusAltairX
     */
    function isExtension(address extension) external returns (bool);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Gets the account's total position value in USD (LP Tokens owned multiplied by LP price). It uses the oracle to get the
     *          price of the LP Token and uses the current exchange rate.
     *  @param borrowable The address of the borrowable contract
     *  @param borrower The address of the borrower
     *  @return cygLPBalance The user's balance of collateral (CygLP)
     *  @return principal The original loaned USDC amount (without interest)
     *  @return borrowBalance The original loaned USDC amount plus interest (ie. what the user must pay back)
     *  @return price The current liquidity token price
     *  @return rate The current exchange rate between CygLP and LP Token
     *  @return positionUsd The borrower's position in USD. position = CygLP Balance * Exchange Rate * LP Token Price
     *  @return positionLp The borrower`s position in LP Tokens
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
            uint256 positionUsd,
            uint256 positionLp,
            uint256 health
        );

    /**
     *  @notice Get the latest account liquidity for a user
     *  @param borrowable Address of the Borrow contract
     *  @param borrower Address of the borrower
     *  @return liquidity The account's liquidity (if any)
     *  @return shortfall The account's shortfall (if any)
     */
    function latestAccountLiquidity(ICygnusBorrow borrowable, address borrower) external returns (uint256 liquidity, uint256 shortfall);

    /**
     *  @notice Get the lender`s full position
     *  @param borrowable The address of the borrowable contract
     *  @param lender The address of the lender
     *  @return cygUsdBalance The `lender's` balance of CygUSD
     *  @return rate The currente exchange rate
     *  @return positionInUsd The lender's position in USD
     */
    function latestLenderPosition(
        ICygnusBorrow borrowable,
        address lender
    ) external returns (uint256 cygUsdBalance, uint256 rate, uint256 positionInUsd);

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
     *  @notice Main function used in Cygnus to liquidate borrows
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidate(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external returns (uint256 amount, uint256 seizeTokens);

    /**
     *  @notice Main function used in Cygnus to liquidate borrows
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param signature The owner's signature over the permit data
     *  @return amount The amount of stablecoins repaid
     *  @return seizeTokens The amount of CygLP seized
     */
    function liquidatePermit2Allowance(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata signature
    ) external returns (uint256 amount, uint256 seizeTokens);

    /**
     *  @notice Main function used in Cygnus to liquidate borrows
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param signature The owner's signature over the permit data
     *  @return amount The amount of stablecoins repaid
     *  @return seizeTokens The amount of CygLP seized
     */
    function liquidatePermit2Signature(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata signature
    ) external returns (uint256 amount, uint256 seizeTokens);

    /**
     *  @notice Main function used in Cygnus to borrow USD
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amount Amount of USD to borrow
     *  @param recipient The address of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData Permit data for pool token
     */
    function borrow(address borrowable, uint256 amount, address recipient, uint256 deadline, bytes calldata permitData) external;

    /**
     *  @notice Main function used in Cygnus to repay borrows
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The max amount to repay
     *  @param borrower Thea ddress of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function repay(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        bytes calldata permitData
    ) external returns (uint256 amount);

    /**
     *  @notice Main function used in Cygnus to repay borrow using Permit2 Signature Transfer
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The max amount to repay
     *  @param borrower Thea ddress of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param signature The owner's signature over the permit data
     */
    function repayPermit2Allowance(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata signature
    ) external returns (uint256);

    /**
     *  @notice Main function used in Cygnus to repay borrow using Permit2 Signature Transfer
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The max amount to repay
     *  @param borrower Thea ddress of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param _permit Data signed over by the owner specifying the terms of approval
     *  @param signature The owner's signature over the permit data
     */
    function repayPermit2Signature(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata signature
    ) external returns (uint256);

    /**
     *  @notice Main function to flash liquidate borrows. Ie, liquidating a user without needing to have USD
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
     *  @param swapdata Calldata to swap
     */
    function flashLiquidate(
        address borrowable,
        address collateral,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) external returns (uint256 amount);

    /**
     *  @notice Main leverage function
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param usdAmount The amount to leverage
     *  @param lpAmountMin The minimum amount of LP Tokens to receive
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData Permit data for borrowable leverage
     *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
     *  @param swapdata the 1inch swap data to convert USD to liquidity
     */
    function leverage(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 usdAmount,
        uint256 lpAmountMin,
        uint256 deadline,
        bytes calldata permitData,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) external returns (uint256);

    /**
     *  @notice Main deleverage function
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param cygLPAmount The amount to CygLP to deleverage
     *  @param usdAmountMin The minimum amount of USD to receive
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData Permit data for collateral deleverage
     *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
     *  @param swapdata the 1inch swap data to convert liquidity to USD
     */
    function deleverage(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 cygLPAmount,
        uint256 usdAmountMin,
        uint256 deadline,
        bytes calldata permitData,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) external returns (uint256);

    //  Admin only  //

    /**
     *  @notice Initializes an extnesion of the router and maps it to a borrowable/collateral/lp token
     *  @param shuttleId the ID of the lending pool
     *  @param extension The address of the extension
     *  @custom:security only-admin
     */
    function setAltairExtension(uint256 shuttleId, address extension) external;

    /**
     *  @notice Sweeps tokens that were sent here by mistake
     *  @param tokens Array of tokens to sweep
     *  @param to The receiver of the sweep
     *  @custom:security only-admin
     */
    function sweepTokens(IERC20[] memory tokens, address to) external;

    /**
     *  @notice Sweeps native
     *  @custom:security only-admin
     */
    function sweepNative() external;
}

