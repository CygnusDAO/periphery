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
 *  @notice The router contract that is used to interact with Cygnus core contracts.
 *
 *          This router is integrated with Paraswap's Augustus Swapper and 1inch's AggregationRouter5 across all
 *          chains, and it works mostly on-chain. The queries are estimated before the first call, following the
 *          same logic for swaps as this contract and then each proceeding call builds on top of the next one.
 *
 *          During the leverage functionality the router borrows USD from the borrowable arm contract, and then
 *          converts it to LP Tokens. What this router does is account for every possible swap scenario between
 *          tokens, using a byte array populated with 1inch data. Before the leverage or de-leverage function call,
 *          we calculate quotes to estimate what the `amount` will be during each swap stage, and we use the data
 *          passed from each step and override the `amount` with the current balance of this contract (both amounts
 *          should be the same, or in some cases could be off by a very small amount).
 *
 *          The max amount of aggswaps that we can perform during a leverage is 1 and de-leverage is 2. Thus the data
 *          passed will always be at most a 2-length byte array.
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
    string public override name = string(abi.encodePacked("Cygnus: Altair Router #", block.chainid));
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
    address public constant override OxPROJECT_EXCHANGE_PROXY = 0xDEF1ABE32c034e558Cdd535791643C58a13aCC10;

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
        if (!success) _revertWithData(data);

        // Return the return value from leverage/deleverage/flash liqudiate
        _returnWithData(data);
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

    /**
     *  @notice Reverts with reason if the delegate call fails
     */
    function _revertWithData(bytes memory data) internal pure {
        assembly {
            revert(add(data, 32), mload(data))
        }
    }

    /**
     *  @notice Returns the returned data from the delegate call
     */
    function _returnWithData(bytes memory data) internal pure {
        assembly {
            return(add(data, 32), mload(data))
        }
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
     *  @inheritdoc ICygnusAltair
     */
    function getAssetsForShares(
        address lpTokenPair,
        uint256 shares
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        // Get the extension for this lp token pair
        address altairX = altairExtensions[lpTokenPair];

        /// @custom:error ExtensionDoesntExist Avoid if the extension does not exist
        if (altairX == address(0)) revert CygnusAltair__AltairXDoesNotExist();

        // The extension should implement the assets for shares function - ie. Which assets and how much we receive
        // by redeeming `shares` amount of a liquidity token
        return ICygnusAltairX(altairX).getAssetsForShares(lpTokenPair, shares);
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
        // Accrue interest first to not leave debt after full repay
        ICygnusBorrow(borrowable).accrueInterest();

        // Get borrow balance of borrower
        // prettier-ignore
        (/* principal */, uint256 borrowedAmount) = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
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
        // Case 1: PARASWAP - Swap tokens using Augustus Swapper V5.
        if (dexAggregator == DexAggregator.PARASWAP) {
            amountOut = _swapTokensParaswap(swapdata, srcToken, srcAmount);
        }
        // Case 2: ONE INCH LEGACY - Swap tokens using One Inch's `swap()` function on the
        // Aggregation Router V5 contract. Can help control swap params via swapDescription struct.
        // The API call is done with `compatibilityMode=true`
        else if (dexAggregator == DexAggregator.ONE_INCH_LEGACY) {
            amountOut = _swapTokensOneInchV1(swapdata, srcToken, srcAmount);
        }
        // Case 3: ONE INCH V2 - Swap tokens using One Inch optimized routers - Unoswap, etc.
        else if (dexAggregator == DexAggregator.ONE_INCH_V2) {
            amountOut = _swapTokensOneInchV2(swapdata, srcToken, srcAmount);
        }
        // Case 4: 0xPROJECT - Swap with matcha/0x swap api with their exchange proxy
        else if (dexAggregator == DexAggregator.OxPROJECT) {
            amountOut = _swapTokens0xProject(swapdata, srcToken, srcAmount);
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
    function _createLeverageShuttle(
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
    function _createDeleverageShuttle(
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

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

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
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Ensure that the amount to repay is never more than currently owed.
        // Accrues interest first then gets the borrow balance
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

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
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Amount to repay
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

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
        address recipient,
        uint256 deadline,
        DexAggregator dexAggregator,
        bytes[] calldata swapdata
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Amount to repay
        amount = _maxRepayAmount(borrowable, amountMax, borrower);

        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Encode data to bytes
        bytes memory cygnusShuttle = abi.encode(
            AltairLiquidateCalldata({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                borrower: borrower,
                recipient: recipient,
                repayAmount: amount,
                dexAggregator: dexAggregator,
                swapdata: swapdata
            })
        );

        // Liquidate
        ICygnusBorrow(borrowable).liquidate(borrower, collateral, amount, cygnusShuttle);
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
        bytes memory borrowData = _createLeverageShuttle(lpTokenPair, collateral, borrowable, lpAmountMin, dexAggregator, swapdata);

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

        // Current CygLP exchange rate
        uint256 exchangeRate = ICygnusCollateral(collateral).exchangeRate();

        // Get redeem amount
        uint256 redeemAmount = cygLPAmount.mulWad(exchangeRate);

        // Encode data to bytes
        bytes memory redeemData = _createDeleverageShuttle(
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
     *  @notice Updates the mapping of borrowable/collateral/lp token => extension
     *  @custom:security only-admin 👽
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

        // For getting the assets for a a given amount of shares
        altairExtensions[ICygnusCollateral(collateral).underlying()] = extension;
    }
}
