// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

import { IERC20 } from "./core/IERC20.sol";

/**
 *  @title Interface for making arbitrary calls during swap
 */
interface IAggregationExecutor {
    /**
     *  @notice Make calls on `msgSender` with specified data
     */
    function callBytes(address msgSender, bytes calldata data) external payable; // 0x2636f7f8
}

/**
 * @title IAggregationRouterV4 OneInch's Aggregation Router
 */
interface IAggregationRouterV4 {
    /**
     *  @custom:member srcToken The address of the token we are swapping
     *  @custom:member dstToken The address of the token we are receiving
     *  @custom:member srcReceiver The address that is swapping the tokens
     *  @custom:member dstReceiver The address that is receiving the tokens
     *  @custom:member amount Amount of `srcToken` we are swapping
     *  @custom:member minReturnAmount The min return amount of `srcToken`
     *  @custom:member flags IDK
     *  @custom:member permit Bytes for permit
     */
    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    /**
     * @notice Performs a swap, delegating all calls encoded in `data` to `caller`. See tests for usage examples
     * @param caller Aggregation executor that executes calls described in `data`
     * @param desc Swap description
     * @param data Encoded calls that `caller` should execute in between of swaps
     * @return returnAmount Resulting token amount
     * @return spentAmount Source token amount
     * @return gasLeft Gas left
     */
    function swap(
        IAggregationExecutor caller,
        SwapDescription calldata desc,
        bytes calldata data
    )
        external
        payable
        returns (
            uint256 returnAmount,
            uint256 spentAmount,
            uint256 gasLeft
        );
}
