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
    .               .            .               .      🛰️     .           .                .           .
           █████████           ---======*.                                                 .           ⠀
          ███░░░░░███                                               📡                🌔                         . 
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀           .          
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .⠀
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████     .----===*  ⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .⠀
                       ███ ░███  ███ ░███                .                 .                 .  ⠀
     🛰️  .             ░░██████  ░░██████                                             .                 .           
                       ░░░░░░    ░░░░░░      -------=========*                      .                     ⠀
           .                            .       .          .            .                          .             .⠀
    
        CYGNUS ALTAIR EXTENSION - `Velodrome Volatile LPs`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {CygnusAltair} from "./CygnusAltair.sol";
import {ICygnusAltair} from "./interfaces/ICygnusAltair.sol";

// Interfaces
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";

// Libraries
import {CygnusDexLib} from "./libraries/CygnusDexLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Strategies
import {IDexPair} from "./interfaces/core/CollateralVoid/IDexPair.sol";
import {IDexRouter} from "./interfaces/core/CollateralVoid/IDexRouter.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";

/**
 *  @title  CygnusAltairX Extension of router contract that handles DEX specific functionalities and core contract callbacks
 *  @author CygnusDAO
 *  @notice Router that is used to leverage, deleverage and flash liquidate. Where as CygnusAltair.sol contains
 *          the functions that are the same for all lending pools, CygnusAltairX is dex-specific.
 */
