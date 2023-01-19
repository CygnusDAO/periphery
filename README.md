# **Cygnus Periphery Contract**

**Important: Currently updating to integrate with 1inch V5. Expect a V2 router to be added shortly.**

This is the main periphery contract to interact with the Cygnus Core contracts. 

 This router is integrated with <a href="https://1inch.io">1inch</a> using their latest Aggregation Router V4, and it works mostly
 on-chain. The queries are estimated before the first call off-chain, following the same logic for each swap as this
 contract. Each proceeding call builds on top of the previous one, so we can estimate the amounts using the `returnAmount` of each API call. At the time of the swap, the router updates the amount of srcToken, in case it's off slightly, but keeps the same executioner and executioner data intact.
 
 During the leverage functionality the router borrows USDC from the borrowable arm contract, and then
 converts it to LP Tokens. What this router does is account for every possible swap scenario between
 tokens, using a byte array populated with 1inch data. Before the leverage or de-leverage function call,
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
function swapTokens(bytes memory swapData, uint256 updatedAmount) internal virtual returns (uint256 amountOut) {
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
 *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsdc` of USDC
 *  @param lpTokenPair The address of the LP Token
 *  @param token0 The address of token0 from the LP Token
 *  @param token1 The address of token1 from the LP Token
 *  @param amountUsdc The amount of USDC to convert to liquidity
 *  @param swapData The bytes array of 1inch optimal leverage swaps
 */
function convertUsdcToLiquidity(
    address lpTokenPair,
    address token0,
    address token1,
    uint256 amountUsdc,
    bytes[] memory swapData
) internal virtual returns (uint256 totalAmountA, uint256 totalAmountB) {
```

The `CygnusBorrow` contract will send `amountUsdc` to the router. The router then converts 50% of USDC to the `CygnusBorrow`'s collateral (an LP Token) token0 and 50% to token1. It then mints the LP Token, sends it to the collateral contract and mints CygLP to the borrower.

We pass token0 and token1 as parameters as these are used by the previous function.

<hr/>

**Deleverage**

```solidity
/**
 *  @notice Converts an amount of LP Token to USDC. It is called after calling `burn` on a uniswapV2 pair, which
 *          receives amountTokenA of token0 and amountTokenB of token1.
 *  @param amountTokenA The amount of token A to convert to USDC
 *  @param amountTokenB The amount of token B to convert to USDC
 *  @param token0 The address of token0 from the LP Token pair
 *  @param token1 The address of token1 from the LP Token pair
 *  @param swapData The bytes array of 1inch optimal deleverage swaps
 */
function convertLiquidityToUsdc(
    uint256 amountTokenA,
    uint256 amountTokenB,
    address token0,
    address token1,
    bytes[] memory swapData
) internal virtual returns (uint256 amountUsdc) {
```

The Collateral contract will send an LP Token amount to the router. The router then transfers the LP Token to the liquidity pool and calls the `burn` function on the DEX, burning the amount of LP Token and returning the assets from the LP Token (amountA of token0, amountB of token1). It then converts all of amountA and amountB this contract has to USDC, sending it back to the borrowable contract.

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

The `liquidate` function will send USDC back to the borrow contract and call the `seizeDeneb` function on the collateral contract, increasing the liquidator's collateral balance (LP Token) by the liquidated amount PLUS the `liquidationIncentive` (Default is 5%) and decrease the collateral balance (LP Token) of the user being liquidated. The router first transfers `amountMax` of USDC from the liquidator to the borrow contract (it checks if amountMax is more than borrower's total borrow balance, if so, then just returns borrow balance) and then will liquidate the `borrower` address.

The liquidator has CygLP in their wallet which can be redeemed at any time for the underlying LP Token.

<hr />

**Liquidate to USDC**

```solidity
/**
 *  @param borrowable The address of the Cygnus borrow contract the borrower has debt with
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
```

This works the same as above but adds another final step. After liquidating the user, the function will call `redeem` to automatically redeem the CygLP balance of the liquidator. In turn, it receives the underlying LP Token (ie AVAX/ETH LP Token) and converts the LP Token back to USDC to send everything back to the liquidator. By the end the user would have the amount they repaid PLUS the liquidation incentive back in their wallet, but all in USDC.

Example: User calls `liquidateToUsdc` with amountMax set as 1000 USDC. The liquidation incentive for that pool is 10%, by the end of the function call the user will have 1100 USDC back in their wallet.
