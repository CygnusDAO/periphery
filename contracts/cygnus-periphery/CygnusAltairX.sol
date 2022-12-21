// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusAltairX } from "./interfaces/ICygnusAltairX.sol";
import { Context } from "./utils/Context.sol";

// Interfaces
import { IERC20 } from "./interfaces/core/IERC20.sol";
import { IWAVAX } from "./interfaces/core/IWAVAX.sol";
import { IDexPair } from "./interfaces/core/IDexPair.sol";
import { ICygnusBorrow } from "./interfaces/core/ICygnusBorrow.sol";
import { ICygnusFactory } from "./interfaces/core/ICygnusFactory.sol";
import { ICygnusTerminal } from "./interfaces/core/ICygnusTerminal.sol";
import { ICygnusCollateral } from "./interfaces/core/ICygnusCollateral.sol";
import { IAggregationRouterV4, IAggregationExecutor } from "./interfaces/IAggregationRouterV4.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";

/**
 *  @title  CygnusAltairX Periphery contract to interact with Cygnus Core contracts
 *  @author CygnusDAO
 *  @notice The router contract is used to interact with Cygnus core contracts using 1inch Dex Aggregator
 *
 *          This router is integrated with 1inch's AggregationRouterV4 across all chains, and it works mostly
 *          on-chain. The queries are estimated before the first call, following the same logic for swaps as this
 *          contract and then each proceeding call builds on top of the next one, keeping the data passed to the
 *          executioner contract intact at each stage, but we update the `amount` passed during each call to the
 *          current token balance of this addres (could differ slightly).
 *
 *          During the leverage functionality the router borrows USDC from the borrowable arm contract, and then
 *          converts it to LP Tokens. What this router does is account for every possible swap scenario between
 *          tokens, using a byte array populated with 1inch data. Before the leverage or de-leverage function call,
 *          we calculate quotes to estimate what the `amount` will be during each swap stage, and we use the data
 *          passed from each step and override the `amount` with the current balance of this contract (both amounts
 *          should be the same, or in some cases could be off by a very small amount).
 *
 *          The max amount of swaps that we can perform during a leverage or de-leverage is 3, thus the data passed
 *          will always be a at least a 3-length byte array. In case a swap is not neeeded, we pass a 0 value in its
 *          place as to keep the length fixed.
 *
 *          Functions in this contract allow for:
 *              - Minting CygLP and CygUSD (Pool tokens for collateral and borrowable respectively)
 *              - Redeeming CygLP and CygUSD
 *              - Borrowing USDC
 *              - Repaying USDC
 *              - Liquidating user's with USDC (pay back USDC, receive CygLP + bonus liquidation reward)
 *              - Liquidating user's and converting to USDC (pay back USDC, receive CygLP + bonus equivalent in USDC)
 *              - Leveraging LP tokens
 *              - Deleveraging LP Tokens
 */
