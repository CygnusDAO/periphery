//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusAltair.sol
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
    
        CYGNUS PERIPHERY ROUTER - `Altair`                                                           
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════  */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusAltair} from "./interfaces/ICygnusAltair.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {ICygnusAltairX} from "./interfaces/ICygnusAltairX.sol";

// Cygnus Core
import {IERC20} from "./interfaces/core/IERC20.sol";
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {ICygnusTerminal} from "./interfaces/core/ICygnusTerminal.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";
import {IAllowanceTransfer} from "./interfaces/core/IAllowanceTransfer.sol"; // Permit2
import {ISignatureTransfer} from "./interfaces/core/ISignatureTransfer.sol"; // Permit2

// Aggregators
import {IAugustusSwapper} from "./interfaces/aggregators/IAugustusSwapper.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/aggregators/IAggregationRouterV5.sol";

/**
 *  @title  CygnusAltair Periphery contract to interact with Cygnus Core contracts
 *  @author CygnusDAO
 *  @notice The base periphery contract that is used to interact with Cygnus Core contracts. Aside from
 *          depositing and withdrawing from the core contracts, users should always use this router
 *          (or a similar implementation) to interact wtih the core contracts. It is integrated with Uniswap's
 *          Permit2 and allows users to interact with Cygnus Core without ever giving any allowance ot this
 *          router (can borrow, repay, leverage, deleverage and liquidate using the Permit functions).
 *
 *          Leverage   = Borrow USDC from the borrowable and use it to mint more collateral (Liquidity Tokens)
 *          Deleverage = Redeem collateral (Liquidity Tokens) and sell the assets for USDC to repay the loan
 *                       or just to convert all your liquidity to USDC in 1 step.
 *
 *          As such, using a dex aggregator is crucial to make our system work. This router is integrated with
 *          the following aggregators to make sure that slippage is minimal between the borrowed USDC and the
 *          minted LP:
 *            1. 0xProject
 *            2. 1Inch (Legacy and Optmiized Routers)
 *            3. Paraswap
 *
 *          During the leverage functionality the router borrows USD from the borrowable arm contract, and
 *          then converts it to LP Tokens. Since each liquidity token requires different logic to "mint".,
 *          for example, minting an LP from UniswapV2 is different to minting a BPT from Balancer or UniswapV3,
 *          the router delegates the call to an extension contract to mint the liquidity token.
 *
 *          During the deleverage functionality the router receives Liquidity Tokens from the collateral arm
 *          contract, and then converts it to USDC. Again, since the process of burning or redeeming the liquidity
 *          token requires different logic across DEXes, this contract delegates the redeem call to the extensions
 *          in the fallback.
 *
 *          The admin is in charge of setting up the extension contracts and these are updatable, however this is
 *          the only contract that users should interact with.
 *
 *          Functions in this contract allow for:
 *            - Borrowing USD
 *            - Repaying USD
 *            - Liquidating user's with USD (pay back USD, receive CygLP + bonus liquidation reward)
 *            - Flash liquidating a user by selling collateral to the market and receive USD
 *            - Leveraging USD into Liquidity
 *            - Deleveraging Liquidity into USD
 */
