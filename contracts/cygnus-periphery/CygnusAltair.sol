// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusAltair} from "./interfaces/ICygnusAltair.sol";

// Libraries
import {CygnusDexLib} from "./libraries/CygnusDexLib.sol";
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IWrappedNative} from "./interfaces/IWrappedNative.sol";
import {IERC20} from "./interfaces/core/IERC20.sol";

// Cygnus Core
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {ICygnusTerminal} from "./interfaces/core/ICygnusTerminal.sol";
import {ICygnusCollateral} from "./interfaces/core/ICygnusCollateral.sol";

// Permit2
import {IAllowanceTransfer} from "./interfaces/core/IAllowanceTransfer.sol";
import {ISignatureTransfer} from "./interfaces/ISignatureTransfer.sol";

// 1Inch
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/core/IAggregationRouterV5.sol";

// Paraswap
import {IAugustusSwapper} from "./interfaces/IAugustusSwapper.sol";

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
abstract contract CygnusAltair is ICygnusAltair {
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
     *  @inheritdoc ICygnusAltair
     */
    string public override name;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant PARASWAP_AUGUSTUS_SWAPPER_V5 = 0xDEF171Fe48CF0115B1d80b88dc8eAB59176FEe57;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant ONE_INCH_ROUTER_V5 = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    /**
     *  @notice Empty permit to deposit leveraged LP amounts
     */
    IAllowanceTransfer.PermitSingle public emptyPermit;

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
    address public immutable override nativeToken;

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
        nativeToken = _hangar18.nativeToken();

        // Assign the USD address set at the factoryn
        usd = _hangar18.usd();
    }

    /**
     *  @notice Only accept native via fallback from the Wrapped native contract
     */
    receive() external payable {
        /// @custom:error NotNativeTokenSender Only accept from native contract (ie WETH)
        if (msg.sender != nativeToken) {
            revert CygnusAltair__NotNativeTokenSender({poolToken: msg.sender});
        }
    }

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
        if (_checkTimestamp() > deadline) {
            revert CygnusAltair__TransactionExpired({deadline: deadline});
        }
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

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Calls permit function on pool token
     *  @param terminal The address of the collateral or borrowable
     *  @param amount The permit amount
     *  @param deadline Permit deadline
     *  @param permitData Permit data to decode
     */
    function _checkPermit(address terminal, uint256 amount, uint256 deadline, bytes memory permitData) private {
        // Return if no permit data
        if (permitData.length == 0) return;

        // Decode permit data
        (bool approveMax, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitData, (bool, uint8, bytes32, bytes32));

        // Max value
        uint256 value = approveMax ? type(uint256).max : amount;

        // Call permit on terminal token
        ICygnusTerminal(terminal).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    // Swap tokens via paraswap

    /**
     *  @notice Creates the swap with Paraswap's Augustus Swapper. We don't update the amount, instead we clean dust at the end.
     *          This is because the data is of complex type (Path[] path). We pass the token being swapped and the amount being
     *          swapped to approve the transfer proxy (which is set on augustus wrapped via `getTokenTransferProxy`).
     *  @param swapData The data from Paraswap's `transaction` query
     *  @param srcToken The token being swapped
     *  @param fromAmount The amount of `srcToken` being swapped
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensParaswap(bytes memory swapData, address srcToken, uint256 fromAmount) private returns (uint256 amountOut) {
        // Paraswap's token proxy to approve in srcToken
        address paraswapTransferProxy = IAugustusSwapper(PARASWAP_AUGUSTUS_SWAPPER_V5).getTokenTransferProxy();

        // Approve Paraswap's transfer proxy in `srcToken` if necessary
        _approveToken(srcToken, paraswapTransferProxy, fromAmount);

        // Call the augustus wrapper with the data passed, triggering the fallback function for multi/mega swaps
        (bool success, bytes memory resultData) = PARASWAP_AUGUSTUS_SWAPPER_V5.call{value: msg.value}(swapData);

        /// @custom:error ParaswapTransactionFailed
        if (!success) revert CygnusAltair__ParaswapTransactionFailed();

        // Return amount received - This is off by some very small amount from the actual contract balance.
        // We shouldn't use it directly. Instead, query contract balance of token received
        assembly {
            amountOut := mload(add(resultData, 32))
        }
    }

    // Swap tokens via 1inch

    /**
     *  @notice Creates the swap with 1Inch's AggregatorV5. We pass an extra param `updatedAmount` to eliminate
     *          any slippage from the byte data passed. When calculating the optimal deposit for single sided
     *          liquidity deposit, our calculation can be off for a few mini tokens which don't affect the
     *          data of the aggregation executor, so we pass the tx data as is but update the srcToken amount
     *  @param swapData The data from 1inch `swap` query
     *  @param updatedAmount The balanceOf this contract`s srcToken
     *  @return amountOut The amount received of destination token
     */
    function _swapTokensInch(bytes memory swapData, uint256 updatedAmount) internal returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi.decode(
            swapData,
            (address, IAggregationRouterV5.SwapDescription, bytes, bytes)
        );

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != updatedAmount) desc.amount = updatedAmount;

        // Approve 1Inch Router in `srcToken` if necessary
        _approveToken(address(desc.srcToken), address(ONE_INCH_ROUTER_V5), desc.amount);

        // Swap `srcToken` to `dstToken` - Aggregator does the necessary minAmount check & we do checks at the end
        // of the leverage/deleverage functions anyways
        (amountOut, ) = IAggregationRouterV5(ONE_INCH_ROUTER_V5).swap(IAggregationExecutor(caller), desc, permit, data);
    }

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

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
     *  @dev Internal function to swap tokens using the specified aggregator.
     *  @param dexAggregator The aggregator to use for the token swap
     *  @param swapData The encoded swap data for the aggregator.
     *  @param srcToken The source token to swap
     *  @param srcAmount The amount of source token to swap
     *  @return amountOut The amount of swapped tokens received
     */
    function _swapTokensAggregator(
        DexAggregator dexAggregator,
        bytes memory swapData,
        address srcToken,
        uint256 srcAmount
    ) internal returns (uint256 amountOut) {
        // Check which dex aggregator to use
        if (dexAggregator == DexAggregator.PARASWAP) {
            // Swap tokens using ParaSwap aggregator
            amountOut = _swapTokensParaswap(swapData, srcToken, srcAmount);
        } else if (dexAggregator == DexAggregator.ONE_INCH) {
            // Swap tokens using 1inch aggregator
            amountOut = _swapTokensInch(swapData, srcAmount);
        }
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

    /**
     *  @notice Avoid repeating ourselves to make leverage data
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable The address of the borrowable of the lending pool
     *  @param lpAmountMin The minimum amount of LP Tokens to receive
     *  @param dexAggregator The dex aggregator to use for the swaps
     *  @param swapData the aggregator swap data to convert USD to liquidity
     */
    function _createLeverageShuttle(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 lpAmountMin,
        DexAggregator dexAggregator,
        bytes[] calldata swapData
    ) private view returns (bytes memory) {
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
                    swapData: swapData
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
                // We only allow the owner of the tokens to be the depositor, but
                // recipient can be set to another address if owner wants
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
                // We only allow the owner of the tokens to be the depositor, but
                // recipient can be set to another address if owner wants
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
        bytes[] calldata swapData
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
                swapData: swapData
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
        bytes[] calldata swapData
    ) external virtual override checkDeadline(deadline) {
        // Check permit
        _checkPermit(borrowable, usdAmount, deadline, permitData);

        // Encode data to bytes
        bytes memory cygnusShuttle = _createLeverageShuttle(lpTokenPair, collateral, borrowable, lpAmountMin, dexAggregator, swapData);

        // Call borrow with encoded data
        ICygnusBorrow(borrowable).borrow(msg.sender, address(this), usdAmount, cygnusShuttle);
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
        bytes[] calldata swapData
    ) external virtual override checkDeadline(deadline) {
        // Permit if any
        _checkPermit(collateral, cygLPAmount, deadline, permitData);

        // Current CygLP exchange rate
        uint256 exchangeRate = ICygnusCollateral(collateral).exchangeRate();

        // Get redeem amount
        uint256 redeemAmount = cygLPAmount.mulWad(exchangeRate);

        // Encode redeem data
        bytes memory redeemData = abi.encode(
            AltairDeleverageCalldata({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                recipient: msg.sender,
                redeemTokens: cygLPAmount,
                usdAmountMin: usdAmountMin,
                dexAggregator: dexAggregator,
                swapData: swapData
            })
        );

        // Flash redeem LP Tokens
        ICygnusCollateral(collateral).flashRedeemAltair(lpTokenPair, redeemAmount, redeemData);
    }
}
