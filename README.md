# **Cygnus Periphery Contract**

Allows users to interact with Cygnus Core contracts to:

-   Minting CygLP and CygDAI
-   Redeeming CygLP and CygDAI
-   Borrowing DAI
-   Repaying DAI
-   Liquidating user's with DAI (pay back DAI, receive CygLP + bonus liquidation reward)
-   Leveraging LP tokens
-   Deleveraging LP Tokens

 <hr/>

**Leverage**

```
function convertDAIToTokens(address lpTokenPair, uint256 amountDai)
   internal
   returns (uint256 totalAmountA, uint256 totalAmountB);
```

The `CygnusBorrow` contract will send `amountDai` to the router. The router then converts 50% of DAI to the `CygnusBorrow`'s collateral (an LP Token) token0 and 50% to token1. It then mints the LP Token, sends it to the collateral contract and mints CygLP to the borrower.

<hr/>

**Deleverage**

```
function convertLPTokenToDAI(
    uint256 amountTokenA,
    uint256 amountTokenB,
    address lpTokenPair
) internal returns (uint256 amountDAI);
```

The `CygnusCollateral` contract will send an LP Token amount to the router. The router then transfers the LP Token to the liquidity pool and calls the `burn` function on the DEX, burning the amount of LP Token and returning the assets from the LP Token (amountA of token0, amountB of token1). It then converts all of amountA and amountB this contract has to DAI, sending it back to the borrowable contract.

<hr />

**Liquidate**

```
/**
 *  @param cygnusDai The address of the Cygnus borrow contract the borrower has debt with
 *  @param amountMax The amount to liquidate
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

```

The `liquidate` function will send DAI back to the borrow contract and call the `seizeDeneb` function on the collateral contract, increasing the liquidator's collateral balance (LP Token) by the liquidated amount PLUS the `liquidationIncentive` (Default is 5%) and decrease the collateral balance (LP Token) of the user being liquidated. The router first transfers `amountMax` of DAI from the liquidator to the borrow contract (it checks if amountMax is more than borrower's total borrow balance, if so, then just returns borrow balance) and then will liquidate the `borrower` address.

The liquidator has CygLP in their wallet which can be redeemed at any time for the underlying LP Token.

<hr />

**Liquidate to DAI**

```
/**
 *  @param cygnusDai The address of the Cygnus borrow contract the borrower has debt with
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
```

This works the same as above but adds another final step. After liquidating the user, the function will call `redeem` to automatically redeem the CygLP balance of the liquidator. In turn, it receives the underlying LP Token (ie AVAX/ETH LP Token) and converts the LP Token back to DAI to send everything back to the liquidator. By the end the user would have the amount they repaid PLUS the liquidation incentive back in their wallet, but all in DAI.

Example: User calls `liquidateToDai` with amountMax set as 1000 DAI. The liquidation incentive for that pool is 10%, by the end of the function call the user will have 1100 DAI back in their wallet.
