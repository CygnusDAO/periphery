// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import { ICygnusAltairX } from "./interfaces/ICygnusAltairX.sol";

// Interfaces
import { IWETH } from "./interfaces/IWETH.sol";
import { IERC20 } from "./interfaces/core/IERC20.sol";
import { IHangar18 } from "./interfaces/core/IHangar18.sol";
import { ICygnusBorrow } from "./interfaces/core/ICygnusBorrow.sol";
import { ICygnusTerminal } from "./interfaces/core/ICygnusTerminal.sol";
import { ICygnusCollateral } from "./interfaces/core/ICygnusCollateral.sol";
import { IAggregationRouterV5, IAggregationExecutor } from "./interfaces/core/IAggregationRouterV5.sol";
import { IAllowanceTransfer } from "./interfaces/core/IAllowanceTransfer.sol";
import { ISignatureTransfer } from "./interfaces/core/ISignatureTransfer.sol";

// Libraries
import { CygnusDexLib } from "./libraries/CygnusDexLib.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { FixedPointMathLib } from "./libraries/FixedPointMathLib.sol";

// Orbiter
import { IDexPair } from "./interfaces/core/CollateralVoid/IDexPair.sol";
import { IDexRouter } from "./interfaces/core/CollateralVoid/IDexRouter.sol";

/**
 *  @title  CygnusAltairX Periphery contract to interact with Cygnus Core contracts
 *  @author CygnusDAO
 *  @notice The router contract is used to interact with Cygnus core contracts using 1inch Dex Aggregator
 *
 *          This router is integrated with 1inch's AggregationRouter5 across all chains, and it works mostly
 *          on-chain. The queries are estimated before the first call, following the same logic for swaps as this
 *          contract and then each proceeding call builds on top of the next one, keeping the data passed to the
 *          executioner contract intact at each stage, but we update the `amount` passed during each call to the
 *          current token balance of this addres (could differ slightly).
 *
 *          During the leverage functionality the router borrows USD from the borrowable arm contract, and then
 *          converts it to LP Tokens. What this router does is account for every possible swap scenario between
 *          tokens, using a byte array populated with 1inch data. Before the leverage or de-leverage function call,
 *          we calculate quotes to estimate what the `amount` will be during each swap stage, and we use the data
 *          passed from each step and override the `amount` with the current balance of this contract (both amounts
 *          should be the same, or in some cases could be off by a very small amount).
 *
 *          The max amount of swaps that we can perform during a leverage or de-leverage is 2, thus the data passed
 *          will always be a at least a 2-length byte array.
 *
 *          Functions in this contract allow for:
 *            - Borrowing USD
 *            - Repaying USD
 *            - Liquidating user's with USD (pay back USD, receive CygLP + bonus liquidation reward)
 *            - Liquidating user's and converting to USD (pay back USD, receive CygLP + bonus equivalent in USD)
 *            - Leveraging Liquidity positions
 *            - Deleveraging Liquidity Positions
 */
