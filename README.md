# **Cygnus Periphery Contract**

| Update                                                         | Date         |
| -------------------------------------------------------------- | ------------ |
| Upgraded to 1inch V5 router                                    | (19/01/2023) |
| Upgraded to use Uniswap's Permit2 and allow Flash Liquidations | (30/05/2023) |
| Integrated with Paraswap's router                              | (15/06/2023) |
| Integrated with 0xProject's Swap API                           | (30/06/2023) |

This is the main periphery contract to interact with the Cygnus Core contracts.

This router is integrated with <a href="https://1inch.io">1inch</a>, <a href="https://www.paraswap.io/">Paraswap</a> and <a href="https://www.0x.org">0xProject</a> using their latest routers and it works mostly
on-chain. The queries are estimated before the first call off-chain, following the same logic for each swap as this
contract. Each proceeding call builds on top of the previous one.

During the leverage functionality the router borrows USD from the borrowable arm contract, and then
converts it to liquidity. Before the leverage or de-leverage function call,
we calculate quotes to estimate what the amount will be during each swap stage allowing users to choose the best
quote from the DEX aggregators. See the function argument `DexAggregator dexAggregator` for leverage, deleverage and flash liquidate below.


 <hr/>
 
<div style="display: flex">
  
</div>

**1Inch Integration**


  <img src="https://assets-global.website-files.com/606f63778ec431ec1b930f1f/60d10d967f7d15d8fba352a9_1inch.png" alt="1Inch">

```solidity
    // Swap tokens via 1inch legacy (aka `swap` method)

    /**
     *  @notice Creates the swap with 1Inch's AggregatorV5. We pass an extra param `updatedAmount` to eliminate
     *          any slippage from the byte data passed. When calculating the optimal deposit for single sided
     *          liquidity deposit, our calculation can be off for a few mini tokens which don't affect the
     *          data of the aggregation executor, so we pass the tx data as is but update the srcToken amount
     *  @param swapdata The data from 1inch `swap` query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function swapTokensOneInchV1Private(
        bytes memory swapdata,
        address srcToken,
        uint256 srcAmount
    ) internal returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi
            .decode(swapdata, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != srcAmount) desc.amount = srcAmount;

        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(srcToken, address(ONE_INCH_ROUTER_V5), srcAmount);

        // Swap `srcToken` to `dstToken` - Aggregator does the necessary minAmount check & we do checks at the end
        // of the leverage/deleverage functions anyways
        (amountOut, ) = IAggregationRouterV5(ONE_INCH_ROUTER_V5).swap(IAggregationExecutor(caller), desc, permit, data);
    }

    // Swap tokens via 1inch optimized routers

    /**
     *  @notice Creates the swap with 1Inch's AggregatorV5 using the router's latest paths (unoswap, uniswapv3, etc.)
     *  @param swapdata The data from 1inch `swap` query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function swapTokensOneInchV2Private(
        bytes memory swapdata,
        address srcToken,
        uint256 srcAmount
    ) internal returns (uint256 amountOut) {
        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(srcToken, address(ONE_INCH_ROUTER_V5), srcAmount);

        // Call the router constant
        (bool success, bytes memory resultData) = ONE_INCH_ROUTER_V5.call{ value: msg.value }(swapdata);

        /// @custom:error OneInchTransactionFailed
        if (!success) revert CygnusAltair__OneInchTransactionFailed();

        // Return amount received
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }
```

<hr />

**Paraswap Integration**

<img src="https://i.ytimg.com/vi/RuFCtt1Kc9Y/maxresdefault.jpg" alt="Paraswap">

```solidity
/**
 *  @notice Creates the swap with Paraswap's Augustus Swapper. We don't update the amount, instead we clean dust at the end.
 *          This is because the data is of complex type (Path[] path). We pass the token being swapped and the amount being
 *          swapped to approve the transfer proxy (which is set on augustus wrapped via `getTokenTransferProxy`).
 *  @param swapData The data from Paraswap's `transaction` query
 *  @param srcToken The token being swapped
 *  @param fromAmount The amount of `srcToken` being swapped
 *  @return amountOut The amount received of destination token
 */
function _swapTokensParaswap(
    bytes memory swapData,
    address srcToken,
    uint256 fromAmount
) private returns (uint256 amountOut) {
    // Paraswap's token proxy to approve in srcToken
    address paraswapTransferProxy = IAugustusSwapper(PARASWAP_AUGUSTUS_SWAPPER_V5).getTokenTransferProxy();

    // Approve Paraswap's transfer proxy in `srcToken` if necessary
    _approveToken(srcToken, paraswapTransferProxy, fromAmount);

    // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
    (bool success, bytes memory resultData) = PARASWAP_AUGUSTUS_SWAPPER_V5.call{ value: msg.value }(swapData);

    /// @custom:error ParaswapTransactionFailed
    if (!success) revert CygnusAltair__ParaswapTransactionFailed();

    // Return amount received - This is off by some very small amount from the actual contract balance.
    // We shouldn't use it directly. Instead, query contract balance of token received
    assembly {
        amountOut := mload(add(resultData, 32))
    }
}
```

