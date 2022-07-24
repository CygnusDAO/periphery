// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

// Interface to interact with YAK adapters
interface IYakAdapter {
    /**
     *  @notice Queries amount out given an amount to swap, the token we are swapping and receiving
     *  @param _amountIn The amount of _tokenIn we want to swap
     *  @param _tokenIn The address of the token we are swapping
     *  @param _tokenOut The address of the token we are receiving
     *  @return amountOut The amount of tokenOut we are receiving
     */
    function query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) external returns (uint256 amountOut);

    /**
     *  @notice Performs a swap directly on the adapter, bypassing the yak router
     *  @param _amountIn The amount we are swapping
     *  @param _amountOut The amount we are receiving
     *  @param _fromToken The address of the token we are swapping
     *  @param _toToken The address of the token we are receiving
     *  @param _to The address of CygnusAltair
     */
    function swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address _fromToken,
        address _toToken,
        address _to
    ) external;

    struct FormattedOffer {
        uint256[] amounts;
        address[] adapters;
        address[] path;
    }

    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address[] adapters;
    }

    function findBestPath(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint256 _maxSteps
    ) external view returns (FormattedOffer memory);

    function swapNoSplit(
        Trade calldata _trade,
        address _to,
        uint256 _fee
    ) external;
}
