# **Cygnus Periphery Contract**

Allows users to interact with Cygnus Core contracts to:

-   Minting CygLP and CygUSD
-   Redeeming CygLP and CygUSD
-   Borrowing USDC
-   Repaying USDC
-   Liquidating user's with USDC (pay back USDC, receive CygLP + bonus liquidation reward)
-   Leveraging LP tokens
-   Deleveraging LP Tokens

 <hr/>

**Leverage**

```
/**
 *  @param token0 The address of token0 from the LP Token
 *  @param token1 The address of token1 from the LP Token
 *  @param amountUsdc USDC amount to convert to token0 and token1 of an LP Token
 */
function convertUsdcToTokens(address lpTokenPair, uint256 amountUsdc)
   internal
   returns (uint256 totalAmountA, uint256 totalAmountB);
```

The `CygnusBorrow` contract will send `amountUsdc` to the router. The router then converts 50% of USDC to the `CygnusBorrow`'s collateral (an LP Token) token0 and 50% to token1. It then mints the LP Token, sends it to the collateral contract and mints CygLP to the borrower.

We pass token0 and token1 as parameters as these are used by the previous function.

<hr/>

**Deleverage**

```

/**
 *  @param amountTokenA The amount of token A to convert to USDC
 *  @param amountTokenB The amount of token B to convert to USDC
 *  @param lpTokenPair The address of the LP Token
 */
function convertLPTokenToUsdc(
    uint256 amountTokenA,
    uint256 amountTokenB,
    address lpTokenPair
) internal returns (uint256 amountUSDC);
```

The `CygnusCollateral` contract will send an LP Token amount to the router. The router then transfers the LP Token to the liquidity pool and calls the `burn` function on the DEX, burning the amount of LP Token and returning the assets from the LP Token (amountA of token0, amountB of token1). It then converts all of amountA and amountB this contract has to USDC, sending it back to the borrowable contract.

<hr />

**Liquidate**

```
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

```
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
