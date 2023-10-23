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
    
        CYGNUS ALTAIR EXTENSION - `Hypervisor`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusAltairX, CygnusAltairX} from "./CygnusAltairX.sol";
import {ICygnusAltairCall} from "./interfaces/ICygnusAltairCall.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/core/IERC20.sol";
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {IAlgebraPool, IHypervisor, IGammaProxy} from "./interfaces-extension/IHypervisor.sol";
import {ICygnusAltair} from "./interfaces/ICygnusAltair.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";

/**
 *  @title  XHypervisor Extension for Hypervisor pools
 *  @author CygnusDAO
 *  @notice There are 2 ways to swap tokens: `swapTokensOptimized` and `swapTokensLegacy`. Legacy methods require
 *          the actual amount of tokenIn being swapped as we need to pass this amount to the aggregator router in
 *          the function call. With optimized routers we perform a low level call so the amount of tokenIn being
 *          swapped is already encoded in the call. We do this only for leverage functions as when we deleverage
 *          we already know the amount of tokenIn we need to swap as we have done an LP burn prior to this.
 */
contract XHypervisor is CygnusAltairX, ICygnusAltairCall {
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
          3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the periphery contract. Factory must be deployed on the chain first to get the addresses
     *          of deployers and the wrapped native token (WETH, WFTM, etc.)
     *  @param _hangar18 The address of the Cygnus Factory contract on this chain
     */
    constructor(IHangar18 _hangar18) CygnusAltairX(_hangar18) {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Private ───────────────────────────────────────────────  */

    /**
     *  @notice Returns whether or not the dex aggregator will use the legacy `swap` function and thus need to calculate
     *          token weights
     *  @param dexAggregator The id of the dex aggregator to use
     *  @return Whether or not the dex aggregator is a legacy aggregator
     */
    function _isLegacy(ICygnusAltair.DexAggregator dexAggregator) private pure returns (bool) {
        // Only legacy aggregators are open ocean v1 and one inch v1
        return
            dexAggregator == ICygnusAltair.DexAggregator.OPEN_OCEAN_LEGACY ||
            dexAggregator == ICygnusAltair.DexAggregator.ONE_INCH_LEGACY ||
            dexAggregator == ICygnusAltair.DexAggregator.UNISWAP_V3_EMERGENCY;
    }

    /**
     *  @notice Returns the weight of each asset in the LP
     *  @param lpTokenPair The address of the LP
     *  @return weight0 The weight of token0 in the LP
     *  @return weight1 The weight of token1 in the LP
     */
    function _tokenWeights(
        address lpTokenPair,
        address token0,
        address token1,
        address gammaUniProxy
    ) private view returns (uint256 weight0, uint256 weight1) {
        // Get scalars of each toekn
        uint256 scalar0 = 10 ** IERC20(token0).decimals();
        uint256 scalar1 = 10 ** IERC20(token1).decimals();

        // Calculate difference in units
        uint256 scalarDifference = scalar0.divWad(scalar1);

        // Adjust for token decimals
        uint256 decimalsDenominator = scalarDifference > 1e12 ? 1e6 : 1;

        // Get sqrt price from Algebra pool
        (uint256 sqrtPriceX96, , , , , , ) = IAlgebraPool(IHypervisor(lpTokenPair).pool()).globalState();

        // Convert to price with scalar diff and denom to take into account decimals of tokens
        uint256 price = ((sqrtPriceX96 ** 2 * (scalarDifference / decimalsDenominator)) / (2 ** 192)) * decimalsDenominator;

        // How much we would need to deposit of token1 if we are depositing 1 unit of token0
        (uint256 low1, uint256 high1) = IGammaProxy(gammaUniProxy).getDepositAmount(lpTokenPair, token0, scalar0);

        // Final token1 amount
        uint256 token1Amount = ((low1 + high1) / 2).divWad(scalar1);

        // Get ratio
        uint256 ratio = token1Amount.divWad(price);

        // Return weight of token0 in the LP
        weight0 = 1e36 / (ratio + 1e18);

        // Weight of token1
        weight1 = 1e18 - weight0;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares,
        uint256 difference
    ) external view override returns (address[] memory tokens, uint256[] memory amounts) {
        // Get total supply of the underlying pool
        uint256 totalSupply = IHypervisor(underlying).totalSupply();

        // Get reserves from the LP
        (uint256 reserves0, uint256 reserves1) = IHypervisor(underlying).getTotalAmounts();

        // Initialize the arrays
        tokens = new address[](2);

        // Empty amounts
        amounts = new uint256[](2);

        // Token 0 from the underlying
        tokens[0] = IHypervisor(underlying).token0();

        // Token1 from the underlying
        tokens[1] = IHypervisor(underlying).token1();

        // Same calculation as other vault tokens, asset = shares * balance / supply

        // Amount out token0 from the LP
        amounts[0] = shares.fullMulDiv(reserves0, totalSupply) - difference;

        // Amount of token1 from the LP
        amounts[1] = shares.fullMulDiv(reserves1, totalSupply) - difference;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Private ───────────────────────────────────────────────  */

    /**
     *  @notice Swaps tokens with legacy aggregators
     *  @param dexAggregator The id of the dex aggregator to use
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     *  @param lpTokenPair The address of the LP Token
     */
    function _swapTokensLegacy(
        ICygnusAltair.DexAggregator dexAggregator,
        address token0,
        address token1,
        uint256 amountUsd,
        bytes[] memory swapdata,
        address lpTokenPair,
        address gammaUniProxy
    ) private {
        // Get the token weights
        (uint256 weight0, uint256 weight1) = _tokenWeights(lpTokenPair, token0, token1, gammaUniProxy);

        // Amount of usd to swap to token0
        uint256 token0Amount = weight0.mulWad(amountUsd);

        // Amount of usd to swap to token1
        uint256 token1Amount = weight1.mulWad(amountUsd);

        // Swap USD to tokenA with the actual token amount, since we are using a legacy method
        if (token0 != usd) _swapTokensAggregator(dexAggregator, swapdata[0], usd, token0, token0Amount);

        // Swap USD to tokenB
        if (token1 != usd) _swapTokensAggregator(dexAggregator, swapdata[1], usd, token1, token1Amount);
    }

    /**
     *  @notice Swaps tokens with legacy aggregators
     *  @param dexAggregator The id of the dex aggregator to use
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     */
    function _swapTokensOptimized(
        ICygnusAltair.DexAggregator dexAggregator,
        address token0,
        address token1,
        uint256 amountUsd,
        bytes[] memory swapdata
    ) private {
        // Swap USD to token0 using dex aggregator - amountUsd does not matter as the actual amount is encoded
        // in the swapdata, pass amountUsd to just approve the aggregator's router if needed
        if (token0 != usd) _swapTokensAggregator(dexAggregator, swapdata[0], usd, token0, amountUsd);

        // Swap USD to token1 using dex aggregator
        if (token1 != usd) _swapTokensAggregator(dexAggregator, swapdata[1], usd, token1, amountUsd);
    }

    /**
     *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsd` of USD
     *  @notice Maximum 2 swaps
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     *  @return liquidity The amount of LP minted
     */
    function _convertUsdToLiquidity(
        ICygnusAltair.DexAggregator dexAggregator,
        address token0,
        address token1,
        uint256 amountUsd,
        bytes[] memory swapdata,
        address lpTokenPair
    ) private returns (uint256 liquidity) {
        // Get the whitelsited address - the only one allowed to deposit in hypervisor
        address gammaUniProxy = IHypervisor(lpTokenPair).whitelistedAddress();

        // Check if the aggregator is a legacy aggregator (ie uses a hardcoded method such as `swap`)
        if (_isLegacy(dexAggregator)) {
            // Swap with open ocean v1 or one inch v1
            _swapTokensLegacy(dexAggregator, token0, token1, amountUsd, swapdata, lpTokenPair, gammaUniProxy);
        }
        // Not legacy, swap with calldata
        else _swapTokensOptimized(dexAggregator, token0, token1, amountUsd, swapdata);

        // Check balance of token0
        uint256 deposit0 = _checkBalance(token0);

        // Balance of token1
        uint256 deposit1 = _checkBalance(token1);

        // Approve token0 in hypervisor
        _approveToken(token0, lpTokenPair, deposit0);

        // Approve token1 in hypervisor
        _approveToken(token1, lpTokenPair, deposit1);

        // Get the minimum and maximum limit of token1 deposit given our balance of token0
        (uint256 low1, uint256 high1) = IGammaProxy(gammaUniProxy).getDepositAmount(lpTokenPair, token0, deposit0);

        // If our balance of token1 is lower than the limit, get the limit of token0
        if (deposit1 < low1) {
            // Get the high limit of token0
            (, uint256 high0) = IGammaProxy(gammaUniProxy).getDepositAmount(lpTokenPair, token1, deposit1);

            // If balance of token0 is higher than limit then deposit high limit
            if (deposit0 > high0) deposit0 = high0;
        }

        // If our balance of token1 is higher than the limit, then deposit high limit
        if (deposit1 > high1) deposit1 = high1;

        // Mint LP
        liquidity = IGammaProxy(gammaUniProxy).deposit(deposit0, deposit1, address(this), lpTokenPair, [uint256(0), 0, 0, 0]);
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
    ) private returns (uint256) {
        // ─────────────────────── 1. Check if token0 or token1 is already USD
        uint256 amountA;
        uint256 amountB;

        // If token0 or token1 is USD then swap opposite
        if (token0 == usd || token1 == usd) {
            // Convert the other token to USD and return
            (amountA, amountB) = token0 == usd
                ? (amountTokenA, _swapTokensAggregator(dexAggregator, swapdata[1], token1, usd, amountTokenB))
                : (_swapTokensAggregator(dexAggregator, swapdata[0], token0, usd, amountTokenA), amountTokenB);

            // Explicit return
            return amountA + amountB;
        }

        // ─────────────────── 2. Not USD, swap both to USD
        // Swap token0 to USD with received amount of token0 from the LP burn
        amountA = _swapTokensAggregator(dexAggregator, swapdata[0], token0, usd, amountTokenA);

        // Swap token1 to USD with received amount of token1 from the LP burn
        amountB = _swapTokensAggregator(dexAggregator, swapdata[1], token1, usd, amountTokenB);

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
        uint256 redeemAmount = _convertToAssets(collateral, seizeTokens);

        // Flash redeem the LP back to the contract
        ICygnusCollateral(collateral).flashRedeemAltair(address(this), redeemAmount, LOCAL_BYTES);

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IHypervisor(lpTokenPair).withdraw(
            redeemAmount,
            address(this),
            address(this),
            [uint256(0), 0, 0, 0]
        );

        // Token0 and token1 from the LP
        address token0 = IHypervisor(lpTokenPair).token0();
        address token1 = IHypervisor(lpTokenPair).token1();

        // Convert amountA and amountB to USD
        _convertLiquidityToUsd(dexAggregator, amountAMax, amountBMax, token0, token1, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate (paraswap..)
        usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientLiquidateUsd Avoid if received is less than liquidated
        if (usdAmount < repayAmount) revert CygnusAltair__InsufficientLiquidateUsd();

        // Transfer USD to recipient
        usd.safeTransfer(recipient, usdAmount - repayAmount);

        // Transfer the repay amount of USD to borrowable
        usd.safeTransfer(borrowable, repayAmount);

        // Clean dust from selling tokens to USDC
        _cleanDust(token0, token1, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
     *  @custom:security only-delegate
     */
    function altairLiquidate_f2x(
        address sender,
        uint256 cygLPAmount,
        uint256 repayAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltairCall) onlyDelegateCall {
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
     */
    function _mintLPAndDeposit(
        address lpTokenPair,
        address recipient,
        address collateral,
        uint256 borrowAmount,
        uint256 lpAmountMin,
        ICygnusAltair.DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) private returns (uint256 liquidity) {
        // Get tokens from the LP
        address token0 = IHypervisor(lpTokenPair).token0();
        address token1 = IHypervisor(lpTokenPair).token1();

        // Converts the borrowed amount of USD to tokenA and tokenB to mint the LP Token
        liquidity = _convertUsdToLiquidity(dexAggregator, token0, token1, borrowAmount, swapdata, lpTokenPair);

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
     *  @custom:security only-delegate
     */
    function altairBorrow_O9E(
        address sender,
        uint256 borrowAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltairCall) onlyDelegateCall returns (uint256 liquidity) {
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
     *  @param redeemTokens The amount of CygLP to redeem
     *  @param usdAmountMin The minimum amount of USD allowed to receive
     *  @param swapdata Swap data for aggregator
     */
    function _removeLPAndRepay(
        address lpTokenPair,
        address borrower,
        address collateral,
        uint256 redeemTokens,
        uint256 redeemAmount,
        uint256 usdAmountMin,
        ICygnusAltair.DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) private returns (uint256 usdAmount) {
        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IHypervisor(lpTokenPair).withdraw(
            redeemAmount,
            address(this),
            address(this),
            [uint256(0), 0, 0, 0]
        );

        // Token0 from the LP
        address token0 = IHypervisor(lpTokenPair).token0();

        // Token1 from the LP
        address token1 = IHypervisor(lpTokenPair).token1();

        // Convert amountA and amountB to USD
        _convertLiquidityToUsd(dexAggregator, amountAMax, amountBMax, token0, token1, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientRedeemAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) revert CygnusAltair__InsufficientUSDAmount();

        // Repay USD
        _repayAndRefund(ICygnusCollateral(collateral).borrowable(), usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);

        // Check for dust from after deleverage
        _cleanDust(token0, token1, borrower);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
     *  @custom:security only-delegate
     */
    function altairRedeem_u91A(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltairCall) onlyDelegateCall returns (uint256 usdAmount) {
        // Decode deleverage shuttle data
        ICygnusAltair.AltairDeleverageCalldata memory redeemData = abi.decode(data, (ICygnusAltair.AltairDeleverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) revert CygnusAltair__MsgSenderNotRouter();
        /// @custom:error MsgSenderNotCollateral Avoid if the msg sender is not Cygnus collateral contract
        else if (msg.sender != redeemData.collateral) revert CygnusAltair__MsgSenderNotCollateral();

        // Burn LP and withdraw from collateral
        usdAmount = _removeLPAndRepay(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.redeemTokens,
            redeemAmount,
            redeemData.usdAmountMin,
            redeemData.dexAggregator,
            redeemData.swapdata
        );
    }

    // Clean Dust

    
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

        // Check if either token from the LP is USDC
        if (token0 != usd && token1 != usd) {
            // Check for dust of USDC
            uint256 leftAmountUsd = _checkBalance(usd);

            // Send leftover usdc to user
            if (leftAmountUsd > 0) usd.safeTransfer(recipient, leftAmountUsd);
        }
    }
}
