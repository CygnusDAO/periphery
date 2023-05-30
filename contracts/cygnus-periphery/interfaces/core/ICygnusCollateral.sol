// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusCollateralVoid} from "./ICygnusCollateralVoid.sol";

/**
 *  @title ICygnusCollateral Interface for the main collateral contract which handles collateral seizes
 */
interface ICygnusCollateral is ICygnusCollateralVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the user doesn't have enough liquidity to redeem
     *
     *  @param from The address of the user attempting to redeem
     *  @param to The address to which the redeemed tokens will be sent
     *  @param value The amount of tokens to be redeemed
     *
     *  @custom:error InsufficientLiquidity
     */
    error CygnusCollateral__InsufficientLiquidity(address from, address to, uint256 value);

    /**
     *  @dev Reverts when the msg.sender of the liquidation is not this contract`s borrowable
     *
     *  @param sender The address of the message sender
     *  @param borrowable The address of the borrower
     *
     *  @custom:error MsgSenderNotBorrowable
     */
    error CygnusCollateral__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @dev Reverts when the repayAmount in a liquidation is 0
     *
     *  @custom:error CantLiquidateZero 
     */
    error CygnusCollateral__CantLiquidateZero();

    /**
     *  @dev Reverts when trying to redeem 0 tokens
     *
     *  @custom:error CantRedeemZero 
     */
    error CygnusCollateral__CantRedeemZero();

    /**
     * @dev Reverts when liquidating an account that has no shortfall
     *
     * @param liquidity The amount of liquidity in the account
     * @param shortfall The shortfall amount of the account
     *
     * @custom:error NotLiquidatable
     */
    error CygnusCollateral__NotLiquidatable(uint256 liquidity, uint256 shortfall);

    /**
     *  @dev Reverts when redeeming more than pool's totalBalance
     *
     *  @param assets The amount of assets in the pool
     *  @param totalBalance The total balance of the pool
     *
     *  @custom:error RedeemAmountInvalid
     */
    error CygnusCollateral__RedeemAmountInvalid(uint256 assets, uint256 totalBalance);

    /**
     *  @dev Reverts when redeeming more shares than CygLP in this contract
     *
     *  @param cygLPTokens The amount of CygLP tokens in this contract
     *  @param shares The amount of shares being redeemed
     *
     *  @custom:error InsufficientRedeemAmount
     */
    error CygnusCollateral__InsufficientRedeemAmount(uint256 cygLPTokens, uint256 shares);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Seizes CygLP from borrower and adds it to the liquidator's account.
     *  @notice Not marked as non-reentrant
     *
     *  @dev This should be called from `borrowable` contract, else it reverts
     *
     *  @param liquidator The address repaying the borrow and seizing the collateral
     *  @param borrower The address of the borrower
     *  @param repayAmount The number of collateral tokens to seize
     *
     *  @return cygLPAmount The amount of CygLP seized
     */
    function seizeCygLP(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 cygLPAmount);

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
    function flashRedeemAltair(address redeemer, uint256 assets, bytes calldata data) external;

    /**
     *  @notice Force the internal balance of this contract to match underlying's balanceOf
     *
     *  @custom:security non-reentrant only-eoa
     */
    function sync() external;
}
