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
    
        CYGNUS ALTAIR EXTENSION - `Gyro ECLP (2 tokens)`                                                           
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
import {ICygnusAltair} from "./interfaces/ICygnusAltair.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";

import {IGyroECLPPool} from "./interfaces-extension/IGyroECLPPool.sol";
import {IVault} from "./interfaces-extension/IVault.sol";

/**
 *  @title  XGyroECLP Extension for Balancer Gyro ECLP Pools (2 tokens)
 *  @author CygnusDAO
 */
contract XGyroECLP is CygnusAltairX, ICygnusAltairCall {
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
    constructor(IHangar18 _hangar18) CygnusAltairX(_hangar18) {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Private ───────────────────────────────────────────────  */

    /**
     *  @notice Returns the weight of each asset in the LP
     *  @param lpTokenPair The address of the LP
     *  @return weight0 The weight of token0 in the LP
     *  @return weight1 The weight of token1 in the LP
     */
    function _tokenWeights(IGyroECLPPool lpTokenPair) private view returns (uint256 weight0, uint256 weight1) {
        // Get current balances
        (, uint256[] memory balances, ) = VAULT.getPoolTokens(lpTokenPair.getPoolId());

        // Token rates - All ECLP pools use a base token with 1-to-1 rate
        (uint256 rate0, uint256 rate1) = lpTokenPair.getTokenRates();

        // Calculate virtual base value
        uint256 val0 = balances[0].mulWad(rate0);
        uint256 val1 = balances[1].mulWad(rate1);

        // Weights
        weight0 = val0.divWad(val0 + val1);
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
        // Get poolId
        bytes32 poolId = IGyroECLPPool(underlying).getPoolId();

        // Get total supply of the underlying pool
        uint256 totalSupply = IGyroECLPPool(underlying).totalSupply();

        // Get pool tokens and amounts from VAULT
        (tokens, amounts, ) = VAULT.getPoolTokens(poolId);

        // Calculate the asset amounts for each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // Calculate the asset amount for the current token
            amounts[i] = shares.fullMulDiv(amounts[i], totalSupply) - difference;
        }
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
        address lpTokenPair
    ) private {
        // Get the token weights
        (uint256 weight0, uint256 weight1) = _tokenWeights(IGyroECLPPool(lpTokenPair));

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
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     *  @return liquidity The amount of LP minted
     */
    function _convertUsdToLiquidity(
        ICygnusAltair.DexAggregator dexAggregator,
        uint256 amountUsd,
        bytes[] memory swapdata,
        address lpTokenPair,
        address recipient
    ) private returns (uint256 liquidity) {
        // 1. Get pool ID and tokens to deposit in the vault
        bytes32 poolId = IGyroECLPPool(lpTokenPair).getPoolId();

        // Get pool tokens - We get balances after the swap in case aggregators swap through the pool
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // 2. Swap USDC to LP assets
        if (_isLegacy(dexAggregator)) {
            // Swap with open ocean v1 or one inch v1
            _swapTokensLegacy(dexAggregator, tokens[0], tokens[1], amountUsd, swapdata, lpTokenPair);
        }
        // Not legacy, swap with calldata
        else _swapTokensOptimized(dexAggregator, tokens[0], tokens[1], amountUsd, swapdata);

        // 3. Calculate BPT out given our balance of each token from the BPT.
        //
        // Since Gyro pools only support ALL_TOKENS_IN_FOR_BPT_OUT we need to calculate the BPT to join the pool.
        //
        // We follow the same calculation from the GyroECLP pool to calculate amountsIn given Bpt Out (rounds up):
        //
        //                              /   bptOut   \
        // amountsIn[i] = balances[i] * | ------------|
        //                              \  totalBPT  /
        //
        // We know amounts in so we do the opposite, rounding up: The min BPT of the 2 is the one that is allowed to 
        // bptOut[i] = amountIn[i] * totalBPT / balances[i]
        //
        // Get balances again after the swap
        (, uint256[] memory balances, ) = VAULT.getPoolTokens(poolId);

        // These are our amountsIn of each token
        (uint256 amount0, uint256 amount1) = (_checkBalance(tokens[0]), _checkBalance(tokens[1]));

        // Calculat BPT out given our amountsIn:
        // Total supply of BPT
        uint256 totalSupply = IGyroECLPPool(lpTokenPair).totalSupply();

        // BPT out for amountIn of token0
        uint256 bpt0 = amount0.fullMulDivUp(totalSupply, balances[0]);

        // BPT out for amountIn of token1
        uint256 bpt1 = amount1.fullMulDivUp(totalSupply, balances[1]);

        // 4. Create the Join Request and mint BPT.
        // Override array
        balances[0] = amount0;
        balances[1] = amount1;

        // Check allowance and approve both tokens if necessary
        _approveToken(tokens[0], address(VAULT), amount0);
        _approveToken(tokens[1], address(VAULT), amount1);

        // Mint requested BPT
        VAULT.joinPool(
            poolId,
            address(this),
            address(this),
            IVault.JoinPoolRequest(tokens, balances, abi.encode(3, bpt0 > bpt1 ? bpt1 - 1 : bpt0 - 1), false)
        );

        // Balance of LP
        liquidity = _checkBalance(lpTokenPair);

        // Clean dust if any
        _cleanDust(tokens[0], tokens[1], recipient);
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
            if (tokens[i] != usd) _swapTokensAggregator(dexAggregator, swapdata[i], tokens[i], usd, amounts[i]);
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

        // Pool Id
        bytes32 poolId = IGyroECLPPool(lpTokenPair).getPoolId();

        // Tokens array for this BPT
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // Min amounts
        uint256[] memory amounts = new uint256[](tokens.length);

        // Exit pool - use `EXACT_BPT_IN_FOR_TOKENS_OUT`
        VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest(tokens, amounts, abi.encode(1, redeemAmount), false)
        );

        // Update amounts array with received amounts of each token
        amounts[0] = _checkBalance(tokens[0]);
        amounts[1] = _checkBalance(tokens[1]);

        // Swap all amounts to USDC
        _convertLiquidityToUsd(dexAggregator, tokens, amounts, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientLiquidateUsd Avoid if received is less than liquidated
        if (usdAmount < repayAmount) revert CygnusAltair__InsufficientLiquidateUsd();

        // Transfer USD to recipient
        usd.safeTransfer(recipient, usdAmount - repayAmount);

        // Transfer the repay amount of USD to borrowable
        usd.safeTransfer(borrowable, repayAmount);

        // Clean dust from selling tokens to USDC
        _cleanDust(tokens[0], tokens[1], recipient);
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
        // Mint BPT
        liquidity = _convertUsdToLiquidity(dexAggregator, borrowAmount, swapdata, lpTokenPair, recipient);

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
        // Pool Id
        bytes32 poolId = IGyroECLPPool(lpTokenPair).getPoolId();

        // Create exit pool request
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);
        uint256[] memory amounts = new uint256[](tokens.length);

        // Exit pool, burn BPT and receive pool tokens - uses 'EXACT_BPT_IN_FOR_TOKENS_OUT'
        VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest(tokens, amounts, abi.encode(1, redeemAmount), false)
        );

        // Update amounts array with received amounto feach token
        amounts[0] = _checkBalance(tokens[0]);
        amounts[1] = _checkBalance(tokens[1]);

        // Swap all amounts to USDC
        usdAmount = _convertLiquidityToUsd(dexAggregator, tokens, amounts, swapdata);

        /// @custom:error CygnusAltair__InsufficientUSDAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) revert CygnusAltair__InsufficientUSDAmount();

        // Repay USD
        _repayAndRefund(ICygnusCollateral(collateral).borrowable(), usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);

        // Clean dust (if any) from redeeming BPT and receiving tokens
        _cleanDust(tokens[0], tokens[1], borrower);
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
