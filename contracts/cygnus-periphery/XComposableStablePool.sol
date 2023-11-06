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
    
        CYGNUS ALTAIR EXTENSION - `Composable Stable Pools`
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

// Strategy
import {IComposableStablePool} from "./interfaces-extension/IComposableStablePool.sol";
import {IVault} from "./interfaces-extension/IVault.sol";

/**
 *  @title  XComposableStablePool Extension for Balancer/BeethovenX Composable Stable Pools
 *  @author CygnusDAO
 *  @notice Periphery router used to interact with Cygnus core pools using Balancer Composable Stable pools as collateral.
 */
contract XComposableStablePool is CygnusAltairX, ICygnusAltairCall {
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

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares,
        uint256 difference
    ) external view override returns (address[] memory tokens, uint256[] memory amounts) {
        // Pool ID
        bytes32 poolId = IComposableStablePool(underlying).getPoolId();

        // Get the pool tokens including the pre-minted BPT
        (address[] memory poolTokens, uint256[] memory balances, ) = VAULT.getPoolTokens(poolId);

        // From Balancer's ComposableStorage
        /**********************************************************************************************
        // exactBPTInForTokensOut                                                                    //
        // (per token)                                                                               //
        // aO = tokenAmountOut             /        bptIn         \                                  //
        // b = tokenBalance      a0 = b * | ---------------------  |                                 //
        // bptIn = bptAmountIn             \     bptTotalSupply    /                                 //
        // bpt = bptTotalSupply                                                                      //
        **********************************************************************************************/

        // BPT Index
        uint256 bptIndex = IComposableStablePool(underlying).getBptIndex();

        // Get actual supply of BPT
        uint256 supply = IComposableStablePool(underlying).getActualSupply();

        // Follow same calculations as Balancer pool
        uint256 bptRatio = shares.divWad(supply);

        // New tokens and amounts excluding BPT
        tokens = new address[](poolTokens.length - 1);
        amounts = new uint256[](poolTokens.length - 1);

        // Loop through each token in the array and return the amounts out of each token given `shares`
        for (uint256 i = 0; i < amounts.length; ) {
            // Skip BPT index
            uint256 index = i < bptIndex ? i : i + 1;

            // Assign token
            tokens[i] = poolTokens[index];

            // Assign amount out given `shares`
            amounts[i] = balances[index].mulWad(bptRatio) - difference;

            unchecked {
                ++i;
            }
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
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     */
    function _swapTokensLegacy(
        ICygnusAltair.DexAggregator dexAggregator,
        address token0,
        uint256 amountUsd,
        bytes[] memory swapdata
    ) private {
        // Swap USD to tokenA with the actual token amount, since we are using a legacy method
        if (token0 != usd) _swapTokensAggregator(dexAggregator, swapdata[0], usd, token0, amountUsd);
    }

    /**
     *  @notice Swaps tokens with legacy aggregators
     *  @param dexAggregator The id of the dex aggregator to use
     *  @param token The token to swap
     *  @param amountUsd The amount of USD to convert to LP
     *  @param swapdata Bytes array consisting of 1inch API swap data
     */
    function _swapTokensOptimized(
        ICygnusAltair.DexAggregator dexAggregator,
        address token,
        uint256 amountUsd,
        bytes[] memory swapdata
    ) private {
        // Composable stable pools allow for single token deposit, so we perform only 1 swap to the first poolToken
        if (token != usd) _swapTokensAggregator(dexAggregator, swapdata[0], usd, token, amountUsd);
    }

    /**
     *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsd` of USD
     *  @notice Maximum 2 swaps
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
        bytes32 poolId = IComposableStablePool(lpTokenPair).getPoolId();

        // Tokens and amounts
        (address[] memory tokens, uint256[] memory amounts, ) = VAULT.getPoolTokens(poolId);

        // 2. Swap USDC to LP assets
        if (_isLegacy(dexAggregator)) {
            // Swap with legacy methods
            _swapTokensLegacy(dexAggregator, tokens[0], amountUsd, swapdata);
        }
        // Not legacy, swap with calldata - Always swap to token0
        else _swapTokensOptimized(dexAggregator, tokens[0], amountUsd, swapdata);

        // 3. Compute new amounts to deposit
        uint256[] memory amountsIn = new uint256[](tokens.length - 1);

        // Get BPT index from the pool
        uint256 bptIndex = IComposableStablePool(lpTokenPair).getBptIndex();

        for (uint256 i = 0; i < amountsIn.length; ) {
            // Filter out the BPT
            address token = tokens[i < bptIndex ? i : i + 1];

            // Assign amounts in of token received from the swap
            amountsIn[i] = _checkBalance(token);

            // Approve token in vault
            if (amountsIn[i] > 0) _approveToken(token, address(VAULT), amountsIn[i]);

            unchecked {
                ++i;
            }
        }

        // 4. Join pool and mint BPT - `EXACT_TOKENS_IN_FOR_BPT_OUT` - Use max amounts from `getPoolTokens` for gas savings
        VAULT.joinPool(poolId, address(this), address(this), IVault.JoinPoolRequest(tokens, amounts, abi.encode(1, amountsIn, 0), false));

        // LP Token minted
        liquidity = _checkBalance(lpTokenPair);

        // Clean dust
        _cleanDust(lpTokenPair, tokens, recipient, false);
    }

    /**
     *  @notice Converts an amount of LP Token to USD. It is called after calling a burn method on the LP and receiving tokens.
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
    ) internal virtual {
        // At this point we have array of `tokens` and `amounts` received after redeeming the BPT, we swap each one to USD
        for (uint256 i = 0; i < tokens.length; ) {
            // Check that token `i` is not USD
            if (tokens[i] != usd) _swapTokensAggregator(dexAggregator, swapdata[i], tokens[i], usd, amounts[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  LIQUIDATE ─────────────────────────────

    /**
     *  @notice Liquidates borrower internally and converts LP Tokens to receive back USD
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus Collateral
     *  @param borrowable The address of the borrowable contract
     *  @param recipient The receiver of the liquidation incentive
     *  @param seizeTokens The amount of CygLP seized
     *  @param repayAmount The amount of USD being repaid
     *  @param dexAggregator The DEX aggregator ID to use
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

        // 1. Flash redeem the LP back to the contract
        ICygnusCollateral(collateral).flashRedeemAltair(address(this), redeemAmount, LOCAL_BYTES);

        // 2. Exit BPT from the pool and receive assets
        // Get pool ID
        bytes32 poolId = IComposableStablePool(lpTokenPair).getPoolId();

        // Tokens array for this BPT
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // Exit Balancer pool, use `EXACT_BPT_IN_FOR_ALL_TOKENS_OUT` with 0 min amount received.
        // We check at the end for sufficient USD received anyways
        VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest(tokens, new uint256[](tokens.length), abi.encode(2, redeemAmount), false)
        );

        // 3. Swap all assets to USDC

        // Remove BPT from assets array and amounts
        address[] memory newTokens = new address[](tokens.length - 1);

        // Amounts minus BPT
        uint256[] memory newAmounts = new uint256[](tokens.length - 1);

        // BPT index
        uint256 bptIndex = IComposableStablePool(lpTokenPair).getBptIndex();

        for (uint256 i = 0; i < newTokens.length; ) {
            // Tokens
            newTokens[i] = tokens[i < bptIndex ? i : i + 1];

            // Amount of asset we own
            newAmounts[i] = _checkBalance(newTokens[i]);

            unchecked {
                ++i;
            }
        }

        // Swap all amounts to USDC
        _convertLiquidityToUsd(dexAggregator, newTokens, newAmounts, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientLiquidateUsd Avoid if received is less than liquidated
        if (usdAmount < repayAmount) revert CygnusAltair__InsufficientLiquidateUsd();

        // Transfer USD to recipient
        usd.safeTransfer(recipient, usdAmount - repayAmount);

        // Transfer the repay amount of USD to borrowable
        usd.safeTransfer(borrowable, repayAmount);

        // Clean dust (if any) from redeeming BPT and receiving tokens
        _cleanDust(lpTokenPair, tokens, recipient, true);
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
        // 1. Get Pool Id
        bytes32 poolId = IComposableStablePool(lpTokenPair).getPoolId();

        // 2. Create exit pool request
        (address[] memory tokens, , ) = VAULT.getPoolTokens(poolId);

        // 3. Exit pool, burn BPT and receive pool tokens - uses 'EXACT_BPT_IN_FOR_ALL_TOKENS_OUT'
        VAULT.exitPool(
            poolId,
            address(this),
            payable(address(this)),
            IVault.ExitPoolRequest(tokens, new uint256[](tokens.length), abi.encode(2, redeemAmount), false)
        );

        // 4. Swap all amounts to USDC
        // Tokens minus BPT
        address[] memory newTokens = new address[](tokens.length - 1);

        // Amounts minus BPT
        uint256[] memory newAmounts = new uint256[](tokens.length - 1);

        // BPT index
        uint256 bptIndex = IComposableStablePool(lpTokenPair).getBptIndex();

        for (uint256 i = 0; i < newTokens.length; ) {
            // Tokens
            newTokens[i] = tokens[i < bptIndex ? i : i + 1];

            // Amount of asset we own
            newAmounts[i] = _checkBalance(newTokens[i]);

            unchecked {
                ++i;
            }
        }

        // Swap all amounts to USDC
        _convertLiquidityToUsd(dexAggregator, newTokens, newAmounts, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientUSDAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) revert CygnusAltair__InsufficientUSDAmount();

        // Repay USD
        _repayAndRefund(ICygnusCollateral(collateral).borrowable(), usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);

        // Clean dust (if any) from redeeming BPT and receiving tokens
        _cleanDust(lpTokenPair, tokens, borrower, true);
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
     *  @notice Send dust to user who leveraged USDC into LP, or deleveraged LP into USDC
     *  @param lpTokenPair The address of the BPT to exclude from cleaning dust
     *  @param recipient The receiver of the dust
     */
    function _cleanDust(address lpTokenPair, address[] memory tokens, address recipient, bool sweepBpt) internal {
        // Loop through each token and transfer dust (if any)
        for (uint256 i = 0; i < tokens.length; i++) {
            // Balance of token `i`
            uint256 leftAmount = _checkBalance(tokens[i]);

            // Send leftover balance to user
            if (leftAmount > 0) {
                // Skip the BPT if not meant to sweep
                if (tokens[i] == lpTokenPair && !sweepBpt) continue;

                // Transfer dust
                tokens[i].safeTransfer(recipient, leftAmount);
            }
        }

        // Balance of token `i`
        uint256 leftAmountUsd = _checkBalance(usd);

        // Send leftover balance to user
        if (leftAmountUsd > 0) usd.safeTransfer(recipient, leftAmountUsd);
    }
}
