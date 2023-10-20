//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusAltairX.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  
    .         🛰️    .            .               .      🛰️     .           .                .           .
           █████████           ---======*.                                                .           ⠀
          ███░░░░░███                                               📡                🌔      🛰️                   . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .          
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀🛰️
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                       ███ ░███  ███ ░███                .                 .                 .  ⠀
     🛰️  .             ░░██████  ░░██████                 🛰️                             .                 .           
                      ░░░░░░    ░░░░░░      -------=========*             🛰️         .                     ⠀
           .                            .🛰️       .          .            .                         🛰️ .             .⠀
    
        CYGNUS PERIPHERY ROUTER EXTENSION
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusAltairX} from "./interfaces/ICygnusAltairX.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/core/IERC20.sol";
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {ICygnusAltair} from "./interfaces/ICygnusAltair.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";
import {IAllowanceTransfer} from "./interfaces/core/IAllowanceTransfer.sol";
import {ICygnusNebulaRegistry} from "./interfaces/core/ICygnusNebulaRegistry.sol"; // Oracle

// Aggregators
import {IAugustusSwapper} from "./interfaces/aggregators/IAugustusSwapper.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/aggregators/IAggregationRouterV5.sol";
import {IOpenOceanExchange, IOpenOceanCaller} from "./interfaces/aggregators/IOpenOceanExchange.sol";
import {IOkxAggregator, IOkxProxy} from "./interfaces/aggregators/IOkxAggregator.sol";

import {IUniswapV3Router} from "./interfaces/aggregators/IUniswapV3Router.sol";
import {IUniswapV3Factory} from "./interfaces/aggregators/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./interfaces/aggregators/IUniswapV3Pool.sol";

/**
 *  @title  CygnusAltairX Extension for the main periphery contract `CygnusAltair`
 *  @author CygnusDAO
 *  @notice Since the core contracts may be integrated with many different dexes, we have to rely on separate
 *          logic for each at the time of leveraging, deleveraging and flash liquidating.
 *            - Leveraging: Converts USDC to Liquidity Tokens. (ie converts USDC to ETH/Matic LP)
 *            - Deleveraging/Flash Liquidating: Converts Liquidity Tokens to USDC. (ie. converts ETH/Matic LP to USDC)
 *
 *          Since each DEX has own logic, contracts, etc. we create extensions and set them on the `CygnusAltair` router,
 *          and the fallback of each call will fall upon a certain extension with the leverage/deleverage/flash liquidate
 *          message signature (msg.sig). As such each extension MUST implement the functions:
 *            - altairBorrow_O9E - For Leverage
 *            - altairRedeem_u91A - For Deleverage
 *            - altairLiquidate_f2x - For Flash Liquidations
 *
 *          This is the base contract that holds Dex Aggregator address which all extensions must inherit from.
 */
