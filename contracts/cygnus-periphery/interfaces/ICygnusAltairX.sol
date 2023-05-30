// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

// Dependencies
import "./ICygnusAltairCall.sol";

// Interfaces
import {IERC20} from "./core/IERC20.sol";
import {IHangar18} from "./core/IHangar18.sol";
import {IDexRouter} from "./core/CollateralVoid/IDexRouter.sol";
import {IAllowanceTransfer} from "./core/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "./core/ISignatureTransfer.sol";
import {IAggregationRouterV5} from "./core/IAggregationRouterV5.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltairX is ICygnusAltairCall {
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
     *  @dev Reverts when the burn amount is 0 for token A
     *
     *  @param amount The amount of token A that is attempted to be burned
     *
     *  @custom:error InsufficientBurnAmountA
     */
    error CygnusAltair__InsufficientBurnAmountA(uint256 amount);

    /**
     *  @dev Reverts when the burn amount is 0 for token B
     *
     *  @param amount The amount of token B that is attempted to be burned
     *
     *  @custom:error InsufficientBurnAmountB
     */
    error CygnusAltair__InsufficientBurnAmountB(uint256 amount);

    /**
     *  @dev Reverts when amount of USD received is less than the minimum asked
     *
     *  @param usdAmountMin The minimum amount of USD tokens that the user expects to receive
     *  @param usdAmount The actual amount of USD tokens received
     *
     *  @custom:error InsufficientRedeemAmount
     */
    error CygnusAltair__InsufficientRedeemAmount(uint256 usdAmountMin, uint256 usdAmount);

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
     *  @dev Reverts when the swapped amount is less than the min requested
     *
     *  @param lpAmountMin The minimum amount of LP tokens requested by the user
     *  @param liquidity The actual amount of LP tokens swapped
     *
     *  @custom:error InsufficientLPTokenAmount
     */
    error CygnusAltair__InsufficientLPTokenAmount(uint256 lpAmountMin, uint256 liquidity);

    /**
     *  @dev Reverts when USD amount received is less than minimum asked while liquidating
     *
     *  @param usdAmountMin The minimum amount of USD asked for
     *  @param usdAmount The USD amount received
     *
     *  @custom:error InsufficientLiquidateUsd
     */
    error CygnusAltair__InsufficientLiquidateUsd(uint256 usdAmountMin, uint256 usdAmount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return name The human readable name this router is for
     */
    function name() external view returns (string memory);

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
     *  @return aggregationRouterV5 Address of the 1Inch V5 router on this chain
     */
    function aggregationRouterV5() external view returns (IAggregationRouterV5);

    /**
     *  @return LOCAL_BYTES Empty bytes for internal calls
     */
    function LOCAL_BYTES() external pure returns (bytes calldata);

    /**
     *  @return DEX_ROUTER The velo router
     */
    function DEX_ROUTER() external view returns (IDexRouter);

    /**
     *  @return PERMIT Uniswap's Permit2 router
     */
    function PERMIT2() external view returns (address);

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
    function borrow(
        address borrowable,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external;

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
        uint256 deadline
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
     *  @notice Main function used in Cygnus to flash liquidate borrows. Ie, liquidating wtihout the need to have USD
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param swapData Calldata to swap
     */
    function flashLiquidate(
        address borrowable,
        address collateral,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        bytes[] calldata swapData
    ) external returns (uint256 amount);

    /**
     *  @notice Main leverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param amountUsdDesired The amount to leverage
     *  @param amountLPMin The minimum amount of LP Tokens to receive
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param swapData the 1inch swap data to convert USD to liquidity
     *  @param permitData Permit data for borrowable leverage
     */
    function leverage(
        address collateral,
        address borrowable,
        uint256 amountUsdDesired,
        uint256 amountLPMin,
        uint256 deadline,
        bytes[] calldata swapData,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Main deleverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param cygLPAmount The amount to CygLP to deleverage
     *  @param usdAmountMin The minimum amount of USD to receive
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param swapData the 1inch swap data to convert liquidity to USD
     *  @param permitData Permit data for collateral deleverage
     */
    function deleverage(
        address collateral,
        address borrowable,
        uint256 cygLPAmount,
        uint256 usdAmountMin,
        uint256 deadline,
        bytes[] calldata swapData,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the leverage
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param borrowAmount The amount to leverage
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function altairBorrow_O9E(
        address sender,
        uint256 borrowAmount,
        bytes calldata data
    ) external override(ICygnusAltairCall);

    /**
     *  @notice Function that is called by the CygnusCollateral contract and decodes data to carry out the deleverage
     *  @notice Will only succeed if: Caller is collateral contract & collateral contract was called by router
     *  @param sender Address of the contract that initialized the redeem transaction (address of the router)
     *  @param redeemAmount The amount to deleverage
     *  @param data The encoded byte data passed from the CygnusCollateral contract to the router
     */
    function altairRedeem_u91A(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external override(ICygnusAltairCall);

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