contract CygnusAltairX is CygnusAltair {
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

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Router for the Dex swap
     */
    IDexRouter public constant DEX_ROUTER = IDexRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the periphery contract. Factory must be deployed on the chain first to get the addresses
     *          of deployers and the wrapped native token (WETH, WFTM, etc.)
     *  @param _hangar18 The address of the Cygnus Factory contract on this chain
     */
    constructor(IHangar18 _hangar18, string memory _name) CygnusAltair(_hangar18) {
        // Name
        name = string(abi.encodePacked("Cygnus-Altair: ", _name));
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltair
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares
    ) external view override(ICygnusAltair) returns (address[] memory tokens, uint256[] memory amounts) {
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

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @param borrowable Address of the Cygnus borrow contract
     *  @param token Address of the token we are repaying (USD)
     *  @param borrower Address of the borrower who is repaying the loan
     *  @param amountMax The max available amount
     */
    function repayAndRefundPrivate(address borrowable, address token, address borrower, uint256 amountMax) internal {
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
            if (token == nativeToken) {
                // Withdraw native
                IWrappedNative(nativeToken).withdraw(refundAmount);

                // Transfer native
                borrower.safeTransferETH(refundAmount);
            } else {
                // Transfer Token
                token.safeTransfer(borrower, refundAmount);
            }
        }
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
    function convertUsdToLiquidity(
        DexAggregator dexAggregator,
        address token0,
        address token1,
        uint256 amountUsd,
        bytes[] memory swapdata,
        uint256 reserves0,
        uint256 reserves1
    ) private returns (uint256 liquidity) {
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
            if (token0 == nativeToken || token1 == nativeToken) {
                // If token0 is nativeToken, then assign tokenA to token0, else tokenA to token1
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
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
        uint256 swapAmount = CygnusDexLib.optimalDepositA(totalAmountA, reservesA, 5);

        // ─────────────────────── 4. Swap `optimalTokenA` amount to tokenB directly on the pair
        // Swap tokens
        uint256 totalAmountB = swapTokensDex(tokenA, tokenB, swapAmount);

        // LP Token
        liquidity = addLiquidityPrivate(tokenA, tokenB, totalAmountA - swapAmount, totalAmountB);
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
    function convertLiquidityToUsd(
        DexAggregator dexAggregator,
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

    /**
     *  @notice Swap tokens using the dex router for the second swap
     *  @param tokenIn The address of the token we are swapping
     *  @param tokenOut The address of the token we are receiving
     *  @param amount Amount of `tokenIn` we are swapping to `tokenOut`
     *  @return Amount received of `tokenOut`
     */
    function swapTokensDex(address tokenIn, address tokenOut, uint256 amount) private returns (uint256) {
        // Check approve tokenIn
        _approveToken(tokenIn, address(DEX_ROUTER), amount);

        // Swap tokenIn to tokenOut
        uint256[] memory amounts = DEX_ROUTER.swapExactTokensForTokensSimple(
            amount,
            0,
            tokenIn,
            tokenOut,
            false,
            address(this),
            block.timestamp
        );

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
    function addLiquidityPrivate(address tokenA, address tokenB, uint256 amountA, uint256 amountB) private returns (uint256 liquidity) {
        // Check tokenA approve
        _approveToken(tokenA, address(DEX_ROUTER), amountA);

        // Check tokenB approve
        _approveToken(tokenB, address(DEX_ROUTER), amountB);

        // Mint LP
        (, , liquidity) = DEX_ROUTER.addLiquidity(tokenA, tokenB, false, amountA, amountB, 0, 0, address(this), block.timestamp);
    }

    /**
     *  @notice Liquidates borrower internally and converts LP Tokens to receive back USD
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus Collateral
     *  @param borrowable The address of the borrowable contract
     *  @param seizeTokens The amount of CygLP seized
     *  @param swapdata The 1inch calldata to swap LP back to USD
     *  @return usdAmount The amount of USD received
     */
    function flashLiquidatePrivate(
        address lpTokenPair,
        address collateral,
        address borrowable,
        address recipient,
        uint256 seizeTokens,
        uint256 repayAmount,
        DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) private returns (uint256 usdAmount) {
        // Calculate LP amount to redeem
        uint256 redeemAmount = seizeTokens.mulWad(ICygnusCollateral(collateral).exchangeRate());

        // Flash redeem the LP back to the contract
        ICygnusCollateral(collateral).flashRedeemAltair(lpTokenPair, redeemAmount, LOCAL_BYTES);

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Token0 and token1 from the LP
        (, , , , , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Convert amountA and amountB to USD
        convertLiquidityToUsd(dexAggregator, amountAMax, amountBMax, token0, token1, swapdata);

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
     *  @notice Mints liquidity from the DEX and deposits in the collateral, minting CygLP to the recipient
     *  @param lpTokenPair The address of the LP Token
     *  @param recipient The address of the recipient
     *  @param collateral The address of the Cygnus Collateral contract
     *  @param borrowAmount The amount of USD borrowed to conver to LP
     *  @param lpAmountMin The minimum amount of LP allowed to receive
     *  @param swapdata Swap data for aggregator
     */
    function mintLPAndDepositPrivate(
        address lpTokenPair,
        address recipient,
        address collateral,
        uint256 borrowAmount,
        uint256 lpAmountMin,
        DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) private {
        // Get token metadata
        (, , uint256 reserves0, uint256 reserves1, , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Converts the borrowed amount of USD to tokenA and tokenB to mint the LP Token
        uint256 liquidity = convertUsdToLiquidity(dexAggregator, token0, token1, borrowAmount, swapdata, reserves0, reserves1);

        /// @custom:error InsufficientLPTokenAmount Avoid if LP Token amount received is less than min
        if (liquidity < lpAmountMin) revert CygnusAltair__InsufficientLPTokenAmount();

        // Check allowance and deposit the LP token in the collateral contract
        _approveToken(lpTokenPair, address(PERMIT2), liquidity);

        // Approve Permit
        _approvePermit2(lpTokenPair, collateral, liquidity);

        // Mint CygLP to the recipient
        ICygnusCollateral(collateral).deposit(liquidity, recipient, emptyPermit, LOCAL_BYTES);

        // Check for dust from after leverage
        cleanDustPrivate(token0, token1, recipient);
    }

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
    function removeLPAndRepayPrivate(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 usdAmountMin,
        DexAggregator dexAggregator,
        bytes[] memory swapdata
    ) private {
        // Burn and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Get token0 and token1
        (, , , , , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Convert tokens to USD using aggregators
        convertLiquidityToUsd(dexAggregator, amountAMax, amountBMax, token0, token1, swapdata);

        // Manually get the balance, this is because in some cases the amount returned by aggregators is not 100% accurate
        uint256 usdAmount = _checkBalance(usd);

        /// @custom:error InsufficientRedeemAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) revert CygnusAltair__InsufficientUSDAmount();

        // Repay USD
        repayAndRefundPrivate(borrowable, usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);

        // Clean dust after deleverage
        cleanDustPrivate(token0, token1, borrower);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  LIQUIDATE ─────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function altairLiquidate_f2x(
        address sender,
        uint256 cygLPAmount,
        uint256 repayAmount,
        bytes calldata data
    ) external virtual override(ICygnusAltair) {
        // Decode data passed from borrow contract
        AltairLiquidateCalldata memory cygnusShuttle = abi.decode(data, (AltairLiquidateCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({sender: sender, origin: tx.origin});
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (msg.sender != cygnusShuttle.borrowable) {
            revert CygnusAltair__MsgSenderNotBorrowable({sender: msg.sender, borrowable: cygnusShuttle.borrowable});
        }

        // Convert CygLP to USD
        flashLiquidatePrivate(
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
     *  @inheritdoc ICygnusAltair
     */
    function altairBorrow_O9E(address sender, uint256 borrowAmount, bytes calldata data) external virtual override(ICygnusAltair) {
        // Decode data passed from borrow contract
        AltairLeverageCalldata memory cygnusShuttle = abi.decode(data, (AltairLeverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({sender: sender, origin: tx.origin});
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (msg.sender != cygnusShuttle.borrowable) {
            revert CygnusAltair__MsgSenderNotBorrowable({sender: msg.sender, borrowable: cygnusShuttle.borrowable});
        }

        // Mint LP and deposit in collateral
        mintLPAndDepositPrivate(
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
     *  @inheritdoc ICygnusAltair
     */
    function altairRedeem_u91A(address sender, uint256 redeemAmount, bytes calldata data) external virtual override(ICygnusAltair) {
        // Decode deleverage shuttle data
        AltairDeleverageCalldata memory redeemData = abi.decode(data, (AltairDeleverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({sender: sender, origin: tx.origin});
        }
        /// @custom:error MsgSenderNotCollateral Avoid if the msg sender is not Cygnus collateral contract
        else if (msg.sender != redeemData.collateral) {
            revert CygnusAltair__MsgSenderNotCollateral({sender: msg.sender, collateral: redeemData.collateral});
        }

        // Shh
        redeemAmount;

        // Burn LP and withdraw from collateral
        removeLPAndRepayPrivate(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.borrowable,
            redeemData.redeemTokens,
            redeemData.usdAmountMin,
            redeemData.dexAggregator,
            redeemData.swapdata
        );
    }

    /**
     *  @notice Send dust to user who leveraged USDC into LP, if any
     *  @param token0 The address of token0 from the LP
     *  @param token1 The address of token1 from the LP
     *  @param recipient The address of the user leveraging the position
     */
    function cleanDustPrivate(address token0, address token1, address recipient) private {
        // Check for dust of token0
        uint256 leftAmount0 = _checkBalance(token0);

        // Check for dust of token1
        uint256 leftAmount1 = _checkBalance(token1);

        // Send leftover token0 to user
        if (leftAmount0 > 0) token0.safeTransfer(recipient, leftAmount0);

        // Send leftover token1 to user
        if (leftAmount1 > 0) token1.safeTransfer(recipient, leftAmount1);
    }
}