abstract contract CygnusAltairX is ICygnusAltairX {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library SafeTransferLib For safe transfers of Erc20 tokens
     */
    using SafeTransferLib for address;

    /**
     *  @custom:library FixedPointMathLib Arithmetic library with operations for fixed-point numbers
     */
    using FixedPointMathLib for uint256;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Empty bytes to pass to contracts if needed
     */
    bytes internal constant LOCAL_BYTES = new bytes(0);

    /**
     *  @notice The address of UniswapV3's Factory contract on this chain
     */
    address internal constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    /**
     *  @notice Stored contract address to check for delegate call only
     */
    address internal immutable extensionAddress;

    /**
     *  @notice Empty allowance permit
     */
    IAllowanceTransfer.PermitSingle internal emptyPermit;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    string public constant override name = "Altair Extension: Hypervisor Pools";

    /**
     *  @inheritdoc ICygnusAltairX
     */
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override PARASWAP_AUGUSTUS_SWAPPER_V5 = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override ONE_INCH_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override OxPROJECT_EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override OPEN_OCEAN_EXCHANGE_PROXY = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override OKX_AGGREGATION_ROUTER = 0xA748D6573acA135aF68F2635BE60CB80278bd855;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override UNISWAP_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IHangar18 public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public immutable override usd;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IWrappedNative public immutable override nativeToken;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the periphery contract. Factory must be deployed on the chain first to get the addresses
     *          of deployers and the wrapped native token (WETH, WFTM, etc.)
     *  @param _hangar18 The address of the Cygnus Factory contract on this chain
     */
    constructor(IHangar18 _hangar18) {
        // Factory
        hangar18 = _hangar18;

        // Assign the native token set at the factory
        nativeToken = IWrappedNative(_hangar18.nativeToken());

        // Assign the USD address set at the factoryn
        usd = _hangar18.usd();

        // Store the contract address to restrict certain functions to delegate only
        extensionAddress = address(this);
    }

    /**
     *  @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /// @notice Allows only delegate calls.
    modifier onlyDelegateCall() {
        _checkAddress();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks address(this) to see if the call is being delegated. Reverts if it returns this contract's
     *          stored address.
     */
    function _checkAddress() internal view {
        /// @custom:error OnlyDelegateCall Avoid if the call is not a delegate call
        if (address(this) == extensionAddress) revert CygnusAltair__OnlyDelegateCall();
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return amount This contract's `token` balance
     */
    function _checkBalance(address token) internal view returns (uint256) {
        // Our balance of `token` (uses solady lib)
        return token.balanceOf(address(this));
    }

    /**
     *  @notice Convert shares to assets
     *  @param collateral Address of the CygLP
     *  @param shares Amount of CygLP redeemed
     */
    function _convertToAssets(address collateral, uint256 shares) internal view returns (uint256) {
        // CygLP Supply
        uint256 _totalSupply = ICygnusCollateral(collateral).totalSupply();

        // LP assets in collateral
        uint256 _totalAssets = ICygnusCollateral(collateral).totalAssets();

        // Return the amount of LPs we get by redeeming shares
        return shares.fullMulDiv(_totalAssets, _totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ───────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

    /**
     *  @notice Reverts with reason if the delegate call fails
     */
    function _extensionRevert(bytes memory data) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            revert(add(data, 32), mload(data))
        }
    }

    /**
     *  @notice Returns the returned data from the delegate call
     */
    function _extensionReturn(bytes memory data) internal pure {
        /// @solidity memory-safe-assembly
        assembly {
            return(add(data, 32), mload(data))
        }
    }

    // Approvals

    /**
     *  @notice Grants allowance from this contract to a dex' router (or just a contract instead of `router`)
     *  @param token The address of the token we are approving
     *  @param router The address of the dex router we are approving (or just a contract)
     *  @param amount The amount to approve
     */
    function _approveToken(address token, address router, uint256 amount) internal {
        // If allowance is already higher than `amount` return
        if (IERC20(token).allowance(address(this), router) >= amount) return;

        // Approve token
        token.safeApprove(router, type(uint256).max);
    }

    /**
     *  @notice Approves permit2 in `token` - This is used to deposit leveraged liquidity back into the CygnusCollateral
     *  @param token The address of the token we are approving the permit2 router in
     *  @param spender The address of the contract we are allowing to move our `token` (CygnusCollateral)
     *  @param amount The amount we are allowing
     */
    function _approvePermit2(address token, address spender, uint256 amount) internal {
        // Get allowance
        (uint160 allowed, , ) = IAllowanceTransfer(PERMIT2).allowance(address(this), token, spender);

        // Return without approving
        if (allowed >= amount) return;

        // We approve to the max uint160 allowed and max allowed deadline
        IAllowanceTransfer(PERMIT2).approve(token, spender, type(uint160).max, type(uint48).max);
    }

    /**
     *  @notice Safe internal function to repay borrowed amount
     *  @param borrowable The address of the Cygnus borrow arm where the borrowed amount was taken from
     *  @param amountMax The max amount that can be repaid
     *  @param borrower The address of the account that is repaying the borrowed amount
     */
    function _maxRepayAmount(address borrowable, uint256 amountMax, address borrower) internal returns (uint256 amount) {
        // Accrue interest if necessary
        ICygnusBorrow(borrowable).accrueInterest();

        // Get latest borrow balance of borrower
        (, uint256 borrowedAmount) = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    /**
     *  @param borrowable Address of the Cygnus borrow contract
     *  @param token Address of the token we are repaying (USD)
     *  @param borrower Address of the borrower who is repaying the loan
     *  @param amountMax The max available amount
     */
    function _repayAndRefund(address borrowable, address token, address borrower, uint256 amountMax) internal {
        // Repay
        uint256 amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Safe transfer USD to borrowable
        token.safeTransfer(borrowable, amount);

        // Cygnus Borrow with address(0) to update borrow balances
        ICygnusBorrow(borrowable).borrow(borrower, address(0), 0, LOCAL_BYTES);

        // Refund excess
        if (amountMax > amount) {
            uint256 refundAmount = amountMax - amount;
            // Check if token is native
            if (token == address(nativeToken)) {
                // Withdraw native
                nativeToken.withdraw(refundAmount);

                // Transfer native
                borrower.safeTransferETH(refundAmount);
            } else {
                // Transfer Token
                token.safeTransfer(borrower, refundAmount);
            }
        }
    }

    /**
     *  @notice Calculates the pool with the best fee to swap `tokenIn` to `tokenOut` given `amountIn`
     *  @param tokenIn The address of the token we are swapping
     *  @param tokenOut The address of the token we are receiving
     */
    function _optimalPoolFee(address tokenIn, address tokenOut) internal view returns (uint24 poolFee) {
        /// Get the uniswapv3 factory on this chain
        IUniswapV3Factory uniswapFactory = IUniswapV3Factory(UNISWAP_V3_FACTORY);

        // Start at 0
        uint256 maxLiquidity = 0;

        // Possible fees (0.01%, 0.05%, 0.3%, 1%)
        uint24[4] memory fees = [uint24(100), 500, 3000, 10000];

        // Get the pool given each fee. If it exists, query the current liquidity of the pool to check
        // which pool has the highest liquidity and hence which pool will most likely offer the best amountOut.
        // In reality this doesn't always result in the highest amountOut, but it will at least filter out dead
        // pools and saves us from having to use the UnsiwapV3 Quoter, which is gas inefficient should not be used on-chain:
        // https://docs.uniswap.org/contracts/v3/reference/periphery/lens/QuoterV2
        for (uint256 i = 0; i < fees.length; ) {
            // Get the pool given `fee`
            address pool = uniswapFactory.getPool(tokenIn, tokenOut, fees[i]);

            // Check if pool exists
            if (pool != address(0)) {
                // Get the liquidity for this pool
                uint256 liquidity = IUniswapV3Pool(pool).liquidity();

                // If amountOut is higher than the last maxAmount then cache the pool fee and maxamount
                if (liquidity > maxLiquidity) (poolFee, maxLiquidity) = (fees[i], liquidity);
            }

            unchecked {
                i++;
            }
        }
    }

    // Swap tokens via Paraswap

    /**
     *  @notice Creates the swap with Paraswap's Augustus Swapper. We don't update the amount, instead we clean dust at the end.
     *          This is because the data is of complex type (Path[] path). We pass the token being swapped and the amount being
     *          swapped to approve the transfer proxy (which is set on augustus wrapped via `getTokenTransferProxy`).
     *  @param swapdata The data from Paraswap's `transaction` query
     *  @param srcToken The token being swapped
     *  @param srcAmount The amount of `srcToken` being swapped
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensParaswap(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Paraswap's token proxy to approve in srcToken
        address paraswapTransferProxy = IAugustusSwapper(PARASWAP_AUGUSTUS_SWAPPER_V5).getTokenTransferProxy();

        // Approve Paraswap's transfer proxy in `srcToken` if necessary
        _approveToken(srcToken, paraswapTransferProxy, srcAmount);

        // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
        (bool success, bytes memory resultData) = PARASWAP_AUGUSTUS_SWAPPER_V5.call{value: msg.value}(swapdata);

        /// @custom:error ParaswapTransactionFailed
        if (!success) _extensionRevert(resultData);

        // Return amount received - This is off by some very small amount from the actual contract balance.
        // We shouldn't use it directly. Instead, query contract balance of token received
        /// @solidity memory-safe-assembly
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

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
    function _swapTokensOneInchV1(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi.decode(
            swapdata,
            (address, IAggregationRouterV5.SwapDescription, bytes, bytes)
        );

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != srcAmount) desc.amount = srcAmount;

        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(srcToken, ONE_INCH_ROUTER_V5, srcAmount);

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
    function _swapTokensOneInchV2(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(srcToken, ONE_INCH_ROUTER_V5, srcAmount);

        // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
        (bool success, bytes memory resultData) = ONE_INCH_ROUTER_V5.call{value: msg.value}(swapdata);

        /// @custom:error 1InchTransactionFailed
        if (!success) _extensionRevert(resultData);

        // Return amount received
        /// @solidity memory-safe-assembly
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

    // Swap tokens via 0xProject's swap API

    /**
     *  @notice Creates the swap with OxProject's swap API
     *  @param swapdata The data from 0x's swap api `quote` query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function _swapTokens0xProject(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Approve 0x Exchange Proxy Router in `srcToken` if necessary
        _approveToken(srcToken, OxPROJECT_EXCHANGE_PROXY, srcAmount);

        // Call the 0x Exchange Proxy Router with the data passed
        (bool success, bytes memory resultData) = OxPROJECT_EXCHANGE_PROXY.call{value: msg.value}(swapdata);

        /// @custom:error 0xProjectTransactionFailed
        if (!success) _extensionRevert(resultData);

        // Return amount received
        /// @solidity memory-safe-assembly
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

    // Swap tokens via OpenOcean

    /**
     *  @notice Creates the swap with OpenOcean's Aggregator API, with the `swap` method only
     *  @param swapdata The data from OpenOcean`s swap quote query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensOpenOceanV1(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Get the caller, swap description and call description from the encoded data
        (address caller, IOpenOceanExchange.SwapDescription memory desc, IOpenOceanCaller.CallDescription[] memory data) = abi.decode(
            swapdata,
            (address, IOpenOceanExchange.SwapDescription, IOpenOceanCaller.CallDescription[])
        );

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != srcAmount) desc.amount = srcAmount;

        // Approve OpenOcean Exchange Router in `srcToken` if necessary
        _approveToken(srcToken, OPEN_OCEAN_EXCHANGE_PROXY, srcAmount);

        // Swap using legacy method
        amountOut = IOpenOceanExchange(OPEN_OCEAN_EXCHANGE_PROXY).swap(IOpenOceanCaller(caller), desc, data);
    }

    /**
     *  @notice Creates the swap with OpenOcean's Aggregator API, with all methods
     *  @param swapdata The data from OpenOcean`s swap quote query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensOpenOceanV2(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Approve OpenOcean Exchange Router in `srcToken` if necessary
        _approveToken(srcToken, OPEN_OCEAN_EXCHANGE_PROXY, srcAmount);

        // Call open ocean's exchange proxy
        (bool success, bytes memory resultData) = OPEN_OCEAN_EXCHANGE_PROXY.call{value: msg.value}(swapdata);

        /// @custom:error OpenOceanTransactionFailed
        if (!success) _extensionRevert(resultData);

        // Return amount received
        /// @solidity memory-safe-assembly
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

    /**
     *  @notice Creates the swap with OKX's aggregation router
     *  @param swapdata The data from OKX`s swap quote query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensOkx(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Get the approve proxy from the router
        address okxApproveProxy = IOkxAggregator(OKX_AGGREGATION_ROUTER).approveProxy();

        // Get the token approve contract from the proxy
        address tokenApprove = IOkxProxy(okxApproveProxy).tokenApprove();

        // Approve Okx' tokenApprove contract in `srcToken`
        _approveToken(srcToken, tokenApprove, srcAmount);

        // Call the OKX router with the swap data passed to use all methods
        (bool success, bytes memory resultData) = OKX_AGGREGATION_ROUTER.call{value: msg.value}(swapdata);

        /// @custom:error OkxTransactionFailed
        if (!success) _extensionRevert(resultData);

        // Return amount received
        /// @solidity memory-safe-assembly
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

    /**
     *  @notice EMERGENCY ONLY - To be used in cases where aggregators stop working and users need to deleverage/liquidate positions.
     *  @notice Creates the swap with UniswapV3's router on this chain
     *  @param tokenIn The token we are swapping
     *  @param tokenOut The token we are receiving
     *  @param amountIn The amount of `tokenIn` we are swapping
     *  @return amountOut The amount of `tokenOut` we receive
     */
    function _swapTokensUniswapV3(address tokenIn, address tokenOut, uint256 amountIn) internal returns (uint256 amountOut) {
        /// Check allowance and approve UniswapV3 Router in token in if necessary
        _approveToken(tokenIn, UNISWAP_V3_ROUTER, amountIn);

        /// Get the optimal pool to trade `tokenIn` to `tokenOut`
        uint24 optimalPoolFee = _optimalPoolFee(tokenIn, tokenOut);

        /// @custom:error InvalidPoolFee
        if (optimalPoolFee == 0) revert CygnusAltair__InvalidPool();

        // Fee possibilities: 500, 3000, 10000
        amountOut = IUniswapV3Router(UNISWAP_V3_ROUTER).exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: optimalPoolFee,
                recipient: address(this),
                deadline: type(uint32).max,
                amountIn: amountIn,
                amountOutMinimum: 0, // No need for a minimimum amountOut since `removeLPAndRepay` does check at the end
                sqrtPriceLimitX96: 0
            })
        );
    }

    /**
     *  @dev Internal function to swap tokens using the specified aggregator.
     *  @param dexAggregator The aggregator to use for the token swap
     *  @param swapdata The encoded swap data for the aggregator.
     *  @param srcToken The source token to swap
     *  @param dstToken The token we are receiving (used only for Uniswapv3)
     *  @param srcAmount The amount of source token to swap
     *  @return amountOut The amount of swapped tokens received
     */
    function _swapTokensAggregator(
        ICygnusAltair.DexAggregator dexAggregator,
        bytes memory swapdata,
        address srcToken,
        address dstToken,
        uint256 srcAmount
    ) internal returns (uint256 amountOut) {
        // Check which dex aggregator to use
        // Case 0: PARASWAP
        if (dexAggregator == ICygnusAltair.DexAggregator.PARASWAP) {
            amountOut = _swapTokensParaswap(swapdata, srcToken, srcAmount);
        }
        // Case 1: ONE INCH LEGACY
        else if (dexAggregator == ICygnusAltair.DexAggregator.ONE_INCH_LEGACY) {
            amountOut = _swapTokensOneInchV1(swapdata, srcToken, srcAmount);
        }
        // Case 2: ONE INCH V2
        else if (dexAggregator == ICygnusAltair.DexAggregator.ONE_INCH_V2) {
            amountOut = _swapTokensOneInchV2(swapdata, srcToken, srcAmount);
        }
        // Case 3: 0xPROJECT
        else if (dexAggregator == ICygnusAltair.DexAggregator.OxPROJECT) {
            amountOut = _swapTokens0xProject(swapdata, srcToken, srcAmount);
        }
        // Case 4: OPEN OCEAN SWAP
        else if (dexAggregator == ICygnusAltair.DexAggregator.OPEN_OCEAN_LEGACY) {
            amountOut = _swapTokensOpenOceanV1(swapdata, srcToken, srcAmount);
        }
        // Case 5: OPEN OCEAN V2
        else if (dexAggregator == ICygnusAltair.DexAggregator.OPEN_OCEAN_V2) {
            amountOut = _swapTokensOpenOceanV2(swapdata, srcToken, srcAmount);
        }
        // Case 6: OKX TODO
        else if (dexAggregator == ICygnusAltair.DexAggregator.OKX) {
            amountOut = _swapTokensOkx(swapdata, srcToken, srcAmount);
        }
        // Case 7: UNISWAPV3 - This is only for EMERGENCY deleverage/liquidiations!
        else if (dexAggregator == ICygnusAltair.DexAggregator.UNISWAP_V3_EMERGENCY) {
            amountOut = _swapTokensUniswapV3(srcToken, dstToken, srcAmount);
        }
        /// @custom:error InvalidAggregator
        else revert CygnusAltair__InvalidAggregator();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     *  @custom:security only-admin
     */
    function sweepTokens(IERC20[] memory tokens, address to) external override {
        // Get latest admin
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin
        if (msg.sender != admin) revert CygnusAltair__MsgSenderNotAdmin();

        // Transfer each token to admin
        for (uint256 i = 0; i < tokens.length; i++) {
            // Balance of token
            uint256 balance = tokens[i].balanceOf(address(this));

            // Send to admin
            if (balance > 0) address(tokens[i]).safeTransfer(to, balance);
        }
    }

    /**
     *  @inheritdoc ICygnusAltairX
     *  @custom:security only-admin
     */
    function sweepNative() external override {
        // Get latest admin
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin
        if (msg.sender != admin) revert CygnusAltair__MsgSenderNotAdmin();

        // Get native balance
        uint256 balance = address(this).balance;

        // Get ETH out
        if (balance > 0) SafeTransferLib.safeTransferETH(admin, balance);
    }
}
