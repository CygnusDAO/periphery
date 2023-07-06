// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

interface IDexRouter {
    function swapExactTokensForTokensSimple(
        uint256,
        uint256,
        address,
        address,
        bool,
        address,
        uint256
    ) external returns (uint[] memory amounts);

    struct Route {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    function quoteAddLiquidity(address, address, bool, uint256, uint256) external view returns (uint256, uint256, uint256);
}