contract CygnusAltairX is ICygnusAltairX, Context {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. LIBRARIES
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:library PRBMathUD60x18 Library for uint256 fixed point math, also imports the main library `PRBMath`
     */
    using PRBMathUD60x18 for uint256;

    /**
     *  @custom:library SafeTransferLib For safe transfers of Erc20 tokens
     */
    using SafeTransferLib for address;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ───────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

    /**
     *  @custom:struct CygnusShuttle Encoded bytes passed to Cygnus Borrow contract for leverage
     *  @custom:member lpTokenPair The address of the LP Token
     *  @custom:member collateral The address of the Cygnus collateral contract
     *  @custom:member borrowable The address of the Cygnus borrow contract
     *  @custom:member recipient The address of the user leveraging LP Tokens
     *  @custom:member lpAmountMin The minimum amount of LP Tokens to receive
     *  @cusotm:member swapData The 1inch swap data byte array to convert USDC to LP Tokens
     */
    struct CygnusShuttle {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 lpAmountMin;
        bytes[] swapData;
    }

    /**
     *  @custom:struct RedeemLeverageCallData Encoded bytes passed to Cygnus Collateral contract for de-leverage
     *  @custom:member lpTokenPair The address of the LP Token
     *  @custom:member collateral The address of the collateral contract
     *  @custom:member borrowable The address of the borrow contract
     *  @custom:member recipient The address of the user de-leveraging LP Tokens
     *  @custom:member redeemTokens The amount of CygLP to redeem
     *  @cusotm:member swapData The 1inch swap data byte array to convert LP Tokens to USDC
     */
    struct RedeemLeverageCallData {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 redeemTokens;
        uint256 usdcAmountMin;
        bytes[] swapData;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public immutable override usdc;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public immutable override nativeToken;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IAggregationRouterV4 public immutable override aggregationRouterV4;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    bytes public constant override LOCAL_BYTES = new bytes(0);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the periphery contract. Factory must be deployed on the chain first to get the addresses
     *          of deployers and the wrapped native token (WAVAX, WETH, WFTM, etc.)
     *  @param factory The address of the Cygnus Factory contract on this chain
     *  @param oneInchRouterV4 The address of the 1inch Dex Aggregator Router V4 contract on this chain
     */
    constructor(address factory, address oneInchRouterV4) {
        // Factory
        hangar18 = factory;

        // Assign the native token set at the factory
        nativeToken = ICygnusFactory(factory).nativeToken();

        // Assign the USDC address set at the factoryn
        usdc = ICygnusFactory(factory).usdc();

        // Assign the dex aggregator on this chain
        aggregationRouterV4 = IAggregationRouterV4(oneInchRouterV4);
    }

    /**
     *  @notice Only accept AVAX via fallback from the Wrapped AVAX contract
     */
    receive() external payable {
        /// @custom:error NotNativeTokenSender Avoid receiving anything but Wrapped AVAX
        if (_msgSender() != nativeToken) {
            revert CygnusAltair__NotNativeTokenSender({ poolToken: _msgSender() });
        }
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier checkDeadline Reverts the transaction if the block.timestamp is after deadline
     */
    modifier checkDeadline(uint256 deadline) {
        checkDeadlineInternal(deadline);
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ───────────────────────────────────────────── Internal ────────────────────────────────────────────────  */

    /**
     *  @notice The current block timestamp
     */
    function getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     *  @notice Reverts the transaction if the block.timestamp is after deadline
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function checkDeadlineInternal(uint256 deadline) internal view {
        /// @custom:error TransactionExpired Avoid transacting past deadline
        if (getBlockTimestamp() > deadline) {
            revert CygnusAltair__TransactionExpired({ deadline: deadline });
        }
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return This contract's balance
     */
    function contractBalanceOf(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     *  @dev Compute optimal deposit amount (https://blog.alphaventuredao.io/onesideduniswap/)
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     *  @param _dexSwapFee The fee charged by this dex for a swap (ie Uniswap = 997/1000 = 0.3%)
     *  @return optimal swap amount of tokenA to tokenB to then hold the same proportion of assets as in pool reserves
     */
    function optimalDepositA(uint256 amountA, uint256 reservesA, uint256 _dexSwapFee) internal pure returns (uint256) {
        // Calculate with dex swap fee
        uint256 a = (1000 + _dexSwapFee) * reservesA;
        uint256 b = amountA * 1000 * reservesA * 4 * _dexSwapFee;
        uint256 c = PRBMath.sqrt(a * a + b);
        uint256 d = 2 * _dexSwapFee;
        return (c - a) / d;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice The permit for the terminal contracts
     *  @param amount The amount to allow borrow
     *  @param deadline A time in the future when the allowance expires
     */
    function permitInternal(
        address terminalToken,
        uint256 amount,
        uint256 deadline,
        bytes calldata permitData
    ) internal virtual {
        // If no permit return
        if (permitData.length == 0) return;

        // Decode permit data
        (bool approveMax, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitData, (bool, uint8, bytes32, bytes32));

        // Get approve amount
        uint256 value = approveMax ? type(uint256).max : amount;

        // Validate permit
        ICygnusTerminal(terminalToken).permit(_msgSender(), address(this), value, deadline, v, r, s);
    }

    /**
     *  @notice The borrow permit for the borrow contracts
     *  @param borrowable The address of the Cygnus borrow contract
     *  @param amount The amount to allow borrow
     *  @param deadline A time in the future when the allowance expires
     */
    function borrowPermitInternal(
        address borrowable,
        uint256 amount,
        uint256 deadline,
        bytes calldata permitData
    ) internal virtual {
        // If no borrow permit data return
        if (permitData.length == 0) return;

        // Decode permit data
        (bool approveMax, uint8 v, bytes32 r, bytes32 s) = abi.decode(permitData, (bool, uint8, bytes32, bytes32));

        // Get borrow approve amount
        uint256 value = approveMax ? type(uint256).max : amount;

        // Validate permit
        ICygnusBorrow(borrowable).borrowPermit(_msgSender(), address(this), value, deadline, v, r, s);
    }

    /**
     *  @param borrowable Address of the Cygnus borrow contract
     *  @param token Address of the token we are repaying (USDC)
     *  @param borrower Address of the borrower who is repaying the loan
     *  @param amountMax The max available amount
     */
    function repayAndRefundInternal(
        address borrowable,
        address token,
        address borrower,
        uint256 amountMax
    ) internal virtual {
        // Repay
        uint256 amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Safe transfer USDC to borrowable
        token.safeTransfer(borrowable, amount);

        // Cygnus Borrow with address(0) to update borrow balances
        ICygnusBorrow(borrowable).borrow(borrower, address(0), 0, LOCAL_BYTES);

        // Refund excess
        if (amountMax > amount) {
            uint256 refundAmount = amountMax - amount;
            // Check if token is Avax
            if (token == nativeToken) {
                // Withdraw Avax
                IWAVAX(nativeToken).withdraw(refundAmount);

                // Transfer AVAX
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
    function repayAmountInternal(
        address borrowable,
        uint256 amountMax,
        address borrower
    ) internal virtual returns (uint256 amount) {
        // Accrue interest first to not leave debt after full repay
        ICygnusBorrow(borrowable).accrueInterest();

        // Get borrow balance of borrower
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    // 2 FUNCTIONS: - CONVERT USDC TO LP'S TOKEN0 AND TOKEN1 FOR OPTIMAL LP DEPOSIT
    //              - CONVERT LP TOKEN TO USDC

    /**
     *  @notice Grants allowance from this contract to a dex' router (or just a contract instead of `router`)
     *  @param token The address of the token we are approving
     *  @param router The address of the dex router we are approving (or just a contract)
     *  @param amount The amount to approve
     */
    function approveContract(address token, address router, uint256 amount) internal virtual {
        // If allowance is already higher than `amount` return
        if (IERC20(token).allowance(address(this), router) >= amount) {
            return;
        } else {
            // Approve contract
            token.safeApprove(router, type(uint256).max);
        }
    }

    /**
     *  @notice Creates the swap with 1Inch's AggregatorV4. We pass an extra param `updatedAmount` to eliminate
     *          any slippage from the byte data passed. When calculating the optimal deposit for single sided
     *          liquidity deposit, our calculation can be off for a few mini tokens which don't affect the
     *          data of the aggregation executor, so we pass the tx data as is but update the srcToken amount
     *  @param swapData The data from 1inch `swap` query
     *  @param updatedAmount The balanceOf this contract`s srcToken
     */
    function swapTokens(bytes memory swapData, uint256 updatedAmount) internal virtual returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        (address caller, IAggregationRouterV4.SwapDescription memory desc, bytes memory data) = abi.decode(
            swapData,
            (address, IAggregationRouterV4.SwapDescription, bytes)
        );

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != updatedAmount) desc.amount = updatedAmount;

        // Approve 1Inch Router in `srcToken` if necessary
        approveContract(address(desc.srcToken), address(aggregationRouterV4), desc.amount);

        // Swap `srcToken` to `dstToken` - Aggregator does the necessary minAmount check & we do checks at the end
        // of the leverage/deleverage functions anyways
        (amountOut, , ) = aggregationRouterV4.swap(IAggregationExecutor(caller), desc, data);
    }

    /**
     *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsdc` of USDC
     *  @param lpTokenPair The address of the LP Token
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param swapData Bytes array consisting of 1inch API swap data
     */
    function convertUsdcToLiquidity(
        address lpTokenPair,
        address token0,
        address token1,
        uint256 amountUsdc,
        bytes[] memory swapData
    ) internal virtual returns (uint256 totalAmountA, uint256 totalAmountB) {
        // Placeholder tokenA
        address tokenA;

        // Placeholder tokenB
        address tokenB;

        // ─────────────────────── 1. Check if token0 or token1 is already USDC
        // Check if usdc
        if (token0 == usdc || token1 == usdc) {
            // Assign USDC to tokenA
            (tokenA, tokenB) = token0 == usdc ? (token0, token1) : (token1, token0);
        } else {
            // ─────────────────── 2. Check if token0 or token1 is already native token
            // Check if native token
            if (token0 == nativeToken || token1 == nativeToken) {
                // swap USDc to native token, passing the total amount of USDC we borrowed
                swapTokens(swapData[0], amountUsdc);

                // If token0 is nativeToken, then assign tokenA to token0, else tokenA to token1
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // None are USDC or native token, swap all USDC to this LP Token's token0
                swapTokens(swapData[0], amountUsdc);

                // Assign tokenA to token0 and tokenB to token1
                (tokenA, tokenB) = (token0, token1);
            }
        }
        // ─────────────────────── 3. Calculate optimal deposit amount for an LP Token
        // Get reserves
        (uint112 reserves0, uint112 reserves1, ) = IDexPair(lpTokenPair).getReserves();

        // Get reserves A for calculating optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A - 997/1000 is the swap fee of TraderJoe
        uint256 optimalTokenA = optimalDepositA(contractBalanceOf(tokenA), reservesA, 997);

        // Swap tokenA to tokenB, passing the optimal swap amount to override 1inch `amount` data to account for small
        // differences and avoid slippage
        swapTokens(swapData[1], optimalTokenA);

        // ─────────────────────── 4. Return current balance of token0 and token1
        // Current token0 balance of this contract
        totalAmountA = contractBalanceOf(token0);

        // Current token0 balance of this contract
        totalAmountB = contractBalanceOf(token1);
    }

    /**
     *  @notice Converts an amount of LP Token to USDC. It is called after calling `burn` on a uniswapV2 pair, which
     *          receives amountTokenA of token0 and amountTokenB of token1.
     *  @param amountTokenA The amount of token A to convert to USDC
     *  @param amountTokenB The amount of token B to convert to USDC
     *  @param token0 The address of token0 from the LP Token pair
     *  @param token1 The address of token1 from the LP Token pair
     *  @param swapData Bytes array consisting of 1inch API swap data
     */
    function convertLiquidityToUsdc(
        uint256 amountTokenA,
        uint256 amountTokenB,
        address token0,
        address token1,
        bytes[] memory swapData
    ) internal virtual returns (uint256) {
        // ─────────────────────── 1. Check if token0 or token1 is already USDC
        // If token0 or token1 is USDC then swap opposite
        if (token0 == usdc || token1 == usdc) {
            // Convert the other token to USDC and return
            token0 == usdc ? swapTokens(swapData[0], amountTokenB) : swapTokens(swapData[0], amountTokenA);

            // Explicit return
            return contractBalanceOf(usdc);
        }
        // ─────────────────── 2. Not USDC, swap both to USDC
        // Swap token0 to USDC
        swapTokens(swapData[0], amountTokenA);

        // Swap token1 to USDC
        swapTokens(swapData[1], amountTokenB);

        // USDC balance
        return contractBalanceOf(usdc);
    }

    // Liquidate to USDC

    /**
     *  @notice Liquidates borrower internally and converts LP Tokens to receive back USDC
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus Collateral
     *  @param recipient The address of the recipient of USDC
     *  @param seizeTokens The amount of CygLP seized
     *  @param swapData The 1inch calldata to swap LP back to USDC
     */
    function liquidateToUsdcInternal(
        address lpTokenPair,
        address collateral,
        address recipient,
        uint256 seizeTokens,
        bytes[] calldata swapData
    ) internal virtual returns (uint256 amountUsdc) {
        // Redeem CygLP for LP Token
        uint256 redeemAmount = ICygnusCollateral(collateral).redeem(seizeTokens, recipient, recipient);

        // Get token0
        address token0 = IDexPair(lpTokenPair).token0();

        // Get token1
        address token1 = IDexPair(lpTokenPair).token1();

        // Remove `redeemAmount` of liquidity from the LP Token pair
        IDexPair(lpTokenPair).transferFrom(recipient, lpTokenPair, redeemAmount);

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Convert amountA and amountB to USDC
        amountUsdc = convertLiquidityToUsdc(amountAMax, amountBMax, token0, token1, swapData);

        // Transfer USDC to liquidator
        IERC20(usdc).transfer(recipient, amountUsdc);
    }

    // Burn LP Token and receive token0 and token1

    /**
     *  @notice Removes liquidity from the Dex by calling the pair's `burn` function, receiving tokenA and tokenB
     *  @param lpTokenPair The address of the LP Token
     *  @param borrower The address of the borrower
     *  @param collateral The address of the Cygnus Collateral contract
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @param redeemTokens The amount of CygLP to redeem
     *  @param redeemAmount The amount of LP to redeem
     *  @param token0 The address of token0 from the lpTokenPair from CygnusCollateral
     *  @param token1 The address of token1 from the lpTokenPair from CygnusCollateral
     *  @param swapData Swap params
     */
    function removeLiquidityAndRepay(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 usdcAmountMin,
        uint256 redeemAmount,
        address token0,
        address token1,
        bytes[] memory swapData
    ) internal virtual {
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

        // Repay and refund
        uint256 amountUsdc = convertLiquidityToUsdc(amountAMax, amountBMax, token0, token1, swapData);

        /// @custom:error InsufficientRedeemAmount Avoid if USDC received is less than min
        if (amountUsdc < usdcAmountMin) {
            revert CygnusAltair__InsufficientRedeemAmount({ usdcAmountMin: usdcAmountMin, amountUsdc: amountUsdc });
        }

        // Repay USDC
        repayAndRefundInternal(borrowable, usdc, borrower, amountUsdc);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);
    }

    // Leverage

    /**
     *  @notice Leverage internal function and calls borrow contract
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus collateral address for this lpTokenPair
     *  @param borrowable The address of the Cygnus borrowable address for this collateral
     *  @param usdcAmount The amount of USDC to borrow from borrowable
     *  @param lpAmountMin The minimum amount of LP Tokens to receive (Slippage calculated with our oracle)
     *  @param recipient The address of the recipient
     *  @param swapData The byte array of 1inch calls to leverage USDC into LP tokens
     */
    function leverageInternal(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 usdcAmount,
        uint256 lpAmountMin,
        address recipient,
        bytes[] calldata swapData
    ) internal virtual {
        // Encode data to bytes
        bytes memory cygnusShuttle = abi.encode(
            CygnusShuttle({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                recipient: recipient,
                lpAmountMin: lpAmountMin,
                swapData: swapData
            })
        );

        // Call borrow with encoded data
        ICygnusBorrow(borrowable).borrow(recipient, address(this), usdcAmount, cygnusShuttle);
    }

    // Deleverage

    /**
     *  @notice Main deleverage function
     *  @param collateral The address of the collateral of the lending pool
     *  @param borrowable THe address of the borrowable of the lending pool
     *  @param redeemTokens The amount of Cyg-LP tokens to deleverage
     *  @param lpTokenPair The address of the LP Token
     *  @param usdcAmountMin The minimum amount of USDC to receive by deleveraging
     *  @param swapData The byte array of 1inch calls to deleverage LP Tokens into USDC
     */
    function deleverageInternal(
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        address lpTokenPair,
        uint256 usdcAmountMin,
        bytes[] calldata swapData
    ) internal virtual {
        // Current CygLP exchange rate
        uint256 exchangeRate = ICygnusCollateral(collateral).exchangeRate();

        // Get redeem amount
        uint256 redeemAmount = redeemTokens.mul(exchangeRate);

        // Encode redeem data
        bytes memory redeemData = abi.encode(
            RedeemLeverageCallData({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                recipient: _msgSender(),
                redeemTokens: redeemTokens,
                usdcAmountMin: usdcAmountMin,
                swapData: swapData
            })
        );

        // Flash redeem LP Tokens
        ICygnusCollateral(collateral).flashRedeemAltair(address(this), redeemAmount, redeemData);
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
        // Borrow permit
        borrowPermitInternal(borrowable, amount, deadline, permitData);

        // Borrow amount
        ICygnusBorrow(borrowable).borrow(_msgSender(), recipient, amount, LOCAL_BYTES);
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
        // Amount to repay
        amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Transfer USDC from msg sender to borrow contract
        ICygnusBorrow(borrowable).underlying().safeTransferFrom(_msgSender(), borrowable, amount);

        // Call borrow to update borrower's borrow balance
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
        amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Transfer USDC
        ICygnusBorrow(borrowable).underlying().safeTransferFrom(_msgSender(), borrowable, amount);

        // Liquidate
        seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function liquidateToUsdc(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline,
        bytes[] calldata swapData
    ) external virtual override checkDeadline(deadline) returns (uint256 amountUsdc) {
        // Amount to repay
        uint256 amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Transfer USDC
        ICygnusBorrow(borrowable).underlying().safeTransferFrom(_msgSender(), borrowable, amount);

        // Liquidate and increase liquidator's CygLP amount
        uint256 seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient);

        // Liquidate internally to avoid stack too deep
        amountUsdc = liquidateToUsdcInternal(lpTokenPair, collateral, recipient, seizeTokens, swapData);
    }

    //  LEVERAGE ─────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function leverage(
        address collateral,
        address borrowable,
        uint256 amountUsdcDesired,
        uint256 amountLPMin,
        address recipient,
        uint256 deadline,
        bytes calldata permitData,
        bytes[] calldata swapData
    ) external virtual override checkDeadline(deadline) {
        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Permit (if any)
        borrowPermitInternal(borrowable, amountUsdcDesired, deadline, permitData);

        // Pass LP Token, collateral, borrowable, amount, recipient
        leverageInternal(lpTokenPair, collateral, borrowable, amountUsdcDesired, amountLPMin, recipient, swapData);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairBorrow_O9E(address sender, uint256 borrowAmount, bytes calldata data) external virtual override {
        borrowAmount;

        // Decode data passed from borrow contract
        CygnusShuttle memory cygnusShuttle = abi.decode(data, (CygnusShuttle));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (_msgSender() != cygnusShuttle.borrowable) {
            revert CygnusAltair__MsgSenderNotBorrowable({ sender: _msgSender(), borrowable: cygnusShuttle.borrowable });
        }

        // Token0 Address of the user's deposited LP token
        address token0 = IDexPair(cygnusShuttle.lpTokenPair).token0();

        // Token1 Address of the user's deposited LP Token
        address token1 = IDexPair(cygnusShuttle.lpTokenPair).token1();

        // Converts the borrowed amount of USDC to tokenA and tokenB to mint the LP Token
        (uint256 totalAmountA, uint256 totalAmountB) = convertUsdcToLiquidity(
            cygnusShuttle.lpTokenPair,
            token0,
            token1,
            borrowAmount,
            cygnusShuttle.swapData
        );

        // Transfer token0 to LP Token contract
        token0.safeTransfer(cygnusShuttle.lpTokenPair, totalAmountA);
        // Transfer token1 to LP Token contract
        token1.safeTransfer(cygnusShuttle.lpTokenPair, totalAmountB);
        // Mint the LP Token to the router
        uint256 liquidity = IDexPair(cygnusShuttle.lpTokenPair).mint(address(this));

        /// @custom:error InsufficientLPTokenAmount Avoid if LP Token amount received is less than min
        if (liquidity < cygnusShuttle.lpAmountMin) {
            revert CygnusAltair__InsufficientLPTokenAmount({
                lpAmountMin: cygnusShuttle.lpAmountMin,
                liquidity: liquidity
            });
        }

        // Check allowance and deposit the LP token in the collateral contract
        approveContract(cygnusShuttle.lpTokenPair, cygnusShuttle.collateral, liquidity);
        // Mint CygLP to the recipient
        ICygnusCollateral(cygnusShuttle.collateral).deposit(liquidity, cygnusShuttle.recipient);
    }

    //  DELEVERAGE ───────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function deleverage(
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 usdcAmountMin,
        uint256 deadline,
        bytes calldata permitData,
        bytes[] calldata swapData
    ) external virtual override checkDeadline(deadline) {
        /// @custom:error InvalidRedeemAmount Avoid redeeming 0 tokens
        if (redeemTokens <= 0) {
            revert CygnusAltair__InvalidRedeemAmount({ redeemer: _msgSender(), redeemTokens: redeemTokens });
        }

        // Get collateral
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Permit data
        permitInternal(collateral, redeemTokens, deadline, permitData);

        // Internal deleverage
        deleverageInternal(collateral, borrowable, redeemTokens, lpTokenPair, usdcAmountMin, swapData);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairRedeem_u91A(
        address sender,
        uint256 redeemAmount,
        address token0,
        address token1,
        bytes calldata data
    ) external virtual override {
        // Decode deleverage shuttle data
        RedeemLeverageCallData memory redeemData = abi.decode(data, (RedeemLeverageCallData));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin });
        }
        /// @custom:error MsgSenderNotCollateral Avoid if the msg sender is not Cygnus collateral contract
        else if (_msgSender() != redeemData.collateral) {
            revert CygnusAltair__MsgSenderNotCollateral({ sender: _msgSender(), collateral: redeemData.collateral });
        }

        // Remove liquidity from pool and repay to borrowable
        removeLiquidityAndRepay(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.borrowable,
            redeemData.redeemTokens,
            redeemData.usdcAmountMin,
            redeemAmount,
            token0,
            token1,
            redeemData.swapData
        );
    }
}