contract CygnusAltair is ICygnusAltair {
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
     *  @notice Internal record of all Altair Extensions - Borrowable/Collateral address to extension contract implementation.
     */
    mapping(address => address) internal altairExtensions;

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @notice Internal mapping to check if extension has been added
     */
    mapping(address => bool) public override isExtension;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address[] public override allExtensions;

    /**
     *  @inheritdoc ICygnusAltair
     */
    string public override name = "Cygnus: Altair Router";

    /**
     *  @inheritdoc ICygnusAltair
     */
    string public constant override version = "1.0.1";

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override PARASWAP_AUGUSTUS_SWAPPER_V5 = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override ONE_INCH_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override OxPROJECT_EXCHANGE_PROXY = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override OPEN_OCEAN_EXCHANGE_PROXY = 0x6352a56caadC4F1E25CD6c75970Fa768A3304e64;

    /**
     *  @inheritdoc ICygnusAltair
     */
    IHangar18 public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public immutable override usd;

    /**
     *  @inheritdoc ICygnusAltair
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
    }

    /**
     *  @dev Fallback function is executed if none of the other functions match the function
     *  identifier or no data was provided with the function call.
     */
    fallback() external payable {
        // Get extension for the caller contract (borrowable or collateral)
        address altairX = altairExtensions[msg.sender];

        /// @custom:error ExtensionDoesntExist Avoid if the extension does not exist
        if (altairX == address(0)) revert CygnusAltair__AltairXDoesNotExist();

        // Delegate the call to the extension router
        (bool success, bytes memory data) = altairX.delegatecall(msg.data);

        // Revert with extension reason
        if (!success) _extensionRevert(data);

        // Return the return value from leverage/deleverage/flash liquidate
        _extensionReturn(data);
    }

    /**
     *  @dev This function is called for plain Ether transfers, i.e. for every call with empty calldata.
     */
    receive() external payable {}

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier checkDeadline Reverts the transaction if the block.timestamp is after deadline
     */
    modifier checkDeadline(uint256 deadline) {
        _checkDeadline(deadline);
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

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

    /**
     *  @notice The current block timestamp
     */
    function _checkTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     *  @notice Reverts the transaction if the block.timestamp is after deadline
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function _checkDeadline(uint256 deadline) internal view {
        /// @custom:error TransactionExpired Avoid transacting past deadline
        if (_checkTimestamp() > deadline) revert CygnusAltair__TransactionExpired();
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltair
     */
    function getAltairExtension(address poolToken) external view override returns (address) {
        // Return the router extension
        return altairExtensions[poolToken];
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function altairExtensionsLength() external view override returns (uint256) {
        // How many extensions we have added to the base router
        return allExtensions.length;
    }

    /**
     *  @dev Same calculation as all vault tokens, asset = shares * balance / supply
     *  @inheritdoc ICygnusAltair
     */
    function getAssetsForShares(
        address lpTokenPair,
        uint256 shares,
        uint256 slippage
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        // Get the extension for this lp token pair
        address altairX = altairExtensions[lpTokenPair];

        /// @custom:error ExtensionDoesntExist Avoid if the extension does not exist
        if (altairX == address(0)) revert CygnusAltair__AltairXDoesNotExist();

        // The extension should implement the assets for shares function - ie. Which assets and how much we receive
        // by redeeming `shares` amount of a liquidity token
        return ICygnusAltairX(altairX).getAssetsForShares(lpTokenPair, shares, slippage);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Calls permit function on pool token
     *  @param terminal The address of the collateral or borrowable
     *  @param amount The permit amount
     *  @param deadline Permit deadline
     *  @param permitData Permit data to decode
     */
    function _checkPermit(address terminal, uint256 amount, uint256 deadline, bytes memory permitData) internal {
        // Return if no permit data
        if (permitData.length == 0) return;

        // Decode permit data
        (uint256 _amount, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitData, (uint256, uint8, bytes32, bytes32));

        // Shh
        amount;

        // Call permit on terminal token
        ICygnusTerminal(terminal).permit(msg.sender, address(this), _amount, deadline, v, r, s);
    }

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
     *  @notice Safe internal function to repay borrowed amount
     *  @param borrowable The address of the Cygnus borrow arm where the borrowed amount was taken from
     *  @param amountMax The max amount that can be repaid
     *  @param borrower The address of the account that is repaying the borrowed amount
     */
    function _maxRepayAmount(address borrowable, uint256 amountMax, address borrower) internal returns (uint256 amount) {
        // Accrue interest first
        ICygnusBorrow(borrowable).accrueInterest();

        // Get latest borrow balance of borrower (accrues interest)
        (, uint256 borrowedAmount) = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    // AGGREGATORS - These are not used by this router, they are kept here for consistency with extensions along with dex aggregator
    //               addresses.

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
     *  @notice Creates the swap with 1Inch's AggregatorV5. We update the `desc.amount` traded of `srcToken by our contract's
     *          current balance of the token. This is only available using 1Inch's legacy `swap` method but can be helpful when
     *          we know that we are going to be receiving AT LEAST X amount of token, and the amount received is off by some
     *          mini tokens. It can help us not leave any dust behind and make full use of the funds.
     *  @dev The API call is created with the param `&compatibilityMode=true`
     *  @param swapdata The data from 1inch `swap` query
     *  @param srcToken The token being swapped
     *  @param srcAmount The amount of `srcToken` being swapped
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
     *  @notice Creates the swap with 1Inch's AggregatorV5 using the router's optimized paths (unoswap, uniswapv3, etc.). Same as above
     *          except we don't update the srcAmount.
     *  @param swapdata The data from 1inch `swap` query
     *  @param srcToken The token being swapped
     *  @param srcAmount The amount of `srcToken` being swapped
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensOneInchV2(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) {
        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(srcToken, address(ONE_INCH_ROUTER_V5), srcAmount);

        // Call 1Inch's Aggregation Router V5 with the data passed
        (bool success, bytes memory resultData) = ONE_INCH_ROUTER_V5.call{value: msg.value}(swapdata);

        /// @custom:error OneInchTransactionFailed
        if (!success) revert CygnusAltair__OneInchTransactionFailed();

        // Return amount received of dstToken
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

        // Call the exchange proxy with the data passed
        (bool success, bytes memory resultData) = OxPROJECT_EXCHANGE_PROXY.call{value: msg.value}(swapdata);

        /// @custom:error 0xProjectTransactionFailed
        if (!success) revert CygnusAltair__0xProjectTransactionFailed();

        // Return amount received of dstToken
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

    // Swap tokens via OpenOcean

    /**
     *  @notice Creates the swap with OpenOcean's Aggregator API
     *  @param swapdata The data from OpenOcean`s swap quote query
     *  @param srcAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensOpeanOcean(bytes memory swapdata, address srcToken, uint256 srcAmount) internal returns (uint256 amountOut) { 
        // Approve 0x Exchange Proxy Router in `srcToken` if necessary
        _approveToken(srcToken, OPEN_OCEAN_EXCHANGE_PROXY, srcAmount);

        // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
        (bool success, bytes memory resultData) = OPEN_OCEAN_EXCHANGE_PROXY.call{value: msg.value}(swapdata);

        /// @custom:error 0xProjectTransactionFailed
        if (!success) revert CygnusAltair__OpenOceanTransactionFailed();

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
        DexAggregator dexAggregator,
        bytes memory swapdata,
        address srcToken,
        uint256 srcAmount
    ) internal returns (uint256 amountOut) {
        // Check which dex aggregator to use
        // Case 0: PARASWAP - Swap tokens using Augustus Swapper V5.
        if (dexAggregator == DexAggregator.PARASWAP) {
            amountOut = _swapTokensParaswap(swapdata, srcToken, srcAmount);
        }
        // Case 1: ONE INCH LEGACY - Swap tokens using One Inch's `swap()` function on the
        // Aggregation Router V5 contract. Can help control swap params via swapDescription struct.
        // The API call is done with `compatibilityMode=true`
        else if (dexAggregator == DexAggregator.ONE_INCH_LEGACY) {
            amountOut = _swapTokensOneInchV1(swapdata, srcToken, srcAmount);
        }
        // Case 2: ONE INCH V2 - Swap tokens using One Inch optimized routers - Unoswap, etc.
        else if (dexAggregator == DexAggregator.ONE_INCH_V2) {
            amountOut = _swapTokensOneInchV2(swapdata, srcToken, srcAmount);
        }
        // Case 3: 0xPROJECT - Swap with matcha/0x swap api with their exchange proxy
        else if (dexAggregator == DexAggregator.OxPROJECT) {
            amountOut = _swapTokens0xProject(swapdata, srcToken, srcAmount);
        }
        // Case 4: OPEN_OCEAN - Swap with OpenOcean
        else if (dexAggregator == DexAggregator.OPEN_OCEAN) {
            amountOut = _swapTokensOpeanOcean(swapdata, srcToken, srcAmount);
        }
    }

    /**
     *  @notice Avoid repeating ourselves to make leverage data and stack-too-deep errors
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param lpAmountMin The minimum amount of LP Tokens to receive
     *  @param dexAggregator The dex aggregator to use for the swaps
     *  @param swapdata the aggregator swap data to convert USD to liquidity
     */
    function _createLeverageData(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 lpAmountMin,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) internal view returns (bytes memory) {
        // Return encoded bytes to pass to borrowbale
        return
            abi.encode(
                AltairLeverageCalldata({
                    lpTokenPair: lpTokenPair,
                    collateral: collateral,
                    borrowable: borrowable,
                    recipient: msg.sender,
                    lpAmountMin: lpAmountMin,
                    dexAggregator: dexAggregator,
                    swapdata: swapdata
                })
            );
    }

    /**
     *  @notice Avoid repeating ourselves to make deleverage data and stack-too-deep errors
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param cygLPAmount The amount of CygLP we are deleveraging
     *  @param usdAmountMin The minimum amount of USD to receive from the deleverage
     *  @param dexAggregator The dex aggregator to use for the swaps
     *  @param swapdata the aggregator swap data to convert USD to liquidity
     */
    function _createDeleverageData(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 cygLPAmount,
        uint256 usdAmountMin,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) internal view returns (bytes memory) {
        // Encode redeem data
        return
            abi.encode(
                AltairDeleverageCalldata({
                    lpTokenPair: lpTokenPair,
                    collateral: collateral,
                    borrowable: borrowable,
                    recipient: msg.sender,
                    redeemTokens: cygLPAmount,
                    usdAmountMin: usdAmountMin,
                    dexAggregator: dexAggregator,
                    swapdata: swapdata
                })
            );
    }

    /**
     *  @notice Flash liquidate data to pass to the borrowable contract
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param borrower The address of the borrower to liquidate
     *  @param amount The amount of USDC being repaid
     *  @param dexAggregator The dex aggregator to use for the swaps
     *  @param swapdata the aggregator swap data to convert USD to liquidity
     */
    function _createFlashLiquidateData(
        address lpTokenPair,
        address collateral,
        address borrowable,
        address borrower,
        uint256 amount,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) internal view returns (bytes memory) {
        // Encode data to bytes
        return
            abi.encode(
                AltairLiquidateCalldata({
                    lpTokenPair: lpTokenPair,
                    collateral: collateral,
                    borrowable: borrowable,
                    borrower: borrower,
                    recipient: msg.sender,
                    repayAmount: amount,
                    dexAggregator: dexAggregator,
                    swapdata: swapdata
                })
            );
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  POSITIONS ────────────────────────────────────

    /**
     *  @notice Easier data for frontend and for build tx data
     *  @inheritdoc ICygnusAltair
     */
    function latestLenderPosition(
        ICygnusBorrow borrowable,
        address lender
    ) external returns (uint256 cygUsdBalance, uint256 rate, uint256 positionUsd) {
        // Accrue interest and update balance
        borrowable.sync();

        // Return latest position
        return borrowable.getLenderPosition(lender);
    }

    /**
     *  @notice Easier data for frontend and for build tx data
     *  @inheritdoc ICygnusAltair
     */
    function latestBorrowerPosition(
        ICygnusBorrow borrowable,
        address borrower
    )
        external
        returns (
            uint256 cygLPBalance,
            uint256 principal,
            uint256 borrowBalance,
            uint256 price,
            uint256 rate,
            uint256 positionUsd,
            uint256 positionLp,
            uint256 health,
            uint256 liquidity,
            uint256 shortfall
        )
    {
        // Accrue interest and update balance
        borrowable.sync();

        // Get collateral
        address collateral = borrowable.collateral();

        // Return borrower`s latest position with accrued interest
        return ICygnusCollateral(collateral).getBorrowerPosition(borrower);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function latestShuttleInfo(
        ICygnusBorrow borrowable
    )
        external
        returns (uint256 supplyApr, uint256 borrowApr, uint256 util, uint256 totalBorrows, uint256 totalBalance, uint256 exchangeRate)
    {
        // Accrue interest and update balance
        borrowable.sync();

        // For APRs
        uint256 secondsPerYear = 24 * 60 * 60 * 365;

        // The APR for lenders
        supplyApr = borrowable.supplyRate() * secondsPerYear;

        // The interest rate for borrowers
        borrowApr = borrowable.borrowRate() * secondsPerYear;

        // Utilization rate
        util = borrowable.utilizationRate();

        // Total borrows stored in the contract
        totalBorrows = borrowable.totalBorrows();

        // Available cash
        totalBalance = borrowable.totalBalance();

        // The latest exchange rate
        exchangeRate = borrowable.exchangeRate();
    }

    //  BORROW ───────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function borrow(
        address borrowable,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        // Check permit
        _checkPermit(borrowable, amount, deadline, permitData);

        // Borrow amount
        ICygnusBorrow(borrowable).borrow(msg.sender, recipient, amount, LOCAL_BYTES);
    }

    //  REPAY ────────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function repay(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Ensure that the amount to repay is never more than currently owed.
        // Accrues interest first then gets the borrow balance
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Check permit - transfer USD from sender to borrowable
        _checkPermit(usd, amount, deadline, permitData);

        // Transfer USD from msg sender to borrow contract
        usd.safeTransferFrom(msg.sender, borrowable, amount);

        // Call borrow to update borrower's borrow balance
        ICygnusBorrow(borrowable).borrow(borrower, address(0), 0, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function repayPermit2Allowance(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata signature
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Ensure that the amount to repay is never more than currently owed.
        // Accrues interest first then gets the borrow balance
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Check for permit (else users can just approve permit2 and skip this by passing an empty
        // PermitSingle and an empty `_signature`)
        if (signature.length > 0) {
            // Set allowance using permit
            IAllowanceTransfer(PERMIT2).permit(
                // The owner of the tokens being approved.
                // We only allow the owner of the tokens to be the repayer
                msg.sender,
                // Data signed over by the owner specifying the terms of approval
                _permit,
                // The owner's signature over the permit data that was the result
                // of signing the EIP712 hash of `_permit`
                signature
            );
        }

        // Transfer underlying to vault
        IAllowanceTransfer(PERMIT2).transferFrom(msg.sender, borrowable, uint160(amount), usd);

        // Call borrow to update borrower's borrow balance and repay loan
        ICygnusBorrow(borrowable).borrow(borrower, address(0), 0, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function repayPermit2Signature(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata signature
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Ensure that the amount to repay is never more than currently owed.
        // Accrues interest first then gets the borrow balance
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Signture transfer
        ISignatureTransfer(PERMIT2).permitTransferFrom(
            // The permit message.
            _permit,
            // The transfer recipient and amount.
            ISignatureTransfer.SignatureTransferDetails({to: borrowable, requestedAmount: amount}),
            // Owner of the tokens and signer of the message.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `_permit`.
            signature
        );

        // Call borrow to update borrower's borrow balance and repay loan
        ICygnusBorrow(borrowable).borrow(borrower, address(0), 0, LOCAL_BYTES);
    }

    //  LIQUIDATE BORROW ─────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function liquidate(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Amount to repay
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Check permit
        _checkPermit(usd, amount, deadline, permitData);

        // Transfer USD
        usd.safeTransferFrom(msg.sender, borrowable, amount);

        // Liquidate
        seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient, amount, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function liquidatePermit2Allowance(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        IAllowanceTransfer.PermitSingle calldata _permit,
        bytes calldata signature
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Ensure that the amount to repay is never more than currently owed.
        // Accrues interest first then gets the borrow balance
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Check for permit (else users can just approve permit2 and skip this by passing an empty
        // PermitSingle and an empty `_signature`)
        if (signature.length > 0) {
            // Set allowance using permit
            IAllowanceTransfer(PERMIT2).permit(
                // The owner of the tokens being approved.
                // We only allow the owner of the tokens to be the liquidator
                msg.sender,
                // Data signed over by the owner specifying the terms of approval
                _permit,
                // The owner's signature over the permit data that was the result
                // of signing the EIP712 hash of `_permit`
                signature
            );
        }

        // Transfer underlying to vault
        IAllowanceTransfer(PERMIT2).transferFrom(msg.sender, borrowable, uint160(amount), usd);

        // Liquidate
        seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient, amount, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function liquidatePermit2Signature(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        ISignatureTransfer.PermitTransferFrom calldata _permit,
        bytes calldata signature
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Amount to repay
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Signture transfer
        ISignatureTransfer(PERMIT2).permitTransferFrom(
            // The permit message.
            _permit,
            // The transfer recipient and amount.
            ISignatureTransfer.SignatureTransferDetails({to: borrowable, requestedAmount: amount}),
            // Owner of the tokens and signer of the message.
            msg.sender,
            // The packed signature that was the result of signing
            // the EIP712 hash of `_permit`.
            signature
        );

        // Liquidate
        seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient, amount, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function flashLiquidate(
        address borrowable,
        address collateral,
        uint256 amountMax,
        address borrower,
        uint256 deadline,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Amount to repay
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Encode data to bytes
        bytes memory liquidateData = _createFlashLiquidateData(
            lpTokenPair,
            collateral,
            borrowable,
            borrower,
            amount,
            dexAggregator,
            swapdata
        );

        // Liquidate
        // The liquidated CYGLP is transfered to the collateral to then call `flashRedeem` and receive LP
        ICygnusBorrow(borrowable).liquidate(borrower, collateral, amount, liquidateData);
    }

    //  LEVERAGE ─────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
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
        bytes[] calldata swapdata
    ) external virtual override checkDeadline(deadline) returns (uint256 liquidity) {
        // Check permit
        _checkPermit(borrowable, usdAmount, deadline, permitData);

        // Encode data to bytes
        bytes memory borrowData = _createLeverageData(lpTokenPair, collateral, borrowable, lpAmountMin, dexAggregator, swapdata);

        // Call borrow with encoded data
        liquidity = ICygnusBorrow(borrowable).borrow(msg.sender, address(this), usdAmount, borrowData);
    }

    //  DELEVERAGE ───────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
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
        bytes[] calldata swapdata
    ) external virtual override checkDeadline(deadline) returns (uint256 usdAmount) {
        // Permit if any
        _checkPermit(collateral, cygLPAmount, deadline, permitData);

        // Get redeem amount
        uint256 redeemAmount = cygLPAmount.mulWad(ICygnusCollateral(collateral).exchangeRate());

        // Encode data to bytes
        bytes memory redeemData = _createDeleverageData(
            lpTokenPair,
            collateral,
            borrowable,
            cygLPAmount,
            usdAmountMin,
            dexAggregator,
            swapdata
        );

        // Flash redeem LP Tokens
        usdAmount = ICygnusCollateral(collateral).flashRedeemAltair(address(this), redeemAmount, redeemData);
    }

    // ADMIN

    /**
     *  @notice Initializes the mapping of borrowable/collateral/lp token => extension
     *  @inheritdoc ICygnusAltair
     *  @custom:security only-admin
     */
    function setAltairExtension(uint256 shuttleId, address extension) external override {
        // Get latest admin
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin
        if (msg.sender != admin) revert CygnusAltair__MsgSenderNotAdmin();

        // Get the shuttle for the shuttle ID
        (bool launched, , address borrowable, address collateral, ) = hangar18.allShuttles(shuttleId);

        /// @custom:error ShuttleDoesNotExist
        if (!launched) revert CygnusAltair__ShuttleDoesNotExist();

        // Add to array
        if (!isExtension[extension]) {
            // Add to array
            allExtensions.push(extension);

            // Mark as true
            isExtension[extension] = true;
        }

        // For leveraging USD
        altairExtensions[borrowable] = extension;

        // For deleveraging the LP
        altairExtensions[collateral] = extension;

        // For getting the assets for a a given amount of shares:
        //
        // asset received = shares_burnt * asset_balance / vault_token_supply
        //
        // Calling `getAssetsForShares(underlying, amount)` returns two arrays: `tokens` and `amounts`. The
        // extensions handle this logic since it differs per underlying Liquidity Token. For example, returning
        // assets by burning 1 LP in UniV2, or 1 BPT in a Balancer Weighted Pool, etc. Helpful when deleveraging
        // liquidity tokens into USDC.
        altairExtensions[ICygnusCollateral(collateral).underlying()] = extension;
    }
}
