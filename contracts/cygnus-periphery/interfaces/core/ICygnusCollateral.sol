// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// dependencies
import { ICygnusCollateralModel } from "./ICygnusCollateralModel.sol";

/**
 *  @title ICygnusCollateral Interface for the main collateral contract which handles collateral seizes
 */
interface ICygnusCollateral is ICygnusCollateralModel {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error InsufficientLiquidity Emitted when the user doesn't have enough liquidity for a transfer.
     */
    error CygnusCollateral__InsufficientLiquidity(address from, address to, uint256 value);

    /**
     *  @custom:error LiquiditingSelf Emitted when liquidator is borrower
     */
    error CygnusCollateral__CantLiquidateSelf(address borrower, address liquidator);

    /**
     *  @custom:error MsgSenderNotCygnusDai Emitted for liquidation when msg.sender is not borrowable.
     */
    error CygnusCollateral__MsgSenderNotCygnusDai(address sender, address borrowable);

    /**
     *  @custom:error CantLiquidateZero Emitted when the repayAmount is 0
     */
    error CygnusCollateral__CantLiquidateZero();

    /**
     *  @custom:error NotLiquidatable Emitted when there is no shortfall
     */
    error CygnusCollateral__NotLiquidatable(uint256 userLiquidity, uint256 userShortfall);

    /**
     *  @custom:error CantRedeemZero Emitted when trying to redeem 0 tokens
     */
    error CygnusCollateral__CantRedeemZero();

    /**
     *  @custom:error RedeemAmountInvalid Emitted when redeeming more than pool's totalBalance
     */
    error CygnusCollateral__RedeemAmountInvalid(uint256 redeemAmount, uint256 totalBalance);

    /**
     *  @custom:error InsufficientRedeemAmount Emitted when redeeming more than user balance of redeem Tokens
     */
    error CygnusCollateral__InsufficientRedeemAmount(uint256 cygLPTokens, uint256 redeemableAmount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @param sender is address of msg.sender
     *  @param redeemer is address of redeemer
     *  @param redeemAmount is redeemed ammount
     *  @param redeemTokens is the balance of
     *  @custom:event Emitted when collateral is safely redeemed
     */
    event RedeemCollateral(address sender, address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    /**
     *  @param borrower The address of redeemer
     *  @param liquidator The address of the liquidator
     *  @param cygLPAmount The amount being seized is the balance of
     *  @param cygnusFee The protocol fee (if any)
     *  @custom:event Emitted when collateral is seized
     */
    event SeizeCollateral(address borrower, address liquidator, uint256 cygLPAmount, uint256 cygnusFee);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @param from The address of the borrower
     *  @param value The amount to redeem
     *  @return Whether the user `from` can redeem - if user has shortfall, debt must be repaid first
     */
    function canRedeem(address from, uint256 value) external returns (bool);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Updates balances of liquidator and borrower, should only be called by borrowable's liquidate function
     *  @param liquidator The address repaying the borrow and seizing the collateral
     *  @param borrower The address of the borrower
     *  @param repayAmount The number of collateral tokens to seize
     */
    function seizeCygLP(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 cygLPAmount);

    /**
     *  @dev This should be called from `Altair` contract
     *  @param redeemer The address redeeming the tokens (Altair contract)
     *  @param redeemAmount The amount of the underlying asset being redeemed
     *  @param data Calldata passed from router contract
     *  @custom:security non-reentrant
     */
    function flashRedeemAltair(
        address redeemer,
        uint256 redeemAmount,
        bytes calldata data
    ) external;
}