<hr />

**0xProject Integration**

<img src="https://coincentral.com/wp-content/uploads/2018/01/0x-874x437.png" alt="zeroex">

```solidity
/**
 *  @notice Creates the swap with OxProject's swap API 
 *  @param swapdata The data from 0x's swap api `quote` query
 *  @param srcAmount The balanceOf this contract`s srcToken
 *  @return amountOut The amount received of destination token
 */
function swapTokens0xProjectPrivate(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
    // Approve 1Inch Router in `srcToken` if necessary
    _approveToken(srcToken, address(OxPROJECT_EXCHANGE_PROXY), srcAmount);

    // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
    (bool success, bytes memory resultData) = OxPROJECT_EXCHANGE_PROXY.call{value: msg.value}(swapdata);

    /// @custom:error 0xProjectTransactionFailed
    if (!success) revert CygnusAltair__0xProjectTransactionFailed();

    // Return amount received
    assembly {
        amountOut := mload(add(resultData, 32))
    }
}
```

<hr />

**Leverage**

```solidity
/**
 *  @notice Main leverage function
 *  @param lpTokenPair The address of the LP Token
 *  @param collateral The address of the collateral of the lending pool
 *  @param borrowable The address of the borrowable of the lending pool
 *  @param usdAmount The amount to leverage
 *  @param lpAmountMin The minimum amount of LP Tokens to receive
 *  @param deadline The time by which the transaction must be included to effect the change
 *  @param permitData Permit data for borrowable leverage
 *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
 *  @param swapData the 1inch swap data to convert USD to liquidity
 */
function leverage(
    address lpTokenPair,
    address collateral,
    address borrowable,
    uint256 usdAmount,
    uint256 lpAmountMin,
    uint256 deadline,
    bytes calldata permitData,
    DexAggregator dexAggregator,
    bytes[] calldata swapData
) external;
```

The `leverage` function will call The `CygnusBorrow` contract and this will send `amountUsd` back to the router of USDC. The router then converts the USDC borrowed into liquidity. It then mints the liquidity Token, sends it to the collateral contract and mints CygLP to the borrower.

<hr/>

**Deleverage**

```solidity
/**
 *  @notice Main deleverage function
 *  @param lpTokenPair The address of the LP Token
 *  @param collateral The address of the collateral of the lending pool
 *  @param borrowable The address of the borrowable of the lending pool
 *  @param cygLPAmount The amount to CygLP to deleverage
 *  @param usdAmountMin The minimum amount of USD to receive
 *  @param deadline The time by which the transaction must be included to effect the change
 *  @param permitData Permit data for collateral deleverage
 *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
 *  @param swapData the 1inch swap data to convert liquidity to USD
 */
function deleverage(
    address lpTokenPair,
    address collateral,
    address borrowable,
    uint256 cygLPAmount,
    uint256 usdAmountMin,
    uint256 deadline,
    bytes calldata permitData,
    DexAggregator dexAggregator,
    bytes[] calldata swapData
) external;
```

The `deleverage` function will call the `CygnusCollateral` contract and this will flash redeem liquidity tokens to the router. The router then burns the liquidity token (or the DEX' function to redeem the liquidity token for the assets), and receives the assets (for example amountA of token0, amountB of token1). It then converts all of amountA and amountB this contract has to USDC, repaying by sending it back to the borrowable contract and sending left over balance to the borrower.

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
 *  @notice Main function to flash liquidate borrows. Ie, liquidating a user without needing to have USD
 *  @param borrowable The address of the CygnusBorrow contract
 *  @param amountMax The maximum amount to liquidate
 *  @param borrower The address of the borrower
 *  @param recipient The address of the recipient
 *  @param deadline The time by which the transaction must be included to effect the change
 *  @param dexAggregator The dex used to sell the collateral (0 for Paraswap, 1 for 1inch)
 *  @param swapData Calldata to swap
 */
function flashLiquidate(
    address borrowable,
    address collateral,
    uint256 amountMax,
    address borrower,
    address recipient,
    uint256 deadline,
    DexAggregator dexAggregator,
    bytes[] calldata swapData
) external returns (uint256 amount);
```

This function will liquidate any borrower who has a position in shortfall without the liquidator needing to have any USDC. The caller must first build the swapData off-chain using this router's `getAssetsForShares(shares)`. The function will return an array of `tokens` and `amounts` which are the amounts of assets we would get back for burning or redeeming `shares`. We can then build the swap data easily by swapping each token amount to USD.

The function will then call the `liquidate()` function on the `CygnusBorrow` contract with the data for the swaps. The CygnusBorrow contract will seize tokens, pass the tokens seized and swapdata back to this contract and the liquidation will take place, sending back the amount repaid of usd to the borrowable and leaving the difference to the borrower (the liquidation incentive).
