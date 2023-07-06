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
    
        CYGNUS ALTAIR EXTENSION - `Velodrome Volatile Pools`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusAltairX} from "./interfaces/ICygnusAltairX.sol";
import {ICygnusAltairCall} from "./interfaces/ICygnusAltairCall.sol";

// Libraries
import {CygnusDexLib} from "./libraries/CygnusDexLib.sol";
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

// Aggregators
import {IAugustusSwapper} from "./interfaces/aggregators/IAugustusSwapper.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/aggregators/IAggregationRouterV5.sol";

// ---- Extension ---- //
import {IDexPair} from "./interfaces-extension/IDexPair.sol";
import {IDexRouter} from "./interfaces-extension/IDexRouter.sol";
import {IVeloFactory} from "./interfaces-extension/IVeloFactory.sol";

/**
 *  @title  CygnusAltairX Extension for Velodrome Volatile LPs
 *  @author CygnusDAO
 *  @notice Router that is used to leverage, deleverage and flash liquidate Velo positions.
 */
contract CygnusAltairXVelodrome is ICygnusAltairX, ICygnusAltairCall {
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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    string public override name;

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
    address public constant override OxPROJECT_EXCHANGE_PROXY = 0xDEF1ABE32c034e558Cdd535791643C58a13aCC10;

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

    /**
     *  @notice Empty permit for permit2 router
     */
    IAllowanceTransfer.PermitSingle public emptyPermit;

    /*  ────────────────────── Strategy  ──────────────────────  */

    /**
     *  @notice Router for the Dex swap
     */
    IDexRouter public constant DEX_ROUTER = IDexRouter(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);

    /**
     *  @notice VELO factory to get the pair fee
     */
    IVeloFactory public constant VELO_FACTORY = IVeloFactory(0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the periphery contract. Factory must be deployed on the chain first to get the addresses
     *          of deployers and the wrapped native token (WETH, WFTM, etc.)
     *  @param _hangar18 The address of the Cygnus Factory contract on this chain
     */
    constructor(IHangar18 _hangar18, string memory _name) {
        // Name
        name = string(abi.encodePacked("Cygnus: Altair Router Extension - ", _name));

        // Factory
        hangar18 = _hangar18;

        // Assign the native token set at the factory
        nativeToken = IWrappedNative(_hangar18.nativeToken());

        // Assign the USD address set at the factoryn
        usd = _hangar18.usd();
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return amount This contract's `token` balance
     */
    function _checkBalance(address token) internal view returns (uint256) {
        // Our balance of `token` (uses solady lib)
        return token.balanceOf(address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares
    ) external view override returns (address[] memory tokens, uint256[] memory amounts) {
        // Get total supply of the underlying pool
        uint256 totalSupply = IDexPair(underlying).totalSupply();

        // Get reserves from the LP
        (uint256 reserves0, uint256 reserves1, ) = IDexPair(underlying).getReserves();

        // Initialize the arrays
        tokens = new address[](2);

        // Empty amounts
        amounts = new uint256[](2);

        // Get tokens
        (, , , , , address token0, address token1) = IDexPair(underlying).metadata();

        // Token 0 from the underlying
        tokens[0] = token0;

        // Token1 from the underlying
        tokens[1] = token1;

        // Same calculation as other vault tokens, asset = shares * balance / supply

        // Amount out token0 from the LP
        amounts[0] = shares.fullMulDiv(reserves0, totalSupply);

        // Amount of token1 from the LP
        amounts[1] = shares.fullMulDiv(reserves1, totalSupply);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ───────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

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

    // AGGREGATORS

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
        if (!success) revert CygnusAltair__ParaswapTransactionFailed();

        // Return amount received - This is off by some very small amount from the actual contract balance.
        // We shouldn't use it directly. Instead, query contract balance of token received
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
    function _swapTokensOneInchV2(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(srcToken, address(ONE_INCH_ROUTER_V5), srcAmount);

        // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
        (bool success, bytes memory resultData) = ONE_INCH_ROUTER_V5.call{value: msg.value}(swapdata);

        /// @custom:error OneInchTransactionFailed
        if (!success) revert CygnusAltair__OneInchTransactionFailed();

        // Return amount received
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

    /**
     *  @dev Internal function to swap tokens using the specified aggregator.
     *  @param dexAggregator The aggregator to use for the token swap
     *  @param swapdata The encoded swap data for the aggregator.
     *  @param srcToken The source token to swap
     *  @param srcAmount The amount of source token to swap
     *  @return amountOut The amount of swapped tokens received
     */
    function _swapTokensAggregator(
        ICygnusAltair.DexAggregator dexAggregator,
        bytes memory swapdata,
        address srcToken,
        uint256 srcAmount
    ) internal returns (uint256 amountOut) {
        // Check which dex aggregator to use
        // Case 1: PARASWAP
        if (dexAggregator == ICygnusAltair.DexAggregator.PARASWAP) {
            amountOut = _swapTokensParaswap(swapdata, srcToken, srcAmount);
        }
        // Case 2: ONE INCH LEGACY
        else if (dexAggregator == ICygnusAltair.DexAggregator.ONE_INCH_LEGACY) {
            amountOut = _swapTokensOneInchV1(swapdata, srcToken, srcAmount);
        }
        // Case 3: ONE INCH V2
        else if (dexAggregator == ICygnusAltair.DexAggregator.ONE_INCH_V2) {
            amountOut = _swapTokensOneInchV2(swapdata, srcToken, srcAmount);
        }
        // Case 4: 0xPROJECT
        else if (dexAggregator == ICygnusAltair.DexAggregator.OxPROJECT) {
            amountOut = _swapTokens0xProject(swapdata, srcToken, srcAmount);
        }
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
     *  @notice Safe internal function to repay borrowed amount
     *  @param borrowable The address of the Cygnus borrow arm where the borrowed amount was taken from
     *  @param amountMax The max amount that can be repaid
     *  @param borrower The address of the account that is repaying the borrowed amount
     */
    function _maxRepayAmount(address borrowable, uint256 amountMax, address borrower) internal returns (uint256 amount) {
        // Accrue interest first to not leave debt after full repay
        ICygnusBorrow(borrowable).accrueInterest();

        // Get borrow balance of borrower
        // prettier-ignore
        (/* principal */, uint256 borrowedAmount) = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    /************************** CUSTOM ****************************/

    // Convert USD to Liquidity
    // Convert Liquidity to USD

    /**
     *  @notice Swap tokens using the dex router for the second swap
     *  @param tokenIn The address of the token we are swapping
     *  @param tokenOut The address of the token we are receiving
     *  @param amount Amount of `tokenIn` we are swapping to `tokenOut`
     *  @return Amount received of `tokenOut`
     */
    function _swapTokensDex(address tokenIn, address tokenOut, uint256 amount) internal returns (uint256) {
        // Check approve tokenIn
        _approveToken(tokenIn, address(DEX_ROUTER), amount);

        // Create route
        IDexRouter.Route[] memory route = new IDexRouter.Route[](1);

        // Swap tokenIn to tokenOut
        route[0] = IDexRouter.Route({from: tokenIn, to: tokenOut, stable: false, factory: address(VELO_FACTORY)});

        // Swap
        uint256[] memory amounts = DEX_ROUTER.swapExactTokensForTokens(amount, 0, route, address(this), block.timestamp);

        // Return amount out of tokenOut (last index)
        return amounts[amounts.length - 1];
    }

    /**
     *  @notice Function to add liquidity and mint LP Tokens
     *  @param tokenA Address of the LP Token's token0
     *  @param tokenB Address of the LP Token's token1
     *  @param amountA Amount of token A to add as liquidity
     *  @param amountB Amount of token B to add as liquidity
     *  @return liquidity The total LP Tokens minted
     */
    function _addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) internal returns (uint256 liquidity) {
        // Check tokenA approve
        _approveToken(tokenA, address(DEX_ROUTER), amountA);

        // Check tokenB approve
        _approveToken(tokenB, address(DEX_ROUTER), amountB);

        // Mint LP
        (, , liquidity) = DEX_ROUTER.addLiquidity(tokenA, tokenB, false, amountA, amountB, 0, 0, address(this), block.timestamp);
    }

    /**
     *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsd` of USD
     *  @notice Maximum 2 swaps
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     *  @param reserves0 The reserves of token0
     *  @param reserves1 The reserves of token1
     *  @return liquidity The amount of LP minted
     */
    function _convertUsdToLiquidity(
        ICygnusAltair.DexAggregator dexAggregator,
        address token0,
        address token1,
        uint256 amountUsd,
        bytes[] memory swapdata,
        uint256 reserves0,
        uint256 reserves1,
        uint256 fee
    ) internal returns (uint256 liquidity) {
        // Placeholder tokenA
        address tokenA;
        address tokenB;

        // ─────────────────────── 1. Check if token0 or token1 is already USD
        // Check if usd
        if (token0 == usd || token1 == usd) {
            // Assign USD to tokenA
            (tokenA, tokenB) = token0 == usd ? (token0, token1) : (token1, token0);
        } else {
            // ─────────────────── 2. If native is either token, then tokenA is native, else default
            // Check if native token
            if (token0 == address(nativeToken) || token1 == address(nativeToken)) {
                // If token0 is nativeToken, then assign tokenA to token0, else tokenA to token1
                (tokenA, tokenB) = token0 == address(nativeToken) ? (token0, token1) : (token1, token0);
            } else {
                // Assign tokenA to token0 and tokenB to token1 as default
                (tokenA, tokenB) = (token0, token1);
            }

            // Swap USD to tokenA using dex aggregator
            _swapTokensAggregator(dexAggregator, swapdata[0], usd, amountUsd);
        }

        // ─────────────────────── 3. Calculate optimal deposit amount for an LP Token
        // Amount A
        uint256 totalAmountA = _checkBalance(tokenA);

        // Get reserves A for calculating optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A (use maximum fee possible for VELO = 0.05%)
        uint256 swapAmount = CygnusDexLib.optimalDepositA(totalAmountA, reservesA, fee);

        // ─────────────────────── 4. Swap `optimalTokenA` amount to tokenB directly on the pair
        // Swap tokens
        uint256 totalAmountB = _swapTokensDex(tokenA, tokenB, swapAmount);

        // LP Token
        liquidity = _addLiquidity(tokenA, tokenB, totalAmountA - swapAmount, totalAmountB);
    }

    /**
     *  @notice Converts an amount of LP Token to USD. It is called after calling `burn` on a uniswapV2 pair, which
     *          receives amountTokenA of token0 and amountTokenB of token1.
     *  @notice Maximum 2 swaps
     *  @param amountTokenA The amount of token A to convert to USD
     *  @param amountTokenB The amount of token B to convert to USD
     *  @param token0 The address of token0 from the LP Token pair
     *  @param token1 The addre.s of token1 from the LP Token pair
     *  @param swapdata Bytes array consisting of 1inch API swap data
     */
    function _convertLiquidityToUsd(
        ICygnusAltair.DexAggregator dexAggregator,
        uint256 amountTokenA,
        uint256 amountTokenB,
        address token0,
        address token1,
        bytes[] memory swapdata
    ) internal returns (uint256) {
        // ─────────────────────── 1. Check if token0 or token1 is already USD
        uint256 amountA;
        uint256 amountB;

        // If token0 or token1 is USD then swap opposite
        if (token0 == usd || token1 == usd) {
            // Convert the other token to USD and return
            (amountA, amountB) = token0 == usd
                ? (amountTokenA, _swapTokensAggregator(dexAggregator, swapdata[1], token1, amountTokenB))
                : (_swapTokensAggregator(dexAggregator, swapdata[0], token0, amountTokenA), amountTokenB);

            // Explicit return
            return amountA + amountB;
        }

        // ─────────────────── 2. Not USD, swap both to USD
        // Swap token0 to USD
        amountA = _swapTokensAggregator(dexAggregator, swapdata[0], token0, amountTokenA);

        // Swap token1 to USD
        amountB = _swapTokensAggregator(dexAggregator, swapdata[1], token1, amountTokenB);

        // USD balance
        return amountA + amountB;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  LIQUIDATE ─────────────────────────────

    /**
     *  @notice Liquidates borrower internally and converts LP Tokens to receive back USD
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus Collateral
     *  @param borrowable The address of the borrowable contract
     *  @param seizeTokens The amount of CygLP seized
     *  @param swapdata The 1inch calldata to swap LP back to USD
     *  @return usdAmount The amount of USD received
     */
    function _flashLiquidate(
        address lpTokenPair,
        address collateral,
        address borrowable,
        address recipient,
        uint256 seizeTokens,
        uint256 repayAmount,
        ICygnusAltair.DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) internal returns (uint256 usdAmount) {
        // Calculate LP amount to redeem
        uint256 redeemAmount = seizeTokens.mulWad(ICygnusCollateral(collateral).exchangeRate());

        // Flash redeem the LP back to the contract
        ICygnusCollateral(collateral).flashRedeemAltair(lpTokenPair, redeemAmount, LOCAL_BYTES);

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Token0 and token1 from the LP
        (, , , , , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Convert amountA and amountB to USD
        _convertLiquidityToUsd(dexAggregator, amountAMax, amountBMax, token0, token1, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientLiquidateUsd Avoid if received is less than liquidated
        if (usdAmount < repayAmount) revert CygnusAltair__InsufficientLiquidateUsd();

        // Transfer USD to recipient
        usd.safeTransfer(recipient, usdAmount - repayAmount);

        // Transfer the repay amount of USD to borrowable
        usd.safeTransfer(borrowable, repayAmount);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
     */
    function altairLiquidate_f2x(
        address sender,
        uint256 cygLPAmount,
        uint256 repayAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltairCall) {
        // Decode data passed from borrow contract
        ICygnusAltair.AltairLiquidateCalldata memory cygnusShuttle = abi.decode(data, (ICygnusAltair.AltairLiquidateCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) revert CygnusAltair__MsgSenderNotRouter();
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (msg.sender != cygnusShuttle.borrowable) revert CygnusAltair__MsgSenderNotBorrowable();

        // Convert CygLP to USD
        _flashLiquidate(
            cygnusShuttle.lpTokenPair,
            cygnusShuttle.collateral,
            cygnusShuttle.borrowable,
            cygnusShuttle.recipient,
            cygLPAmount, // Seized amount of CygLP
            repayAmount,
            cygnusShuttle.dexAggregator,
            cygnusShuttle.swapdata
        );
    }

    //  LEVERAGE ─────────────────────────────────────

    /**
     *  @notice Mints liquidity from the DEX and deposits in the collateral, minting CygLP to the recipient
     *  @param lpTokenPair The address of the LP Token
     *  @param recipient The address of the recipient
     *  @param collateral The address of the Cygnus Collateral contract
     *  @param borrowAmount The amount of USD borrowed to conver to LP
     *  @param lpAmountMin The minimum amount of LP allowed to receive
     *  @param swapdata Swap data for aggregator
     *  @return liquidity The amount of LP minted
     */
    function _mintLPAndDeposit(
        address lpTokenPair,
        address recipient,
        address collateral,
        uint256 borrowAmount,
        uint256 lpAmountMin,
        ICygnusAltair.DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) internal returns (uint256 liquidity) {
        // Get token metadata
        (, , uint256 reserves0, uint256 reserves1, , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Fee
        uint256 fee = VELO_FACTORY.getFee(lpTokenPair, false);

        // Converts the borrowed amount of USD to tokenA and tokenB to mint the LP Token
        liquidity = _convertUsdToLiquidity(dexAggregator, token0, token1, borrowAmount, swapdata, reserves0, reserves1, fee);

        /// @custom:error InsufficientLPTokenAmount Avoid if LP Token amount received is less than min
        if (liquidity < lpAmountMin) revert CygnusAltair__InsufficientLPTokenAmount();

        // Check allowance and deposit the LP token in the collateral contract
        _approveToken(lpTokenPair, address(PERMIT2), liquidity);

        // Approve Permit
        _approvePermit2(lpTokenPair, collateral, liquidity);

        // Mint CygLP to the recipient
        ICygnusCollateral(collateral).deposit(liquidity, recipient, emptyPermit, LOCAL_BYTES);

        // Check for dust from after leverage
        _cleanDust(token0, token1, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
     */
    function altairBorrow_O9E(
        address sender,
        uint256 borrowAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltairCall) returns (uint256 liquidity) {
        // Decode data passed from borrow contract
        ICygnusAltair.AltairLeverageCalldata memory cygnusShuttle = abi.decode(data, (ICygnusAltair.AltairLeverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) revert CygnusAltair__MsgSenderNotRouter();
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (msg.sender != cygnusShuttle.borrowable) revert CygnusAltair__MsgSenderNotBorrowable();

        // Mint LP and deposit in collateral
        liquidity = _mintLPAndDeposit(
            cygnusShuttle.lpTokenPair,
            cygnusShuttle.recipient,
            cygnusShuttle.collateral,
            borrowAmount,
            cygnusShuttle.lpAmountMin,
            cygnusShuttle.dexAggregator,
            cygnusShuttle.swapdata
        );
    }

    //  DELEVERAGE ───────────────────────────────────

    /**
     *  @notice Removes liquidity from the Dex by calling the pair's `burn` function, receiving tokenA and tokenB
     *  @notice Ideally the dex would already have the LP so we can just call burn (check `deleveragePrivate()`)
     *  @param lpTokenPair The address of the LP Token
     *  @param borrower The address of the recipient
     *  @param collateral The address of the Cygnus Collateral contract
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @param redeemTokens The amount of CygLP to redeem
     *  @param usdAmountMin The minimum amount of USD allowed to receive
     *  @param swapdata Swap data for aggregator
     */
    function _removeLPAndRepay(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 redeemAmount,
        uint256 usdAmountMin,
        ICygnusAltair.DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) internal returns (uint256 usdAmount) {
        // Send back to LP
        lpTokenPair.safeTransfer(lpTokenPair, redeemAmount);

        // Burn and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Get token0 and token1
        (, , , , , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Convert tokens to USD using aggregators
        _convertLiquidityToUsd(dexAggregator, amountAMax, amountBMax, token0, token1, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        usdAmount = _checkBalance(usd);

        /// @custom:error CygnusAltair__InsufficientUSDAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) revert CygnusAltair__InsufficientUSDAmount();

        // Repay USD
        _repayAndRefund(borrowable, usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
     */
    function altairRedeem_u91A(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltairCall) returns (uint256 usdAmount) {
        // Decode deleverage shuttle data
        ICygnusAltair.AltairDeleverageCalldata memory redeemData = abi.decode(data, (ICygnusAltair.AltairDeleverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) revert CygnusAltair__MsgSenderNotRouter();
        /// @custom:error MsgSenderNotCollateral Avoid if the msg sender is not Cygnus collateral contract
        else if (msg.sender != redeemData.collateral) revert CygnusAltair__MsgSenderNotCollateral();

        // Shh
        redeemAmount;

        // Burn LP and withdraw from collateral
        usdAmount = _removeLPAndRepay(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.borrowable,
            redeemData.redeemTokens,
            redeemAmount,
            redeemData.usdAmountMin,
            redeemData.dexAggregator,
            redeemData.swapdata
        );
    }

    ////// Clean Dust ////////

    /**
     *  @notice Send dust to user who leveraged USDC into LP, if any
     *  @param token0 The address of token0 from the LP
     *  @param token1 The address of token1 from the LP
     *  @param recipient The address of the user leveraging the position
     */
    function _cleanDust(address token0, address token1, address recipient) internal {
        // Check for dust of token0
        uint256 leftAmount0 = _checkBalance(token0);

        // Check for dust of token1
        uint256 leftAmount1 = _checkBalance(token1);

        // Send leftover token0 to user
        if (leftAmount0 > 0) token0.safeTransfer(recipient, leftAmount0);

        // Send leftover token1 to user
        if (leftAmount1 > 0) token1.safeTransfer(recipient, leftAmount1);
    }

    /**
     *  @notice Updates the name of the extension
     *  @custom:security only-admin
     */
    function setName(string memory _name) external {
        // Get latest admin
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin
        if (msg.sender != admin) revert("Only admin");

        // Update name
        name = _name;
    }
}
