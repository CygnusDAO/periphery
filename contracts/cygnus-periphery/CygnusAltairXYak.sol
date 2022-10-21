// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusAltairX } from "./interfaces/ICygnusAltairX.sol";
import { Context } from "./utils/Context.sol";

// Interfaces
import { IERC20 } from "./interfaces/core/IERC20.sol";
import { IWAVAX } from "./interfaces/core/IWAVAX.sol";
import { IDexPair } from "./interfaces/core/IDexPair.sol";
import { IYakRouter } from "./interfaces/IYakRouter.sol";
import { ICygnusBorrow } from "./interfaces/core/ICygnusBorrow.sol";
import { ICygnusFactory } from "./interfaces/core/ICygnusFactory.sol";
import { ICygnusTerminal } from "./interfaces/core/ICygnusTerminal.sol";
import { ICygnusCollateral } from "./interfaces/core/ICygnusCollateral.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { CygnusPoolAddress } from "./libraries/CygnusPoolAddress.sol";

/**
 *  @title  CygnusAltairX Periphery contract to interact with Cygnus Core contracts
 *  @author CygnusDAO
 *  @notice The router contract is used to interact with Cygnus core using YieldYak's on-chain aggregator. When doing 
 *          leverage, the router is in charge of receiving USDC from the core borrowable arm, and converting it 
 *          to more LP Tokens. When de-leveraging a position, the router contract receives the LP Token amount to 
 *          deleverage, and converts them back to USDC to repay part of the position to the borrowable arm, decreasing 
 *          the borrower`s debt. The main functions in this contract allow for:
 *              - Minting CygLP and CygUSD (Pool tokens for collateral and borrowable respectively)
 *              - Redeeming CygLP and CygUSD
 *              - Borrowing USDC
 *              - Repaying USDC
 *              - Liquidating user's with USDC (pay back USDC, receive CygLP + bonus liquidation reward)
 *              - Liquidating user's and converting to USDC (pay back USDC, receive CygLP + bonus equivalent in USDC)
 *              - Leveraging LP tokens
 *              - Deleveraging LP Tokens
 */
