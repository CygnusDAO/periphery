// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import "./ICygnusAltairCall.sol";

// Interfaces
import { IYakAdapter } from "./IYakAdapter.sol";
import { IDexRouter02 } from "./core/IDexRouter.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltairX is ICygnusAltairCall {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error NotnativeTokenSender Emitted when the underlying is not Avax
     */
    error CygnusAltair__NotNativeTokenSender(address poolToken);

    /**
     *  @custom:error TransactionExpired Emitted when the current block.timestamp is past deadline
     */
    error CygnusAltair__TransactionExpired(uint256);

    /**
     *  @custom:error InsufficientBurnAmountA Emitted when the burn amount is 0 for token A
     */
    error CygnusAltair__InsufficientBurnAmountA(uint256 amount);

    /**
     *  @custom:error InsufficientBurnAmountB Emitted when the burn amount is 0 for token B
     */
    error CygnusAltair__InsufficientBurnAmountB(uint256 amount);

    /**
     *  @custom:error MsgSenderNotRouter Emitted when the msg sender is not the router in the leverage function
     */
    error CygnusAltair__MsgSenderNotRouter(address sender, address origin, address borrower);

    /**
     *  @custom:error MsgSenderNotBorrowable Emitted when the msg sender is not the borrow contract
     */
    error CygnusAltair__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @custom:error InvalidRedeemAmount Emitted when the redeem amount is 0 or less
     */
    error CygnusAltair__InvalidRedeemAmount(address redeemer, uint256 redeemTokens);

    /**
     *  @custom:error MsgSenderNotCollateral Emitted when the msg sender is not the collateral contract
     */
    error CygnusAltair__MsgSenderNotCollateral(address sender, address collateral);

    /**
     *  @custom:error MsgSenderNotAdmin Emitted when the msg sender is not the cygnus factory admin
     */
    error CygnusAltair__MsgSenderNotAdmin(address sender, address admin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return hangar18 The address of the Cygnus factory contract V1
     */
    function hangar18() external view returns (address);

    /**
     *  @return nativeToken The address of wrapped Avax
     */
    function nativeToken() external view returns (address);

    /**
     *  @return usdc The address of USDC on this chain
     */
    function usdc() external view returns (address);

    /**
     *  @return LOCAL_BYTES Empty bytes 0x
     */
    function LOCAL_BYTES() external view returns (bytes memory);

    /**
     *  @return YAK_ROUTER The address of Yak's dex aggregator
     */
    function YAK_ROUTER() external pure returns (IYakAdapter);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Main function used in Cygnus to borrow USDC
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amount Amount of USDC to borrow
     *  @param recipient The address of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function borrow(
        address borrowable,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes memory permitData
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
     *  @notice Function to liquidate a borrower and immediately convert holdings to USDC
     *  @param borrowable The address of the CygnusBorrow contract
     *  @param amountMax The amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidateToUsdc(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountUsdc);

    /**
     *  @notice Main leverage function
     *  @param collateral The address of the Cygnus collateral
     *  @param amount The amount to leverage
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function leverage(
        address collateral,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Main deleverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param redeemTokens The amount to CygLP to deleverage
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function deleverage(
        address collateral,
        uint256 redeemTokens,
        uint256 deadline,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the leverage
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param borrower Address of the borrower that is leveraging
     *  @param borrowAmount The amount to leverage
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function altairBorrow_O9E(
        address sender,
        address borrower,
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
        address token0,
        address token1,
        bytes calldata data
    ) external override(ICygnusAltairCall);
}
