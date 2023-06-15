// Note that this returns the bytes array which is directly passed to the `leverage` function (see CygnusAltair.sol)
// To include and call in your script just import it:
//
// const oneInchLeverage = require(path.resolve(__dirname, "./path/leverageOneInch.js"));
//
// ...
//
// const leverageCalls = await oneInchLeverage(chainId, lpToken, nativeToken, usdc.address, router, leverageAmount)

/// @param chainId The network ID we are performing the swap on (ie Optimism = 10, Mainnet = 1)
/// @param lpToken - Contract for the LP
/// @param nativeToken - Address of the native token (ie WETH, WFTM, etc)
/// @param usdc - Address of USDC on this chain
/// @param router - Contract of the contract which is doing the call to the swapper on chain 
/// @param leverageUsdcAmount - USDC Amount being swapped to LP
module.exports = async function leverageSwapdata(chainId, lpToken, nativeToken, usdc, router, leverageUsdcAmount) {
    // Get token0 and token1 for this lp
    const token0 = await lpToken.token0();
    const token1 = await lpToken.token1();

    /**
     *  @notice 1inch swagger API call
     *  @param {Number} chainId - The id of this chain
     *  @param {String} fromToken - The address of the token we are swapping
     *  @param {String} toToken - The address of the token we are receiving
     *  @param {String} amount - The amount of `fromToken` we are swapping
     *  @param {String} router - The address of the owner of the USDC (router)
     */
    const oneInch = async (chainId, fromToken, toToken, amount, router) => {
        // 1inch Api call
        const apiUrl = `https://api.1inch.io/v5.0/${chainId}/swap?fromTokenAddress=${fromToken}&toTokenAddress=${toToken}&amount=${amount}&fromAddress=${router}&disableEstimate=true&compatibilityMode=true&slippage=0.025`;

        // Fetch from 1inch api
        const swapdata = await fetch(apiUrl).then((response) => response.json());

        // Return response replacing the selector
        return swapdata.tx.data.toString().replace("0x12aa3caf", "0x");
    };

    // 1Inch call array to pass to periphery
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
            const swapdata = await oneInch(chainId, usdc, nativeToken, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
        // Swap to token0
        else {
            // Swap USDC to token0
            const swapdata = await oneInch(chainId, usdc, token0, leverageUsdcAmount, router.address);

            // Add to call array
            calls = [...calls, swapdata];
        }
    }

    // Return bytes array to pass to periphery
    return calls;
};

