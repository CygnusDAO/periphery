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

// Dependencies
import "./ICygnusAltairCall.sol";

// Interfaces
import {IERC20} from "./core/IERC20.sol";
import {IHangar18} from "./core/IHangar18.sol";

// 1Inch
import {IAggregationRouterV5} from "./IAggregationRouterV5.sol";

// Permit2
import {IAllowanceTransfer} from "./core/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "./ISignatureTransfer.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltair is ICygnusAltairCall {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the underlying is not native (WETH)
     *
     *  @param poolToken The address of the token that is not native to the network
     *
     *  @custom:error NotnativeTokenSender
     */
    error CygnusAltair__NotNativeTokenSender(address poolToken);

    /**
     *  @dev Reverts when the current block.timestamp is past deadline
     *
     *  @param deadline The timestamp after which the transaction is considered expired
     *
     *  @custom:error TransactionExpired
     */
    error CygnusAltair__TransactionExpired(uint256 deadline);

    /**
     *  @dev Reverts when the msg sender is not the router in the leverage function
     *
     *  @param sender The address of the message sender
     *  @param origin The address of the original message sender
     *
     *  @custom:error MsgSenderNotRouter
     */
    error CygnusAltair__MsgSenderNotRouter(address sender, address origin);

    /**
     *  @dev Reverts when the msg sender is not the borrow contract
     *
     *  @param sender The address of the message sender
     *  @param borrowable The address of the borrow contract
     *
     *  @custom:error MsgSenderNotBorrowable
     */
    error CygnusAltair__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @dev InvalidRedeemAmount Reverts when the redeem amount is 0 or less
     *
     *  @param redeemer The address of the user who attempted to redeem
     *  @param redeemTokens The amount of tokens the user attempted to redeem
     *
     *  @custom:error InvalidRedeemAmount
     */
    error CygnusAltair__InvalidRedeemAmount(address redeemer, uint256 redeemTokens);

    /**
     *  @dev Reverts when the msg sender is not the collateral contract
     *
     *  @param sender The address of the message sender
     *  @param collateral The address of the collateral contract
     *
     *  @custom:error MsgSenderNotCollateral
     */
    error CygnusAltair__MsgSenderNotCollateral(address sender, address collateral);

    /**
     *  @dev Reverts when the msg sender is not the cygnus factory admin
     *
     *  @param sender The address of the message sender
     *  @param admin The address of the Cygnus factory admin
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusAltair__MsgSenderNotAdmin(address sender, address admin);

    /**
     *  @dev Reverts when initializing an orbiter that doesn't exist
     *
     *  @custom:error OrbitersNotActive
     */
    error CygnusAltairY__OrbitersNotActive();

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
     *  @dev Reverts when USD amount received is less than minimum asked while liquidating
     *
     *  @custom:error InsufficientLiquidateUsd
     */
    error CygnusAltair__InsufficientLiquidateUsd();

    /**
     *  @dev Reverts when amount of USD received is less than the minimum asked
     *
     *  @custom:error InsufficientUSDAmount
     */
    error CygnusAltair__InsufficientUSDAmount();

    /**
     *  @dev Reverts when the swapped amount is less than the min requested
     *
     *  @custom:error InsufficientLPTokenAmount
     */
    error CygnusAltair__InsufficientLPTokenAmount();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Enum for choosing dex aggregators to perform leverage, deleverage and liquidations
     *  @custom:member PARASWAP Pass 0 to use Paraswap
     *  @custom:member ONE_INCH Pass 1 to use 1Inch
     */
    enum DexAggregator {
        PARASWAP,
        ONE_INCH_LEGACY,
        ONE_INCH_V2,
        OxPROJECT
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

    /**
     *  @return name The human readable name this router is for
     */
    function name() external view returns (string memory);

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
    function nativeToken() external view returns (address);

    /**
     *  @dev Retrieves the assets corresponding to a given number of shares in a MetastablePool.
     *  @param underlying The address of the underlying MetastablePool.
     *  @param shares The number of shares to calculate assets for.
     *  @return tokens An array of asset token addresses.
     *  @return amounts An array of asset token amounts.
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares
    ) external view returns (address[] memory tokens, uint256[] memory amounts);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

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
        uint256 deadline
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
    function repay(address borrowable, uint256 amountMax, address borrower, uint256 deadline) external returns (uint256 amount);

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
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
     *  @param swapdata Calldata to swap
     */
    function flashLiquidate(
        address borrowable,
        address collateral,
        uint256 amountMax,
        address borrower,
        address recipient,
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
    ) external;

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
    ) external;

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the leverage
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param borrowAmount The amount to leverage
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function altairBorrow_O9E(address sender, uint256 borrowAmount, bytes calldata data) external override(ICygnusAltairCall);

    /**
     *  @notice Function that is called by the CygnusCollateral contract and decodes data to carry out the deleverage
     *  @notice Will only succeed if: Caller is collateral contract & collateral contract was called by router
     *  @param sender Address of the contract that initialized the redeem transaction (address of the router)
     *  @param redeemAmount The amount to deleverage
     *  @param data The encoded byte data passed from the CygnusCollateral contract to the router
     */
    function altairRedeem_u91A(address sender, uint256 redeemAmount, bytes calldata data) external override(ICygnusAltairCall);

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the liquidation
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param cygLPAmount The cygLP Amount seized
     *  @param actualRepayAmount The usd amount the contract must have for the liquidate function to finish
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function altairLiquidate_f2x(
        address sender,
        uint256 cygLPAmount,
        uint256 actualRepayAmount,
        bytes calldata data
    ) external override(ICygnusAltairCall);
}
