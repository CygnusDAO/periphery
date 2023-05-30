# **Cygnus Periphery Contract**


| Update                             | Date |
|-|-|
|Upgraded to 1inch V5 router | (19/01/2023) |
|Upgraded to use Uniswap's Permit2 and allow Flash Liquidations | (30/05/2023)|

This is the main periphery contract to interact with the Cygnus Core contracts.

This router is integrated with <a href="https://1inch.io">1inch</a> using their latest Aggregation Router V5, and it works mostly
on-chain. The queries are estimated before the first call off-chain, following the same logic for each swap as this
contract. Each proceeding call builds on top of the previous one, so we can estimate the amounts using the `returnAmount` of each API call. At the time of the swap, the router updates the amount of srcToken, in case it's off slightly, but keeps the same executioner and executioner data intact.

During the leverage functionality the router borrows USD from the borrowable arm contract, and then
converts it to liquidity tokens. Before the leverage or de-leverage function call,
we calculate quotes to estimate what the amount will be during each swap stage, and we use the data
passed from each step and override the amount with the current balance of this contract (both amounts
should be the same, or in some cases could be off by a very small amount).

 <hr/>

**1Inch Integration**

```solidity
/**
 *  @notice Creates the swap with 1Inch's AggregatorV5. We pass an extra param `updatedAmount` to eliminate
 *          any slippage from the byte data passed. When calculating the optimal deposit for single sided
 *          liquidity deposit, our calculation can be off for a few mini tokens which don't affect the
 *          data of the aggregation executor, so we pass the tx data as is but update the srcToken amount
 *  @param swapData The data from 1inch `swap` query
 *  @param updatedAmount The balanceOf this contract`s srcToken
 */
function swapTokensInch(bytes memory swapData, uint256 updatedAmount) internal virtual returns (uint256 amountOut) {
    // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
    (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi
        .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

    // Update swap amount to current balance of src token (if needed)
    if (desc.amount != updatedAmount) desc.amount = updatedAmount;

    // Approve 1Inch Router in `srcToken` if necessary
    approveContract(address(desc.srcToken), address(aggregationRouterV5), desc.amount);

    // Swap `srcToken` to `dstToken` - Aggregator does the necessary minAmount check & we do checks at the end
    // of the leverage/deleverage functions anyways
    (amountOut, ) = aggregationRouterV5.swap(IAggregationExecutor(caller), desc, permit, data);
}
```

<hr />

**Leverage**

```solidity
/**
 *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsd` of USD
 *  @notice Maximum 2 swaps
 *  @param lpTokenPair The address of the liquidity Token
 *  @param token0 The address of token0 from the liquidity Token
 *  @param token1 The address of token1 from the liquidity Token
 *  @param amountUsd The amount of USDC to convert into liquidity
 *  @param swapData Bytes array consisting of 1inch API swap data
 */
function convertUsdToLiquidity(
    address lpTokenPair,
    address token0,
    address token1,
    uint256 amountUsd,
    bytes[] memory swapData
) internal virtual returns (uint256 liquidity);
```

The `CygnusBorrow` contract will send `amountUsd` to the router. The router then converts 50% of USDC to the `CygnusBorrow`'s collateral (a liquidity token) token0 and 50% to token1. It then mints the liquidity Token, sends it to the collateral contract and mints CygLP to the borrower.

<hr/>

**Deleverage**

```solidity
/**
 *  @notice This function is called after burning or redeeming (or a similar function) a liquidity token and receiving
 *          amountTokenA of token0 and amountTokenB of token1.
 *  @notice Maximum 2 swaps
 *  @param amountTokenA The amount of token A to convert to USD
 *  @param amountTokenB The amount of token B to convert to USD
 *  @param token0 The address of token0 from the liquidity Token pair
 *  @param token1 The address of token1 from the liquidity Token pair
 *  @param swapData Bytes array consisting of 1inch API swap data
 */
function convertLiquidityToUsd(
    uint256 amountTokenA,
    uint256 amountTokenB,
    address token0,
    address token1,
    bytes[] memory swapData
) private returns (uint256);
```

The `CygnusCollateral` contract will send an amount of liquidity tokens to the router. The router then burns the liquidity token (or the DEX' function to redeem the liquidity token for the assets), and receives the assets (for example amountA of token0, amountB of token1). It then converts all of amountA and amountB this contract has to USD, sending it back to the borrowable contract.

<hr />

**Liquidate**

```solidity
/**
 *  @param borrowable The address of the Cygnus borrow contract the borrower has debt with
 *  @param amountMax The amount to liquidate
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
```

Simple `liquidate` function which sends USD from the liquidator back to the borrowable pool and calling the pool's `liquidate()` function, seizing CygLP from the borrower and sending it to the recipient. The recipient receives the equivalent amount of the USD repaid in liquidity tokens (in the form of CygLP) + the liquidation reward also in liquidity tokens.

<hr />

**Flash Liquidate**

```solidity
/**
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
```

This function will liquidate any borrower who has a position in shortfall without needing to send the USD first to the borrowable pool. The caller must first build the swapData off-chain using this router's `getAssetsForShares(shares)`. The function will return an array of `tokens` and `amounts` which are the amounts of assets we would get back for burning or redeeming `shares`. We can then build the swap data easily by swapping each token amount to USD.

The function will then call the `liquidate()` function on the `CygnusBorrow` contract with the data for the swaps. The CygnusBorrow contract will seize tokens, pass the tokens seized and swapdata back to this contract and the liquidation will take place, sending back the amount repaid of usd to the borrowable and leaving the difference to the borrower (the liquidation incentive).
