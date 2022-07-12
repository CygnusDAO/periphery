# **Cygnus Periphery Contract**

Allows users to interact with Cygnus Core contracts to:
 - Minting CygLP and CygDAI
 - Redeeming CygLP and CygDAI
 - Borrowing DAI
 - Repaying DAI
 - Liquidating user's with DAI (pay back DAI, receive CygLP + bonus liquidation reward)
 - Leveraging LP tokens
 - Deleveraging LP Tokens
 
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

The `CygnusCollateral` contract will send an LP Token amount to the router. The router then calls the `burn` function on the DEX burning the amount of LP Token to delevereage, returning the assets from the LP Token (amountA of token0, amountB of token1). It then converts all of amountA and amountB this contract has to DAI, sending it back to the borrowable contract.

