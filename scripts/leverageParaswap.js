// Paraswap SDK
const { constructSimpleSDK } = require("@paraswap/sdk");
const axios = require("axios");

// Note that this returns the bytes array which is directly passed to the `leverage` function (see CygnusAltair.sol)
// To include and call in your script just import it:
//
// const paraswapLeverage = require(path.resolve(__dirname, "./path/leverageParaswap.js"));
//
// ...
//
// const leverageCalls = await paraswapLeverage(chainId, lpToken, nativeToken, usdc.address, router, leverageAmount)

/// @param chainId The network ID we are performing the swap on (ie Optimism = 10, Mainnet = 1)
/// @param lpToken - Contract for the LP
/// @param nativeToken - Address of the native token (ie WETH, WFTM, etc)
/// @param usdc - Address of USDC on this chain
/// @param router - Contract of the contract which is doing the call to the swapper on chain 
/// @param leverageUsdcAmount - USDC Amount being swapped to LP
module.exports = async function paraswapLeverage(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    // Construct minimal SDK with fetcher only
    const paraSwapMin = constructSimpleSDK({ chainId: chainId, axios });

    // Get token0 and token1 for this lp
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    /// @notice Paraswap API call
    /// @param {String} fromToken - The address of the token we are swapping
    /// @param {String} toToken - The address of the token we are receiving
    /// @param {String} amount - The amount of `fromToken` we are swapping
    /// @param {String} router - The address of the owner of the USDC (router)
    const paraswap = async (fromToken, toToken, amount, router) => {
        // Get the price route first from /prices/ endpoint (https://apiv5.paraswap.io/prices)
        const priceRoute = await paraSwapMin.swap.getRate({
            srcToken: fromToken,
            destToken: toToken,
            srcDecimals: 6, // This is always 6 decimals in our case
            destDecimals: 18, // Override with dest token decimals
            amount: amount,
            userAddress: router,
            side: "SELL",
        });

        // Get the tx data from /transactions/ endpoint (https://apiv5.paraswap.io/transactions/:network)
        // Network is already in route since we constructed sdk with chainId
        const swapdata = await paraSwapMin.swap.buildTx({
            srcToken: fromToken,
            destToken: toToken,
            srcAmount: amount,
            slippage: "10", // If fails then can increase, maximum of 10000 (30 == 0.3%)
            priceRoute,
            userAddress: router,
            ignoreChecks: "true",
            deadline: Math.floor(Date.now() / 1000) + 10000,
        });

        return swapdata.data;
    };

    // Paraswap call array to pass to periphery
    let calls = [];

    // Check if token0 is already usdc
    if (token0.toLowerCase() === usdc.toLowerCase() || token1.toLowerCase() === usdc.toLowerCase()) {
        // If usdc pass empty bytes
        calls = [...calls, "0x"];
    }
    // Not usdc, check for native token (ie WETH) to minimize slippage
    else {
        if (token0.toLowerCase() === nativeToken.toLowerCase() || token1.toLowerCase() === nativeToken.toLowerCase()) {
            // Swap USDC to Native
            const swapdata = await paraswap(usdc, nativeToken, leverageUsdcAmount.toString(), router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
        // Swap to token0
        else {
            // Swap USDC to token0
            const swapdata = await paraswap(usdc, token0, leverageUsdcAmount.toString(), router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};
