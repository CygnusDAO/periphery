// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import "./ICygnusAltairCall.sol";

// Interfaces
import { IERC20 } from "./core/IERC20.sol";
import { IAggregationRouterV5 } from "./IAggregationRouterV5.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltairX is ICygnusAltairCall {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error NotnativeTokenSender Reverts when the underlying is not Avax
     */
    error CygnusAltair__NotNativeTokenSender(address poolToken);

    /**
     *  @custom:error TransactionExpired Reverts when the current block.timestamp is past deadline
     */
    error CygnusAltair__TransactionExpired(uint256 deadline);

    /**
     *  @custom:error InsufficientBurnAmountA Reverts when the burn amount is 0 for token A
     */
    error CygnusAltair__InsufficientBurnAmountA(uint256 amount);

    /**
     *  @custom:error InsufficientBurnAmountB Reverts when the burn amount is 0 for token B
     */
    error CygnusAltair__InsufficientBurnAmountB(uint256 amount);

    /**
     *  @custom:error InsufficientRedeemAmount Reverts when amount of USD received is less than the minimum asked
     */
    error CygnusAltair__InsufficientRedeemAmount(uint256 usdAmountMin, uint256 usdAmount);

    /**
     *  @custom:error MsgSenderNotRouter Reverts when the msg sender is not the router in the leverage function
     */
    error CygnusAltair__MsgSenderNotRouter(address sender, address origin);

    /**
     *  @custom:error MsgSenderNotBorrowable Reverts when the msg sender is not the borrow contract
     */
    error CygnusAltair__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @custom:error InvalidRedeemAmount Reverts when the redeem amount is 0 or less
     */
    error CygnusAltair__InvalidRedeemAmount(address redeemer, uint256 redeemTokens);

    /**
     *  @custom:error MsgSenderNotCollateral Reverts when the msg sender is not the collateral contract
     */
    error CygnusAltair__MsgSenderNotCollateral(address sender, address collateral);

    /**
     *  @custom:error MsgSenderNotAdmin Reverts when the msg sender is not the cygnus factory admin
     */
    error CygnusAltair__MsgSenderNotAdmin(address sender, address admin);

    /**
     *  @custom:error InsufficientLPTokenAmount Reverts when the swapped amount is less than the min requested
     */
    error CygnusAltair__InsufficientLPTokenAmount(uint256 lpAmountMin, uint256 liquidity);

    /**
     *  @custom:error InsufficientLiquidateUsd Reverts when USD amount received is less than minimum asked while liq.
     */
    error CygnusAltair__InsufficientLiquidateUsd(uint256 usdAmountMin, uint256 usdAmount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return usd The address of USD on this chain
     */
    function usd() external view returns (address);

    /**
     *  @return hangar18 The address of the Cygnus factory contract V1 - Used to get the nativeToken and USD address
     *                   on this chain
     */
    function hangar18() external view returns (address);

    /**
     *  @return nativeToken The address of the native token on this chain (ie. WETH)
     */
    function nativeToken() external view returns (address);

    /**
     *  @return aggregationRouterV4 Address of the 1Inch router on this chain
     */
    function aggregationRouterV5() external view returns (IAggregationRouterV5);

    /**
     *  @return LOCAL_BYTES Empty bytes for internal calls
     */
    function LOCAL_BYTES() external view returns (bytes memory);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

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
     *  @notice Function to liquidate a borrower and immediately convert holdings to USD
     *  @param lpTokenPair The address of the LP Token that represents the CygLP we are seizing
     *  @param collateral The address of the CygnusCollateral contract
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The amount to liquidate
     *  @param amountMin The min amount of USD to receive
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidateToUsd(
        address lpTokenPair,
        address borrowable,
        address collateral,
        uint256 amountMax,
        uint256 amountMin,
        address borrower,
        address recipient,
        uint256 deadline,
        bytes[] calldata swapData
    ) external returns (uint256 amountUsd);

    /**
     *  @notice Main leverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param amountUsdDesired The amount to leverage
     *  @param amountLPMin The minimum amount of LP Tokens to receive
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param swapData the 1inch swap data to convert USD to liquidity
     *  @param permitData Permit data for borrowable leverage
     */
    function leverage(
        address collateral,
        address borrowable,
        uint256 amountUsdDesired,
        uint256 amountLPMin,
        address recipient,
        uint256 deadline,
        bytes[] calldata swapData,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Main deleverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param redeemTokens The amount to CygLP to deleverage
     *  @param usdAmountMin The minimum amount of USD to receive
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param swapData the 1inch swap data to convert liquidity to USD
     *  @param permitData Permit data for collateral deleverage
     */
    function deleverage(
        address collateral,
        address borrowable,
        uint256 redeemTokens,
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
     *  @param token0 The address of the collateral`s underlying token0
     *  @param token1 The address of the collateral`s underlying token1
     *  @param data The encoded byte data passed from the CygnusCollateral contract to the router
     */
    function altairRedeem_u91A(
        address sender,
        uint256 redeemAmount,
        address token0,
        address token1,
        bytes calldata data
    ) external override(ICygnusAltairCall);
}
