// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowVoid} from "./ICygnusBorrowVoid.sol";
import {ICygnusTerminal} from "./ICygnusTerminal.sol";

/**
 *  @title ICygnusBorrow Interface for the main Borrow contract which handles borrows/liquidations
 */
interface ICygnusBorrow is ICygnusBorrowVoid {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the borrow amount is higher than total balance
     *
     *  @param borrowAmount The amount being borrowed
     *  @param balance The total balance of the pool
     *
     *  @custom:error BorrowExceedsTotalBalance
     */
    error CygnusBorrow__BorrowExceedsTotalBalance(uint256 borrowAmount, uint256 balance);

    /**
     *  @dev Reverts if the borrower has insufficient liquidity for this borrow
     *
     *  @param collateral The address of the collateral token
     *  @param borrower The address of the borrower
     *
     *  @custom:error InsufficientLiquidity
     */
    error CygnusBorrow__InsufficientLiquidity(address collateral, address borrower);

    /**
     *  @dev Reverts if borrowAmount and repayAmount are both non-zero
     *
     *  @param borrowAmount The amount being borrowed
     *  @param repayAmount The amount being repaid
     *
     *  @custom:error BorrowAndRepayOverload
     */
    error CygnusBorrow__BorrowRepayOverload(uint256 borrowAmount, uint256 repayAmount);

    /**
     *  @dev Reverts if usd received is less than repaid after liquidating
     *
     *  @param received The amount of USD received after liquidation
     *  @param repaid The amount of USD repaid during liquidation
     *
     *  @custom:error InsufficientUsdReceived
     */
    error CygnusBorrow__InsufficientUsdReceived(uint256 received, uint256 repaid);

    /**
     *  @dev Reverts if liquidating 0 USD
     *
     *  @param repayAmount The amount being repaid
     *
     *  @custom:error CantRepayZero Reverts if liquidating 0 USD
     */
    error CygnusBorrow__CantRepayZero(uint256 repayAmount);

    /**
     *  @dev Reverts if repay is more than total borrows
     *
     *  @param repayAmount The amount being repaid
     *
     *  @custom:error InvalidRepayAmount
     */
    error CygnusBorrow__InvalidRepayAmount(uint256 repayAmount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a liquidator repays and seizes collateral
     *
     *  @param sender Indexed address of msg.sender (should be `Altair` address)
     *  @param borrower Indexed address of the borrower
     *  @param receiver Indexed address of receiver
     *  @param repayAmount The amount of USD repaid
     *  @param cygLPAmount The amount of CygLP seized
     *  @param usdAmount The total amount of underlying deposited
     *
     *  @custom:event Liquidate
     */
    event Liquidate(
        address indexed sender,
        address indexed borrower,
        address receiver,
        uint256 repayAmount,
        uint256 cygLPAmount,
        uint256 usdAmount
    );

    /**
     *  @dev Logs when a borrower takes out a loan
     *
     *  @param sender Indexed address of msg.sender (should be `Altair` address)
     *  @param borrower Indexed address of the borrower
     *  @param receiver Indexed address of receiver
     *  @param borrowAmount The amount of USD borrowed
     *  @param repayAmount The amount of USD repaid
     *
     *  @custom:event Borrow
     */
    event Borrow(
        address indexed sender,
        address indexed borrower,
        address receiver,
        uint256 borrowAmount,
        uint256 repayAmount
    );

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Overrides the exchange rate of `CygnusTerminal` for borrow contracts to mint reserves
     */
    function exchangeRate() external override(ICygnusTerminal) returns (uint256);

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *
     *  @param borrower The address of the borrower being liquidated
     *  @param receiver The address of the receiver of the collateral
     *  @param repayAmount USD amount covering the loan
     *  @param data Calltype data passed to Router contract.
     *  @return usdAmount The amount of USD deposited after taking into account liq. incentive
     *
     *  @custom:security non-reentrant
     */
    function liquidate(
        address borrower,
        address receiver,
        uint256 repayAmount,
        bytes calldata data
    ) external returns (uint256 usdAmount);

    /**
     *  @notice This low level function should only be called from `CygnusAltair` contract only
     *
     *  @param borrower The address of the Borrow contract.
     *  @param receiver The address of the receiver of the borrow amount.
     *  @param borrowAmount The amount of the underlying asset to borrow.
     *  @param data Calltype data passed to Router contract.
     *
     *  @custom:security non-reentrant
     */
    function borrow(address borrower, address receiver, uint256 borrowAmount, bytes calldata data) external;

    /**
     *  @notice Syncs internal balance with totalBalance
     *
     *  @custom:security non-reentrant only-eoa
     */
    function sync() external;
}