contract CygnusAltairX is ICygnusAltairX {
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

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     * @custom:struct AltairLeverageCalldata Encoded bytes passed to Cygnus Borrow contract for leverage
     * @custom:member lpTokenPair The address of the LP Token
     * @custom:member collateral The address of the Cygnus collateral contract
     * @custom:member borrowable The address of the Cygnus borrow contract
     * @custom:member recipient The address of the user receiving the leveraged LP Tokens
     * @custom:member lpAmountMin The minimum amount of LP Tokens to receive
     * @custom:member swapData The 1inch swap data byte array to convert USD to Liquidity Tokens
     */
    struct AltairLeverageCalldata {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 lpAmountMin;
        bytes[] swapData;
    }

    /**
     * @custom:struct AltairDeleverageCalldata Encoded bytes passed to Cygnus Collateral contract for de-leverage
     * @custom:member lpTokenPair The address of the LP Token
     * @custom:member collateral The address of the collateral contract
     * @custom:member borrowable The address of the borrow contract
     * @custom:member recipient The address of the user receiving the de-leveraged assets
     * @custom:member redeemTokens The amount of CygLP to redeem
     * @custom:member usdAmountMin The minimum amount of USD to receive by redeeming `redeemTokens`
     * @custom:member swapData The 1inch swap data byte array to convert Liquidity Tokens to USD
     */
    struct AltairDeleverageCalldata {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 redeemTokens;
        uint256 usdAmountMin;
        bytes[] swapData;
    }

    /**
     * @custom:struct AltairLiquidateCalldata Encoded bytes passed to Cygnus Borrow contract for liquidating borrows
     * @custom:member lpTokenPair The address of the LP Token
     * @custom:member collateral The address of the collateral contract
     * @custom:member borrowable The address of the borrow contract
     * @custom:member recipient The address of the liquidator (or this contract if protocol liquidation)
     * @custom:member borrower The address of the borrower being liquidated
     * @custom:member repayAmount The USD amount being repaid by the liquidator
     * @custom:member swapData The 1inch swap data byte array to convert Liquidity Tokens to USD after burning
     */
    struct AltairLiquidateCalldata {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        address borrower;
        uint256 repayAmount;
        bytes[] swapData;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    string public override name = "Cygnus-Altair-X: Velo Volatile";

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
    address public immutable override nativeToken;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IAggregationRouterV5 public immutable override aggregationRouterV5;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    bytes public constant override LOCAL_BYTES = new bytes(0);

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IDexRouter public constant override DEX_ROUTER = IDexRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    /**
     *  @notice Empty permit to deposit leveraged LP amounts
     */
    IAllowanceTransfer.PermitSingle public emptyPermit;

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

        // One inch router
        aggregationRouterV5 = _hangar18.AGGREGATION_ROUTER_V5();
    }

    /**
     *  @notice Only accept native via fallback from the Wrapped native contract
     */
    receive() external payable {
        /// @custom:error NotNativeTokenSender Only accept from native contract (ie WETH)
        if (msg.sender != nativeToken) {
            revert CygnusAltair__NotNativeTokenSender({ poolToken: msg.sender });
        }
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier checkDeadline Reverts the transaction if the block.timestamp is after deadline
     */
    modifier checkDeadline(uint256 deadline) {
        checkDeadlinePrivate(deadline);
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
          5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ───────────────────────────────────────────── Private ─────────────────────────────────────────────────  */

    /**
     *  @notice The current block timestamp
     */
    function getBlockTimestamp() private view returns (uint256) {
        return block.timestamp;
    }

    /**
     *  @notice Reverts the transaction if the block.timestamp is after deadline
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function checkDeadlinePrivate(uint256 deadline) private view {
        /// @custom:error TransactionExpired Avoid transacting past deadline
        if (getBlockTimestamp() > deadline) {
            revert CygnusAltair__TransactionExpired({ deadline: deadline });
        }
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return amount This contract's `token` balance
     */
    function contractBalanceOf(address token) private view returns (uint256) {
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

        // Token 0 from the underlying
        tokens[0] = IDexPair(underlying).token0();

        // Token1 from the underlying
        tokens[1] = IDexPair(underlying).token1();

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
     *  @notice Creates the swap with 1Inch's AggregatorV5. We pass an extra param `updatedAmount` to eliminate
     *          any slippage from the byte data passed. When calculating the optimal deposit for single sided
     *          liquidity deposit, our calculation can be off for a few mini tokens which don't affect the
     *          data of the aggregation executor, so we pass the tx data as is but update the srcToken amount
     *  @param swapData The data from 1inch `swap` query
     *  @param updatedAmount The balanceOf this contract`s srcToken
     */
    function swapTokensInch(bytes memory swapData, uint256 updatedAmount) private returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi
            .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != updatedAmount) desc.amount = updatedAmount;

        // Approve 1Inch Router in `srcToken` if necessary
        approveTokenPrivate(address(desc.srcToken), address(aggregationRouterV5), desc.amount);

        // Swap `srcToken` to `dstToken` - Aggregator does the necessary minAmount check & we do checks at the end
        // of the leverage/deleverage functions anyways
        (amountOut, ) = aggregationRouterV5.swap(IAggregationExecutor(caller), desc, permit, data);
    }

    // 2 FUNCTIONS: - CONVERT USD TO LIQUIDITY TOKEN
    //              - CONVERT LIQUIDITY TOKEN TO USD

    /**
     *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsd` of USD
     *  @notice Maximum 2 swaps
     *  @param lpTokenPair The address of the LP Token
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountUsd The amount of USDC converted into LP
     *  @param swapData Bytes array consisting of 1inch API swap data
     */
    function convertUsdToLiquidity(
        address lpTokenPair,
        address token0,
        address token1,
        uint256 amountUsd,
        bytes[] memory swapData
    ) internal virtual returns (uint256 liquidity) {
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
            // Perform first swap with 1inch data
            swapTokensInch(swapData[0], amountUsd);
        }
        // ─────────────────────── 3. Calculate optimal deposit amount for an LP Token
        // Amount A
        uint256 totalAmountA = contractBalanceOf(tokenA);

        // Get reserves
        (uint112 reserves0, uint112 reserves1, ) = IDexPair(lpTokenPair).getReserves();

        // Get reserves A for calculating optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A - 997/1000 (0.3%)
        uint256 swapAmount = CygnusDexLib.optimalDepositA(totalAmountA, reservesA, 997);

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
     *  @param token1 The address of token1 from the LP Token pair
     *  @param swapData Bytes array consisting of 1inch API swap data
     */
    function convertLiquidityToUsd(
        uint256 amountTokenA,
        uint256 amountTokenB,
        address token0,
        address token1,
        bytes[] memory swapData
    ) private returns (uint256) {
        // ─────────────────────── 1. Check if token0 or token1 is already USD
        uint256 amountA;
        uint256 amountB;

        // If token0 or token1 is USD then swap opposite
        if (token0 == usd || token1 == usd) {
            // Convert the other token to USD and return
            (amountA, amountB) = token0 == usd
                ? (amountTokenA, swapTokensInch(swapData[0], amountTokenB))
                : (swapTokensInch(swapData[0], amountTokenA), amountTokenB);

            // Explicit return
            return amountA + amountB;
        }

        // ─────────────────── 2. Not USD, swap both to USD
        // Swap token0 to USD
        amountA = swapTokensInch(swapData[0], amountTokenA);

        // Swap token1 to USD
        amountB = swapTokensInch(swapData[1], amountTokenB);

        // USD balance
        return amountA + amountB;
    }

    /**
     *  @notice Function to add liquidity and mint LP Tokens
     *  @param tokenA Address of the LP Token's token0
     *  @param tokenB Address of the LP Token's token1
     *  @param amountA Amount of token A to add as liquidity
     *  @param amountB Amount of token B to add as liquidity
     *  @return liquidity The total LP Tokens minted
     */
    function addLiquidityPrivate(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) private returns (uint256 liquidity) {
        // Check tokenA approve
        approveTokenPrivate(tokenA, address(DEX_ROUTER), amountA);

        // Check tokenB approve
        approveTokenPrivate(tokenB, address(DEX_ROUTER), amountB);

        // Mint LP
        (, , liquidity) = DEX_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /**
     *  @notice Calls permit function on pool token
     *  @param terminal The address of the collateral or borrowable
     *  @param amount The permit amount
     *  @param deadline Permit deadline
     *  @param permitData Permit data to decode
     */
    function permitPrivate(address terminal, uint amount, uint deadline, bytes memory permitData) private {
        // Return if no permit data
        if (permitData.length == 0) return;

        // Decode permit data
        (bool approveMax, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitData, (bool, uint8, bytes32, bytes32));

        // Max value
        uint value = approveMax ? type(uint256).max : amount;

        // Call permit on terminal token
        ICygnusTerminal(terminal).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    /**
     *  @param borrowable Address of the Cygnus borrow contract
     *  @param token Address of the token we are repaying (USD)
     *  @param borrower Address of the borrower who is repaying the loan
     *  @param amountMax The max available amount
     */
    function repayAndRefundPrivate(address borrowable, address token, address borrower, uint256 amountMax) private {
        // Repay
        uint256 amount = repayAmountPrivate(borrowable, amountMax, borrower);

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
                IWETH(nativeToken).withdraw(refundAmount);

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
    function repayAmountPrivate(
        address borrowable,
        uint256 amountMax,
        address borrower
    ) private returns (uint256 amount) {
        // Accrue interest first to not leave debt after full repay
        ICygnusBorrow(borrowable).accrueInterest();

        // Get borrow balance of borrower
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    /**
     *  @notice Grants allowance from this contract to a dex' router (or just a contract instead of `router`)
     *  @param token The address of the token we are approving
     *  @param router The address of the dex router we are approving (or just a contract)
     *  @param amount The amount to approve
     */
    function approveTokenPrivate(address token, address router, uint256 amount) private {
        // If allowance is already higher than `amount` return
        if (IERC20(token).allowance(address(this), router) >= amount) {
            return;
        }

        // Approve token
        token.safeApprove(router, type(uint256).max);
    }

    /**
     *  @notice Approves permit2 in `token` - This is used to deposit leveraged liquidity back into the CygnusCollateral
     *  @param token The address of the token we are approving the permit2 router in
     *  @param spender The address of the contract we are allowing to move our `token` (CygnusCollateral)
     *  @param amount The amount we are allowing
     */
    function approvePermit2Private(address token, address spender, uint256 amount) private {
        // Get allowance
        (uint160 allowed, , ) = IAllowanceTransfer(PERMIT2).allowance(address(this), token, spender);

        // Return without approving
        if (allowed >= amount) return;

        // We approve to the max uint160 allowed and max allowed deadline
        IAllowanceTransfer(PERMIT2).approve(token, spender, type(uint160).max, type(uint48).max);
    }

    /**
     *  @notice Swap tokens using the dex router for the second swap
     *  @param tokenIn The address of the token we are swapping
     *  @param tokenOut The address of the token we are receiving
     *  @param amount Amount of `tokenIn` we are swapping to `tokenOut`
     */
    function swapTokensDex(address tokenIn, address tokenOut, uint256 amount) internal returns (uint256) {
        // Check approve tokenIn
        approveTokenPrivate(tokenIn, address(DEX_ROUTER), amount);

        // Path of tokenA to tokenB
        address[] memory path = new address[](2);

        // Make path
        (path[0], path[1]) = (tokenIn, tokenOut);

        // Swap using dex
        uint256[] memory amounts = DEX_ROUTER.swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp);

        // Return amount received
        return amounts[amounts.length - 1];
    }

    // Liquidate to USD

    /**
     *  @notice Liquidates borrower internally and converts LP Tokens to receive back USD
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus Collateral
     *  @param borrowable The address of the borrowable contract
     *  @param seizeTokens The amount of CygLP seized
     *  @param swapData The 1inch calldata to swap LP back to USD
     *  @return usdAmount The amount of USD received
     */
    function flashLiquidatePrivate(
        address lpTokenPair,
        address collateral,
        address borrowable,
        address recipient,
        uint256 seizeTokens,
        uint256 repayAmount,
        bytes[] memory swapData
    ) private returns (uint256 usdAmount) {
        // Redeem CygLP for LP Token, send to the lp token address
        ICygnusCollateral(collateral).redeem(seizeTokens, lpTokenPair, address(this));

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Get token0
        address token0 = IDexPair(lpTokenPair).token0();

        // Get token1
        address token1 = IDexPair(lpTokenPair).token1();

        // Convert amountA and amountB to USD
        usdAmount = convertLiquidityToUsd(amountAMax, amountBMax, token0, token1, swapData);

        /// @custom:error InsufficientLiquidateUsd Avoid if received is less than liquidated
        if (usdAmount < repayAmount) {
            revert CygnusAltair__InsufficientLiquidateUsd({ usdAmountMin: repayAmount, usdAmount: usdAmount });
        }

        // Transfer USD to recipient
        usd.safeTransfer(recipient, usdAmount - repayAmount);

        // Transfer the repay amount of USD to borrowable
        usd.safeTransfer(borrowable, repayAmount);
    }

    // Burn LP Token and receive token0 and token1

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
    function removeLPAndRepayPrivate(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 usdAmountMin,
        uint256 redeemAmount,
        bytes[] memory swapData
    ) private {
        // Transfer LP Token back to LP Token's contract to remove liquidity
        IDexPair(lpTokenPair).transfer(lpTokenPair, redeemAmount);

        // Burn and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        /// @custom:error InsufficientBurnAmountA Avoid invalid burn amount of token A
        if (amountAMax <= 0) {
            revert CygnusAltair__InsufficientBurnAmountA({ amount: amountAMax });
        }
        /// @custom:error InsufficientBurnAmountB Avoid invalid burn amount of token B
        else if (amountBMax <= 0) {
            revert CygnusAltair__InsufficientBurnAmountB({ amount: amountBMax });
        }

        (, , , , , address token0, address token1) = IDexPair(lpTokenPair).metadata();

        // Convert tokens to USD
        uint256 usdAmount = convertLiquidityToUsd(amountAMax, amountBMax, token0, token1, swapData);

        /// @custom:error InsufficientRedeemAmount Avoid if USD received is less than min
        if (usdAmount < usdAmountMin) {
            revert CygnusAltair__InsufficientRedeemAmount({ usdAmountMin: usdAmountMin, usdAmount: usdAmount });
        }

        // Repay USD
        repayAndRefundPrivate(borrowable, usd, borrower, usdAmount);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);
    }

    // Leverage

    /**
     *  @notice Leverage internal function and calls borrow contract
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus collateral address for this lpTokenPair
     *  @param borrowable The address of the Cygnus borrowable address for this collateral
     *  @param usdAmount The amount of USD to borrow from borrowable
     *  @param lpAmountMin The minimum amount of LP Tokens to receive (Slippage calculated with our oracle)
     *  @param swapData The byte array of 1inch calls to leverage USD into LP tokens
     */
    function leveragePrivate(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 usdAmount,
        uint256 lpAmountMin,
        bytes[] calldata swapData
    ) private {
        // Encode data to bytes
        bytes memory cygnusShuttle = abi.encode(
            AltairLeverageCalldata({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                recipient: msg.sender,
                lpAmountMin: lpAmountMin,
                swapData: swapData
            })
        );

        // Call borrow with encoded data
        ICygnusBorrow(borrowable).borrow(msg.sender, address(this), usdAmount, cygnusShuttle);
    }

    // Deleverage

    /**
     *  @notice Main deleverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable THe address of the borrowable of the lending pool
     *  @param cygLPAmount The amount of CygLP tokens to deleverage
     *  @param lpTokenPair The address of the LP Token
     *  @param usdAmountMin The minimum amount of USD to receive by deleveraging
     *  @param swapData The byte array of 1inch calls to deleverage LP Tokens into USD
     */
    function deleveragePrivate(
        address collateral,
        address borrowable,
        uint256 cygLPAmount,
        address lpTokenPair,
        uint256 usdAmountMin,
        bytes[] calldata swapData
    ) private {
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
                swapData: swapData
            })
        );

        // Flash redeem LP Tokens
        ICygnusCollateral(collateral).flashRedeemAltair(address(this), redeemAmount, redeemData);
    }

    /**
     *  @notice Send dust to user who leveraged USDC into LP, if any
     *  @param token0 The address of token0 from the LP
     *  @param token1 The address of token1 from the LP
     *  @param recipient The address of the user leveraging the position
     */
    function cleanDustPrivate(address token0, address token1, address recipient) internal {
        // Check for dust of token0
        uint256 leftAmount0 = contractBalanceOf(token0);

        // Check for dust of token1
        uint256 leftAmount1 = contractBalanceOf(token1);

        // Send leftover token0 to user
        if (leftAmount0 > 0) token0.safeTransfer(recipient, leftAmount0);

        // Send leftover token1 to user
        if (leftAmount1 > 0) token1.safeTransfer(recipient, leftAmount1);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  BORROW ───────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function borrow(
        address borrowable,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        // Check permit
        permitPrivate(borrowable, amount, deadline, permitData);

        // Borrow amount
        ICygnusBorrow(borrowable).borrow(msg.sender, recipient, amount, LOCAL_BYTES);
    }

    //  REPAY BORROW ─────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function repay(
        address borrowable,
        uint256 amountMax,
        address borrower,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Ensure that the amount to repay is never more than currently owed.
        // Accrues interest first then gets the borrow balance
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

        // Transfer USD from msg sender to borrow contract
        usd.safeTransferFrom(msg.sender, borrowable, amount);

        // Call borrow to update borrower's borrow balance
        ICygnusBorrow(borrowable).borrow(borrower, address(0), 0, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltairX
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
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

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
     *  @inheritdoc ICygnusAltairX
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
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

        // Signture transfer
        ISignatureTransfer(PERMIT2).permitTransferFrom(
            // The permit message.
            _permit,
            // The transfer recipient and amount.
            ISignatureTransfer.SignatureTransferDetails({ to: borrowable, requestedAmount: amount }),
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
     *  @inheritdoc ICygnusAltairX
     */
    function liquidate(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Amount to repay
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

        // Transfer USD
        usd.safeTransferFrom(msg.sender, borrowable, amount);

        // Liquidate
        seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient, amount, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltairX
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
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

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
     *  @inheritdoc ICygnusAltairX
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
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

        // Signture transfer
        ISignatureTransfer(PERMIT2).permitTransferFrom(
            // The permit message.
            _permit,
            // The transfer recipient and amount.
            ISignatureTransfer.SignatureTransferDetails({ to: borrowable, requestedAmount: amount }),
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
     *  @inheritdoc ICygnusAltairX
     */
    function flashLiquidate(
        address borrowable,
        address collateral,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        bytes[] calldata swapData
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Amount to repay
        amount = repayAmountPrivate(borrowable, amountMax, borrower);

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
                swapData: swapData
            })
        );

        // Liquidate
        ICygnusBorrow(borrowable).liquidate(borrower, address(this), amount, cygnusShuttle);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairLiquidate_f2x(
        address sender,
        uint256 cygLPAmount,
        uint256 repayAmount,
        bytes calldata data
    ) external virtual override {
        // Decode data passed from borrow contract
        AltairLiquidateCalldata memory cygnusShuttle = abi.decode(data, (AltairLiquidateCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (msg.sender != cygnusShuttle.borrowable) {
            revert CygnusAltair__MsgSenderNotBorrowable({ sender: msg.sender, borrowable: cygnusShuttle.borrowable });
        }

        // Convert CygLP to USD
        flashLiquidatePrivate(
            cygnusShuttle.lpTokenPair,
            cygnusShuttle.collateral,
            cygnusShuttle.borrowable,
            cygnusShuttle.recipient,
            cygLPAmount, // Seized amount of CygLP
            repayAmount,
            cygnusShuttle.swapData
        );
    }

    //  LEVERAGE ─────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function leverage(
        address collateral,
        address borrowable,
        uint256 amountUsd,
        uint256 amountLPMin,
        uint256 deadline,
        bytes[] calldata swapData,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        // Check permit
        permitPrivate(borrowable, amountUsd, deadline, permitData);

        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Pass LP Token, collateral, borrowable, amount, recipient
        leveragePrivate(lpTokenPair, collateral, borrowable, amountUsd, amountLPMin, swapData);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairBorrow_O9E(address sender, uint256 borrowAmount, bytes calldata data) external virtual override {
        // Decode data passed from borrow contract
        AltairLeverageCalldata memory cygnusShuttle = abi.decode(data, (AltairLeverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (msg.sender != cygnusShuttle.borrowable) {
            revert CygnusAltair__MsgSenderNotBorrowable({ sender: msg.sender, borrowable: cygnusShuttle.borrowable });
        }

        // Get token0 and token1 for the swaps
        address token0 = IDexPair(cygnusShuttle.lpTokenPair).token0();
        address token1 = IDexPair(cygnusShuttle.lpTokenPair).token1();

        // Converts the borrowed amount of USD to tokenA and tokenB to mint the LP Token
        uint256 liquidity = convertUsdToLiquidity(
            cygnusShuttle.lpTokenPair,
            token0,
            token1,
            borrowAmount,
            cygnusShuttle.swapData
        );

        /// @custom:error InsufficientLPTokenAmount Avoid if LP Token amount received is less than min
        if (liquidity < cygnusShuttle.lpAmountMin) {
            revert CygnusAltair__InsufficientLPTokenAmount({
                lpAmountMin: cygnusShuttle.lpAmountMin,
                liquidity: liquidity
            });
        }

        // Check allowance and deposit the LP token in the collateral contract
        approveTokenPrivate(cygnusShuttle.lpTokenPair, address(PERMIT2), liquidity);

        // Approve Permit
        approvePermit2Private(cygnusShuttle.lpTokenPair, cygnusShuttle.collateral, liquidity);

        // Mint CygLP to the recipient
        ICygnusCollateral(cygnusShuttle.collateral).deposit(
            liquidity,
            cygnusShuttle.recipient,
            emptyPermit,
            LOCAL_BYTES
        );

        // Check for dust from after leverage
        cleanDustPrivate(token0, token1, cygnusShuttle.recipient);
    }

    //  DELEVERAGE ───────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function deleverage(
        address collateral,
        address borrowable,
        uint256 cygLPAmount,
        uint256 usdAmountMin,
        uint256 deadline,
        bytes[] calldata swapData,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        /// @custom:error InvalidRedeemAmount Avoid redeeming 0 tokens
        if (cygLPAmount <= 0) {
            revert CygnusAltair__InvalidRedeemAmount({ redeemer: msg.sender, redeemTokens: cygLPAmount });
        }

        // Permit if any
        permitPrivate(collateral, cygLPAmount, deadline, permitData);

        // Get collateral
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Private deleverage
        deleveragePrivate(collateral, borrowable, cygLPAmount, lpTokenPair, usdAmountMin, swapData);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairRedeem_u91A(address sender, uint256 redeemAmount, bytes calldata data) external virtual override {
        // Decode deleverage shuttle data
        AltairDeleverageCalldata memory redeemData = abi.decode(data, (AltairDeleverageCalldata));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin });
        }
        /// @custom:error MsgSenderNotCollateral Avoid if the msg sender is not Cygnus collateral contract
        else if (msg.sender != redeemData.collateral) {
            revert CygnusAltair__MsgSenderNotCollateral({ sender: msg.sender, collateral: redeemData.collateral });
        }

        // Remove liquidity from pool and repay to borrowable
        removeLPAndRepayPrivate(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.borrowable,
            redeemData.redeemTokens,
            redeemData.usdAmountMin,
            redeemAmount,
            redeemData.swapData
        );
    }
}
