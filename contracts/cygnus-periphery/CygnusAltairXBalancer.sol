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
    
        CYGNUS ALTAIR EXTENSION - `Balancer Weighted Pools`                                                           
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
import {IVault} from "./interfaces-extension/IVault.sol";
import {IWeightedPool} from "./interfaces-extension/IWeightedPool.sol";

/**
 *  @title  CygnusAltairX Extension for Balancer Weighted Pools.
 *  @author CygnusDAO
 *  @notice Router that is used to leverage, deleverage and flash liquidate Balancer positions.
 */
contract CygnusAltairX is ICygnusAltairX, ICygnusAltairCall {
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
     *  @notice Balancer VAULT
     */
    IVault public constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

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
        // Get poolId
        bytes32 poolId = IWeightedPool(underlying).getPoolId();

        // Get total supply of the underlying pool
        uint256 totalSupply = IWeightedPool(underlying).totalSupply();

        // Get pool tokens and amounts from VAULT
        (address[] memory _tokens, uint256[] memory _amounts, ) = VAULT.getPoolTokens(poolId);

        // Initialize the arrays
        tokens = new address[](_tokens.length);

        // Empty amounts
        amounts = new uint256[](_tokens.length);

        // Calculate the asset amounts for each token
        for (uint256 i = 0; i < _tokens.length; i++) {
            // Token
            tokens[i] = _tokens[i];

            // Calculate the asset amount for the current token
            amounts[i] = shares.fullMulDiv(_amounts[i], totalSupply);
        }
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

    function _convertUsdToLiquidity(
        ICygnusAltair.DexAggregator dexAggregator,
        uint256 amountUsd,
        uint256[] memory weights,
        address[] memory tokens,
        bytes[] memory swapdata
    ) internal returns (uint256[] memory) {
        // Build array for the token amounts
        uint256[] memory amounts = new uint256[](weights.length);

        // Loop through each token of the LP
        for (uint256 i = 0; i < weights.length; i++) {
            // If different than USD then swap
            if (tokens[i] != usd) {
                // Swap USD amount according to weight
                uint256 usdSwapAmount = weights[i].mulWad(amountUsd);

                // Aggregator swap
                _swapTokensAggregator(dexAggregator, swapdata[i], usd, usdSwapAmount);

                // Amounts
                amounts[i] = _checkBalance(tokens[i]);
            }
        }

        // Return amounts received of each token
        return amounts;
    }

    /**
     *  @notice Converts an amount of LP Token to USD. It is called after calling `burn` on a uniswapV2 pair, which
     *          receives amountTokenA of token0 and amountTokenB of token1.
     *  @notice Maximum 2 swaps
     *  @param dexAggregator The dex aggregator for the swap
     *  @param tokens Tokens array for the pool
     *  @param amounts The amounts array to swap to usdc of each toke
     *  @param swapdata Bytes array consisting of 1inch API swap data
     */
    function _convertLiquidityToUsd(
        ICygnusAltair.DexAggregator dexAggregator,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes[] memory swapdata
    ) internal virtual returns (uint256) {
        // At this point we have array of `tokens` and `amounts` received after redeeming the BPT
        // We swap each one to USD
        for (uint256 i = 0; i < tokens.length; i++) {
            // Check that token `i` is not USD
            if (tokens[i] != usd) _swapTokensAggregator(dexAggregator, swapdata[i], tokens[i], amounts[i]);
        }

        // USD balance
        return _checkBalance(usd);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  LIQUIDATE ─────────────────────────────

    /**
     *  @notice Liquidates borrower internally and converts LP Tokens to receive back USD
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus Collateral
     *  @param borrowable The address of the borrowable contract
     *  @param seizeTokens The amount of CygLP seized
     *  @param swapData The 1inch calldata to swap LP back to USD
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
        bytes[] memory swapData
    ) private returns (uint256 usdAmount) {
        // Calculate LP amount to redeem
        uint256 redeemAmount = seizeTokens.mulWad(ICygnusCollateral(collateral).exchangeRate());

        // Flash redeem the LP back to the contract
        ICygnusCollateral(collateral).flashRedeemAltair(lpTokenPair, redeemAmount, LOCAL_BYTES);

        // Pool Id
        bytes32 poolId = IWeightedPool(lpTokenPair).getPoolId();

        // Tokens array for this BPT
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // Min amounts
        uint256[] memory amounts = new uint256[](tokens.length);

        // Exit pool
        // defaultAbiCoder.encode(WeightedPoolExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, bptAmountIn);
        bytes memory userData = abi.encode(1, seizeTokens);

        // Exit pool
        VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest(tokens, amounts, userData, false) // tokens, amounts min, data, receive internally
        );

        // Update amounts array with received amounto feach token
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = _checkBalance(tokens[i]);
        }

        // Swap all amounts to USDC
        usdAmount = _convertLiquidityToUsd(dexAggregator, tokens, amounts, swapData);

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
     *  @notice Makes the Balancer request
     *  @param dexAggregator The dex aggregator to make the swap with
     *  @param poolId The unique pool ID for the BPT
     *  @param lpTokenPair The address of the BPT
     *  @param borrowAmount The borrowed USD amount
     *  @param swapdata The 1inch swapdata
     */
    function _makeRequest(
        ICygnusAltair.DexAggregator dexAggregator,
        bytes32 poolId,
        address lpTokenPair,
        uint256 borrowAmount,
        bytes[] memory swapdata
    ) internal {
        // 1. Tokens array for this BPT
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // 2. Get each pool token weight
        uint256[] memory weights = IWeightedPool(lpTokenPair).getNormalizedWeights();

        // 3. Convert USD to each token according to the weights
        uint256[] memory amounts = _convertUsdToLiquidity(dexAggregator, borrowAmount, weights, tokens, swapdata);

        // 4. Approve the vault to spend our tokens and update balance of USD incase one of the pool tokens is USD
        for (uint256 i = 0; i < weights.length; i++) {
            // If pool token is USD then we assign balance, since `convertUsdToLiquidity` skips usd swap and leaves 0 amount
            if (tokens[i] == usd) {
                // Update usd balance
                amounts[i] = _checkBalance(usd);
            }

            // Approve token
            _approveToken(address(tokens[i]), address(VAULT), amounts[i]);
        }

        // 4. Join pool and mint BPT
        // EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, min
        bytes memory userData = abi.encode(1, amounts, 0);

        // 3. Mint requested BPT
        VAULT.joinPool(poolId, address(this), address(this), IVault.JoinPoolRequest(tokens, amounts, userData, false));
    }

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
        // 1. Get pool tokens for this BPT
        // Pool ID to get tokens from vault
        bytes32 poolId = IWeightedPool(lpTokenPair).getPoolId();

        // 2. Make the request
        _makeRequest(dexAggregator, poolId, lpTokenPair, borrowAmount, swapdata);

        // BPT amount
        liquidity = _checkBalance(lpTokenPair);

        /// @custom:error InsufficientLPTokenAmount Avoid if LP Token amount received is less than min
        if (liquidity < lpAmountMin) revert CygnusAltair__InsufficientLPTokenAmount();

        // Check allowance and deposit the LP token in the collateral contract
        _approveToken(lpTokenPair, address(PERMIT2), liquidity);

        // Approve Permit
        _approvePermit2(lpTokenPair, collateral, liquidity);

        // Mint CygLP to the recipient
        ICygnusCollateral(collateral).deposit(liquidity, recipient, emptyPermit, LOCAL_BYTES);
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
     *  @param lpTokenPair The address of the LP Token
     *  @param borrower The address of the recipient
     *  @param collateral The address of the Cygnus Collateral contract
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @param redeemTokens The amount of CygLP to redeem
     *  @param redeemAmount The amount of LP to redeem
     *  @param swapData Swap params
     */
    function _removeLPAndRepay(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 usdAmountMin,
        uint256 redeemAmount,
        ICygnusAltair.DexAggregator dexAggregator,
        bytes[] memory swapData
    ) private returns (uint256 usdAmount) {
        // Pool Id
        bytes32 poolId = IWeightedPool(lpTokenPair).getPoolId();

        // Tokens array for this BPT
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // Min amounts
        uint256[] memory amounts = new uint256[](tokens.length);

        // Exit pool
        // defaultAbiCoder.encode(WeightedPoolExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT, bptAmountIn);
        bytes memory userData = abi.encode(1, redeemAmount);

        // Exit pool
        VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest(tokens, amounts, userData, false) // tokens, amounts min, data, receive internally
        );

        // Update amounts array with received amounto feach token
        for (uint256 i = 0; i < tokens.length; i++) {
            amounts[i] = _checkBalance(tokens[i]);
        }

        // Swap all amounts to USDC
        usdAmount = _convertLiquidityToUsd(dexAggregator, tokens, amounts, swapData);

        /// @custom:error CygnusAltair__InsufficientUSDAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) revert CygnusAltair__InsufficientUSDAmount();

        // Repay USD
        _repayAndRefund(borrowable, usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);

        // Clean dust (if any) from redeeming BPT and receiving tokens
        _cleanDust(tokens, borrower);
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
        ICygnusAltair.AltairDeleverageCalldata memory cygnusShuttle = abi.decode(data, (ICygnusAltair.AltairDeleverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) revert CygnusAltair__MsgSenderNotRouter();
        /// @custom:error MsgSenderNotCollateral Avoid if the msg sender is not Cygnus collateral contract
        else if (msg.sender != cygnusShuttle.collateral) revert CygnusAltair__MsgSenderNotCollateral();

        // Burn LP and withdraw from collateral
        usdAmount = _removeLPAndRepay(
            cygnusShuttle.lpTokenPair,
            cygnusShuttle.recipient,
            cygnusShuttle.collateral,
            cygnusShuttle.borrowable,
            cygnusShuttle.redeemTokens,
            redeemAmount,
            cygnusShuttle.usdAmountMin,
            cygnusShuttle.dexAggregator,
            cygnusShuttle.swapdata
        );
    }

    ////// Clean Dust ////////

    /**
     *  @notice Send dust to user who leveraged USDC into LP, if any
     *  @param _tokens Tokens to check for dust
     *  @param recipient The address of the user leveraging the position
     */
    function _cleanDust(address[] memory _tokens, address recipient) private {
        // Each token in the LP
        for (uint256 i = 0; i < _tokens.length; i++) {
            // Check for dust for token i
            uint256 leftAmount = _checkBalance(_tokens[i]);

            // Send dust to user
            if (leftAmount > 0) _tokens[i].safeTransfer(recipient, leftAmount);
        }

        // Check for dust for token i
        uint256 leftAmountUsd = _checkBalance(usd);

        // Send dust to user
        if (leftAmountUsd > 0) usd.safeTransfer(recipient, leftAmountUsd);
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