contract CygnusAltairXYak is ICygnusAltairX, Context {
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
     *  @custom:member borrow The address of the Cygnus borrow contract
     *  @custom:member recipient The address of the recipient
     */
    struct CygnusShuttle {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 lpAmountMin;
    }

    /**
     *  @custom:struct RedeemLeverageCallData Encoded bytes passed to Cygnus Collateral contract for leverage redeem
     *  @custom:member collateral The address of the collateral contract
     *  @custom:member borrowable The address of the borrow contract
     *  @custom:member recipient The address of the user de-leveraging LP Tokens
     *  @custom:member redeemTokens The amount of CygLP to redeem
     *  @custom:member redeemAmount The amount of LP to redeem
     */
    struct RedeemLeverageCallData {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 redeemTokens;
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
    bytes public constant override LOCAL_BYTES = new bytes(0);

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IYakRouter public constant override YAK_ROUTER = IYakRouter(0xC4729E56b831d74bBc18797e0e17A295fA77488c);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the periphery contract. Factory must be deployed on the chain first to get the addresses
     *          of deployers and the wrapped native token (WAVAX, WETH, WFTM, etc.)
     *  @param factory The address of the Factory contract
     */
    constructor(address factory) {
        // Assign factory
        hangar18 = factory;

        // Address of nativeToken in this chain
        nativeToken = ICygnusFactory(factory).nativeToken();

        // Address of USDC in this chain
        usdc = ICygnusFactory(factory).usdc();
    }

    /**
     *  @notice Only accept AVAX via fallback from the Wrapped AVAX contract
     */
    receive() external payable {
        /// @custom:error NotNativeTokenSender Avoid receiving anything but Wrapped AVAX
        if (_msgSender() != nativeToken) {
            revert CygnusAltair__NotNativeTokenSender(_msgSender());
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
     *  @notice Reverts the transaction if the block.timestamp is after deadline
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function checkDeadlineInternal(uint256 deadline) internal view {
        /// @custom:error TransactionExpired Avoid transacting past deadline
        if (getBlockTimestamp() > deadline) {
            revert CygnusAltair__TransactionExpired(deadline);
        }
    }

    /**
     *  @notice The current block timestamp
     */
    function getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     *  @dev Compute optimal deposit amount helper (https://blog.alphaventuredao.io/onesideduniswap/)
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     *  @param _dexSwapFee The fee charged by this dex for a swap (ie Uniswap = 997/1000 = 0.3%)
     *  @return Optimal amount of tokenA to swap to tokenB to keep reserves ratio constant
     */
    function optimalDepositA(
        uint256 amountA,
        uint256 reservesA,
        uint256 _dexSwapFee
    ) internal pure returns (uint256) {
        // Calculate with dex swap fee
        uint256 a = (1000 + _dexSwapFee) * reservesA;
        uint256 b = amountA * 1000 * reservesA * 4 * _dexSwapFee;
        uint256 c = PRBMath.sqrt(a * a + b);
        uint256 d = 2 * _dexSwapFee;
        return (c - a) / d;
    }

    /**
     *  @notice Checks the `token` balance of this contract
     *  @param token The token to view balance of
     *  @return This contract's current balance of `token`
     */
    function contractBalanceOf(address token) private view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
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
        bytes memory permitData
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
        bytes memory permitData
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
    function contractApprove(
        address token,
        address router,
        uint256 amount
    ) internal {
        if (IERC20(token).allowance(address(this), router) >= amount) {
            return;
        } else {
            token.safeApprove(router, type(uint256).max);
        }
    }

    /**
     *  @notice Swaps tokenIn to tokenOut given an `amount` of tokenIn
     *  @param tokenIn The address of the token we are swapping
     *  @param tokenOut The address of the token we are receiving
     *  @param amountIn The amount of tokenIn we are swapping
     */
    function swapTokensInternal(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal virtual {
        // adapters
        uint8[] memory adapters = new uint8[](7);

        // These Adapters should be fixed so no need to update again. We pass the most common adapters used
        // by YieldYak's router to cover most scenarios and reduce gas costs significantly. We cover most popular
        // Dexes on Avalanche (Joe, Pangolin, Sushi) + stablecoins (Platypus/Curve/Woofi) + WAVAX (GMX)
        adapters[0] = 0; // TraderJoe
        adapters[1] = 1; // Pangolin
        adapters[2] = 2; // Sushiswap
        adapters[3] = 8; // Platypus
        adapters[4] = 17; // Curve
        adapters[5] = 19; // WOOFI
        adapters[6] = 22; // GMX

        // Query adapters and return the best adapter to swap `tokenIn` to `tokenOut`
        IYakRouter.Query memory query = YAK_ROUTER.queryNoSplit(amountIn, tokenIn, tokenOut, adapters);

        // Approve adapter in tokenIn if necessary (explicitly returns if current allowance of router > amountIn)
        contractApprove(tokenIn, query.adapter, amountIn);

        // Send `amountIn` of `tokenIn` to the adapter
        tokenIn.safeTransfer(query.adapter, amountIn);

        // Swap `amountIn` and receive `amountOut`
        IYakRouter(query.adapter).swap(amountIn, query.amountOut, tokenIn, tokenOut, address(this));
    }

    /**
     *  @notice This function gets called after calling `borrow` on Borrow contract and having `amountUsdc` of USDC
     *  @param lpTokenPair The address of the LP Token
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountUsdc USDC amount to convert to token0 and token1 of an LP Token
     *  @return totalAmount0 Amount of token0 we have after converting amountUsdc
     *  @return totalAmount1 Amount of token1 we have after converting amountUsdc
     */
    function convertUsdcToLiquidity(
        address lpTokenPair,
        address token0,
        address token1,
        uint256 amountUsdc
    ) internal returns (uint256 totalAmount0, uint256 totalAmount1) {
        // ─────────────────────── 1. Check if token0 or token1 is already USDC
        // Placeholder tokenA
        address tokenA;

        // Placeholder tokenB
        address tokenB;

        // If usdc, then swap from pool itself
        if (token0 == usdc || token1 == usdc) {
            // If token0 is USDC, then assign tokenA to token0, else tokenA to token1
            (tokenA, tokenB) = token0 == usdc ? (token0, token1) : (token1, token0);
        } else {
            // swap USDc to native token
            swapTokensInternal(usdc, nativeToken, amountUsdc);

            // ─────────────────── 2. Check if token0 or token1 is already AVAX
            if (token0 == nativeToken || token1 == nativeToken) {
                // If token0 is nativeToken, then assign tokenA to token0, else tokenA to token1
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // None are USDC or native token, swap all native token to token0 to calculate optimal deposit
                swapTokensInternal(nativeToken, token0, contractBalanceOf(nativeToken));

                // Assign tokenA to token0 and tokenB to token1
                (tokenA, tokenB) = (token0, token1);
            }
        }
        // ─────────────────────── 3. Calculate optimal deposit amount for an LP Token
        // prettier-ignore
        (uint112 reserves0, uint112 reserves1, ) = IDexPair(lpTokenPair).getReserves();

        // Get reserves A for calculating optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A - 997/1000 is the swap fee of TraderJoe
        uint256 swapAmount = optimalDepositA(contractBalanceOf(tokenA), reservesA, 997);

        // Swap optimal amount of tokenA to tokenB
        swapTokensInternal(tokenA, tokenB, swapAmount);

        // ─────────────────────── 4. Send token0 and token1 to lp token pair to call `mint` on next function
        // Total Amount of token0
        totalAmount0 = contractBalanceOf(token0);

        // Total Amount of token1
        totalAmount1 = contractBalanceOf(token1);
    }

    /**
     *  @notice Converts an amount of LP Token to USDC. It is called after calling `burn` on a uniswapV2 pair, which
     *          receives amountTokenA of token0 and amountTokenB of token1.
     *  @param amountTokenA The amount of token A to convert to USDC
     *  @param amountTokenB The amount of token B to convert to USDC
     *  @param token0 The address of token0 from the LP Token pair
     *  @param token1 The address of token1 from the LP Token pair
     *  @return amountUsdc Amount of USDC this contract holds after converting the LP Token amount to USDC
     */
    function convertLiquidityToUsdc(
        uint256 amountTokenA,
        uint256 amountTokenB,
        address token0,
        address token1
    ) internal returns (uint256 amountUsdc) {
        // ─────────────────────── 1. Check if token0 or token1 is already USDC

        // If token0 or token1 is USDC then swap opposite and return
        if (token0 == usdc || token1 == usdc) {
            // Convert the other token to USDC and return
            token0 == usdc
                ? swapTokensInternal(token1, usdc, amountTokenB)
                : swapTokensInternal(token0, usdc, amountTokenA);

            // Explicit return
            return contractBalanceOf(usdc);
        }
        // Not USDC, check for nativeToken
        else {
            // ─────────────────── 2. Not USDC, swap to native token

            if (token0 == nativeToken || token1 == nativeToken) {
                // Convert token0 or token1 to nativeToken
                token0 == nativeToken
                    ? swapTokensInternal(token1, nativeToken, amountTokenB)
                    : swapTokensInternal(token0, nativeToken, amountTokenA);
            }
            // None are USDC or nativeToken, convert all to nativeToken
            else {
                // Swap token0 to nativeToken
                swapTokensInternal(token0, nativeToken, amountTokenA);

                // Swap token 1 to nativeToken
                swapTokensInternal(token1, nativeToken, amountTokenB);
            }
        }

        // ─────────────────────── 3. Swap all nativeTokens to USDC

        // Convert nativeToken to USDc due to liquidity concentrated in USDc
        swapTokensInternal(nativeToken, usdc, contractBalanceOf(nativeToken));

        // Total Amount USDC
        amountUsdc = contractBalanceOf(usdc);
    }

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
     */
    function removeLiquidityAndRepay(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 redeemAmount,
        address token0,
        address token1
    ) internal {
        // Transfer LP Token back to LP Token's contract to remove liquidity
        IDexPair(lpTokenPair).transfer(lpTokenPair, redeemAmount);

        // Burn and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        /// @custom:error InsufficientBurnAmountA Avoid invalid burn amount of token A
        if (amountAMax < 0) {
            revert CygnusAltair__InsufficientBurnAmountA(amountAMax);
        }
        /// @custom:error InsufficientBurnAmountB Avoid invalid burn amount of token B
        else if (amountBMax < 0) {
            revert CygnusAltair__InsufficientBurnAmountB(amountBMax);
        }

        // Repay and refund
        uint256 amountUsdc = convertLiquidityToUsdc(amountAMax, amountBMax, token0, token1);

        // Repay USDC
        repayAndRefundInternal(borrowable, usdc, borrower, amountUsdc);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);
    }

    /**
     *  @notice Leverage internal function and calls borrow contract
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus collateral address for this lpTokenPair
     *  @param borrowable The address of the Cygnus borrowable address for this collateral
     *  @param usdcAmount The amount of USDC to borrow from borrowable
     *  @param lpAmountMin The minimum amount of LP Tokens to receive (Slippage calculated with our oracle)
     *  @param recipient The address of the recipient
     */
    function leverageInternal(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 usdcAmount,
        uint256 lpAmountMin,
        address recipient
    ) internal virtual {
        // Encode data to bytes
        bytes memory cygnusShuttle = abi.encode(
            CygnusShuttle({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                recipient: recipient,
                lpAmountMin: lpAmountMin
            })
        );

        // Call borrow with encoded data
        ICygnusBorrow(borrowable).borrow(recipient, address(this), usdcAmount, cygnusShuttle);
    }

    /**
     * @notice Main deleverage function
     * @param collateral The address of the collateral of the lending pool
     * @param redeemTokens The amount of tokens to redeem
     * @param lpTokenPair The address of the LP Token
     */
    function deleverageInternal(
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        address lpTokenPair
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
                redeemTokens: redeemTokens
            })
        );

        // Flash redeem
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
        bytes memory permitData
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
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amountUsdc) {
        // Amount to repay
        uint256 amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Transfer USDC
        ICygnusBorrow(borrowable).underlying().safeTransferFrom(_msgSender(), borrowable, amount);

        // Liquidate and increase liquidator's CygLP amount
        uint256 seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient);

        // Get Collateral
        address collateral = ICygnusBorrow(borrowable).collateral();

        // Redeem CygLP for LP Token
        uint256 redeemAmount = ICygnusCollateral(collateral).redeem(seizeTokens, recipient, recipient);

        // Get LP Token pair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Get token0
        address token0 = IDexPair(lpTokenPair).token0();

        // Get token1
        address token1 = IDexPair(lpTokenPair).token1();

        // Remove `redeemAmount` of liquidity from the LP Token pair
        IDexPair(lpTokenPair).transferFrom(recipient, lpTokenPair, redeemAmount);

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Convert amountA and amountB to USDC
        amountUsdc = convertLiquidityToUsdc(amountAMax, amountBMax, token0, token1);

        // Transfer USDC to liquidator
        IERC20(usdc).transfer(recipient, amountUsdc);
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
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Permit (if any)
        borrowPermitInternal(borrowable, amountUsdcDesired, deadline, permitData);

        // Pass LP Token, collateral, borrowable, amount, recipient
        leverageInternal(lpTokenPair, collateral, borrowable, amountUsdcDesired, amountLPMin, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairBorrow_O9E(
        address sender,
        uint256 borrowAmount,
        bytes calldata data
    ) external override {
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
        (uint256 totalAmount0, uint256 totalAmount1) = convertUsdcToLiquidity(
            cygnusShuttle.lpTokenPair,
            token0,
            token1,
            borrowAmount
        );

        // Transfer token0 to LP Token contract
        token0.safeTransfer(cygnusShuttle.lpTokenPair, totalAmount0);
        // Transfer token1 to LP Token contract
        token1.safeTransfer(cygnusShuttle.lpTokenPair, totalAmount1);
        // Mint the LP Token to the router
        uint256 liquidity = IDexPair(cygnusShuttle.lpTokenPair).mint(address(this));

        // Check for amount min requested
        require(liquidity >= cygnusShuttle.lpAmountMin, "Insufficient liquidity");

        // Check allowance and deposit the LP token in the collateral contract
        contractApprove(cygnusShuttle.lpTokenPair, cygnusShuttle.collateral, liquidity);

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
        uint256 deadline,
        bytes calldata permitData
    ) external override checkDeadline(deadline) {
        /// @custom:error InvalidRedeemAmount Avoid redeeming 0 tokens
        if (redeemTokens <= 0) {
            revert CygnusAltair__InvalidRedeemAmount({ redeemer: _msgSender(), redeemTokens: redeemTokens });
        }

        // Get collateral
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Permit data
        permitInternal(collateral, redeemTokens, deadline, permitData);

        // Internal deleverage
        deleverageInternal(collateral, borrowable, redeemTokens, lpTokenPair);
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
    ) external override {
        redeemAmount;

        // Decode shuttle
        RedeemLeverageCallData memory redeemData = abi.decode(data, (RedeemLeverageCallData));

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-ine
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
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
            redeemAmount,
            token0,
            token1
        );
    }
}
