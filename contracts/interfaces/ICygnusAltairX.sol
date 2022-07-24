// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Dependencies
import "./ICygnusAltairCall.sol";

// Interfaces
import { IYakAdapter } from "./IYakAdapter.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltairX is ICygnusAltairCall {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error TransactionExpired Emitted when the current block.timestamp is past deadline
     */
    error CygnusAltair__TransactionExpired(uint256);

    /**
     *  @custom:error NotnativeTokenSender Emitted when the underlying is not Avax
     */
    error CygnusAltair__NotNativeTokenSender(address poolToken);

    /**
     *  @custom:error InsufficientTokenAmount Emitted when quoting amount is <= 0
     */
    error CygnusAltair__InsufficientTokenAmount(uint256 amountTokenA);

    /**
     *  @custom:error InsufficientTokenAAmount Emitted when optimal Token A amount is less than mininum
     */
    error CygnusAltair__InsufficientTokenAAmount(uint256 amountTokenA);

    /**
     *  @custom:error InsufficientTokenBAmount Emitted when optimal Token B amount is less than mininum
     */
    error CygnusAltair__InsufficientTokenBAmount(uint256 amountTokenB);

    /**
     *  @custom:error InsufficientReserves Emitted when there are no reserves for Token A && Token B
     */
    error CygnusAltair__InsufficientReserves(uint256 reservesTokenA, uint256 reservesTokenB);

    /**
     *  @custom:error MsgSenderNotRouter Emitted when the msg sender is not the router in the leverage function
     */
    error CygnusAltair__MsgSenderNotRouter(address sender, address origin, address borrower);

    /**
     *  @custom:error MsgSenderNotBorrowable Emitted when the msg sender is not the borrow contract
     */
    error CygnusAltair__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @custom:error MsgSenderNotCollateral Emitted when the msg sender is not the collateral contract
     */
    error CygnusAltair__MsgSenderNotCollateral(address sender, address origin, address collateral);

    /**
     *  @custom:error InsufficientBurnAmountA Emitted when the burn amount is 0 for token A
     */
    error CygnusAltair__InsufficientBurnAmountA(uint256 amount);

    /**
     *  @custom:error InsufficientBurnAmountB Emitted when the burn amount is 0 for token B
     */
    error CygnusAltair__InsufficientBurnAmountB(uint256 amount);

    /**
     *  @custom:error InvalidRedeemAmount Emitted when the redeem amount is 0 or less
     */
    error CygnusAltair__InvalidRedeemAmount(address redeemer, uint256 redeemTokens);

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
     *  @return dai The address of DAI on this chain
     */
    function dai() external view returns (address);

    /**
     *  @return LOCAL_BYTES Empty bytes 0x
     */
    function LOCAL_BYTES() external view returns (bytes memory);

    /**
     *  @return joeYakAdapter The address of TraderJoe's Yak adapter
     */
    function JOE_ADAPTER() external view returns (IYakAdapter joeYakAdapter);

    /**
     *  @return pangolinYakAdapter The address of Pangolin's Yak adapter
     */
    function PANGOLIN_ADAPTER() external view returns (IYakAdapter pangolinYakAdapter);

    /**
     *  @return platypusYakAdapter The address of Platypus' Yak adapter
     */
    function PLATYPUS_ADAPTER() external view returns (IYakAdapter platypusYakAdapter);

    /**
     *  @notice Function to return collateral and borrow contract addresses for a specific LP Token in Cygnus
     *  @param lpTokenPair The address of the LP Token from DEX
     *  @return collateral The address of the Cygnus collateral for this specific LP Token
     *  @return borrowable The address of the Cygnus borrow contract for this specific LP Token
    function getShuttle(address lpTokenPair) external view returns (address collateral, address borrowable);
     */

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Creates a new position in Cygnus for any Erc20 token
     *  @param terminalToken The address of the collateral/borrow pool token that represents the minted position
     *  @param amount The amount to be minted
     *  @param recipient The account that should receive the tokens
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function mint(
        address terminalToken,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) external returns (uint256 tokens);

    /**
     *  @notice Destroys `amount` of tokens, emitting a burn event and decreasing total supply
     *  @param terminalToken The address of the collateral/borrow pool token
     *  @param tokens The Cygnus pool token
     *  @param recipient The account that should receive the tokens
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function redeem(
        address terminalToken,
        uint256 tokens,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external returns (uint256 amount);

    /**
     *  @notice Main function used in Cygnus to borrow DAI
     *  @param amount Amount of DAI to borrow
     *  @param recipient The address of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function borrow(
        address cygnusDai,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external;

    /**
     *  @notice Main function used in Cygnus to repay borrows
     *  @param amountMax The max amount to repay
     *  @param borrower Thea ddress of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function repay(
        address cygnusDai,
        uint256 amountMax,
        address borrower,
        uint256 deadline
    ) external returns (uint256 amount);

    /**
     *  @notice Main function used in Cygnus to liquidate borrows
     *  @param cygnusDai The address of Cygnus albireo
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidate(
        address cygnusDai,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount, uint256 seizeTokens);

    /**
     *  @notice Function to liquidate a borrower and immediately convert holdings to DAI
     *  @param cygnusDai The address of Cygnus albireo
     *  @param amountMax The amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidateToDai(
        address cygnusDai,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountDai);

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
     *  @notice Swap tokens function used by Leverage to turn DAI into LP Token assets
     *  @param tokenIn address of the token we are swapping
     *  @param tokenOut Address of the token we are receiving
     *  @param amount Amount of TokenIn we are swapping

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal virtual {
        // Create the path for the swap
        address[] memory path = new address[](2);

        // Path of the token we are swapping
        path[0] = address(tokenIn);

        // Path of the token we are receiving
        path[1] = address(tokenOut);

        // Safe Approve router
        AltairHelper.approveDexRouter(tokenIn, address(JOE_ROUTER), type(uint256).max);

        // Swap tokens
        JOE_ROUTER.swapExactTokensForTokens(amount, 0, path, address(this), type(uint256).max);
    }
     */
}
