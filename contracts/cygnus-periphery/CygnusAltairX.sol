// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusAltairX, ICygnusAltairCall } from "./interfaces/ICygnusAltairX.sol";
import { Context } from "./utils/Context.sol";

// Interfaces
import { ICygnusBorrow } from "./interfaces/core/ICygnusBorrow.sol";
import { ICygnusCollateral } from "./interfaces/core/ICygnusCollateral.sol";
import { ICygnusTerminal } from "./interfaces/core/ICygnusTerminal.sol";
import { IWAVAX } from "./interfaces/core/IWAVAX.sol";
import { IDexPair } from "./interfaces/core/IDexPair.sol";
import { IErc20 } from "./interfaces/core/IErc20.sol";
import { IDexRouter02 } from "./interfaces/core/IDexRouter.sol";
import { ICygnusFactory } from "./interfaces/core/ICygnusFactory.sol";
import { IYakAdapter } from "./interfaces/IYakAdapter.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { CygnusPoolAddress } from "./libraries/CygnusPoolAddress.sol";

/**
 *  @title  CygnusAltair Periphery contract to interact with Cygnus Core contracts
 *  @author CygnusDAO
 *  @notice This contract details the functions for:
 *          - Minting CygLP and CygDAI
 *          - Redeeming CygLP and CygDAI
 *          - Borrowing DAI
 *          - Repaying DAI
 *          - Liquidating user's with DAI (pay back DAI, receive CygLP + bonus liquidation reward)
 *          - Liquidating user's and converting to DAI (pay back DAI, receive CygLP + bonus equivalent in DAI)
 *          - Leveraging LP tokens
 *          - Deleveraging LP Tokens
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
     *  @custom:struct CygnusShuttle Callback addresses for the leverage function
     *  @custom:member lp The address of the LP Token
     *  @custom:member collateral The address of the Cygnus collateral contract
     *  @custom:member borrow The address of the Cygnus borrow contract
     *  @custom:member recipient The address of the recipient
     */
    struct CygnusShuttle {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
    }

    /**
     *  @custom:struct RedeemLeverageCallData Encoded bytes passed to Cygnus contracts containing leverage data
     *  @custom:member collateral The address of the collateral contract
     *  @custom:member borrowable The address of the borrow contract
     *  @custom:member recipient The address of the user leveraging LP Tokens
     *  @custom:member redeemTokens The amount of CygLP to redeem
     *  @custom:member redeemAmount The amount of LP to redeem
     */
    struct RedeemLeverageCallData {
        address lpTokenPair;
        address collateral;
        address borrowable;
        address recipient;
        uint256 redeemTokens;
        uint256 redeemAmount;
    }

    struct Query {
        address adapter;
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

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
    address public immutable override dai;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    address public constant override USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    /**
     *  @inheritdoc ICygnusAltairX
     */
    bytes public constant override LOCAL_BYTES = new bytes(0);

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IYakAdapter public constant override YAK_ROUTER = IYakAdapter(0xC4729E56b831d74bBc18797e0e17A295fA77488c);

    /**
     *  @notice Adapters: TraderJoe for JOE pools, Sushi for Sushi, Pangolin for PNG, Platypus for stablecoins + Bonus
     */
    uint8[] public adapters = [0, 1, 4, 25, 28];

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

        // Address of DAI in this chain
        dai = ICygnusFactory(factory).dai();
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
     *  @param deadline A time in the future when the transaction expires
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
     *  @dev Compute optimal deposit amount helper.
     *  @param amountA amount of token A desired to deposit
     *  @param reservesA Reserves of token A from the DEX
     *  @param _dexSwapFee The fee charged by this dex for a swap (ie Uniswap = 997/1000 = 0.3%)
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
     *  @return This contract's balance
     */
    function contractBalanceOf(address token) private view returns (uint256) {
        return IErc20(token).balanceOf(address(this));
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
     *  @param token Address of the token we are repaying (DAI)
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

        // Safe transfer DAI to borrowable
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
        ICygnusBorrow(borrowable).accrueInterest();

        // Get borrow balance of borrower
        uint256 borrowedAmount = ICygnusBorrow(borrowable).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    // 2 FUNCTIONS: - CONVERT DAI TO LP'S TOKEN0 AND TOKEN1 FOR OPTIMAL LP DEPOSIT
    //              - CONVERT LP TOKEN TO DAI

    /**
     *  @notice Grants allowance to the dex' router to handle our rewards
     *  @param token The address of the token we are approving
     *  @param amount The amount to approve
     */
    function approveDexRouter(
        address token,
        address router,
        uint256 amount
    ) internal {
        if (IErc20(token).allowance(address(this), router) >= amount) {
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
        uint256 amountIn,
        uint8[] memory opts
    ) internal virtual {
        // Query adapters
        IYakAdapter.Query memory query = YAK_ROUTER.queryNoSplit(amountIn, tokenIn, tokenOut, opts);

        // Approve adapter in router
        approveDexRouter(tokenIn, query.adapter, type(uint256).max);

        // Send `amountIn` of `tokenIn` to the adapter
        tokenIn.safeTransfer(query.adapter, amountIn);

        // Swap `amountIn` and receive `amountOut`
        IYakAdapter(query.adapter).swap(amountIn, query.amountOut, tokenIn, tokenOut, address(this));
    }

    /**
     *  @notice IMPORTANT
     *          USDC is used as bridge token to convert to DAI. Avalanche liquidity is very highly concentrated in USDc.
     *          Converting from LP token to USDc saves a lot for borrowers, even while using dex aggregators.
     *  @notice This function gets called after calling `borrow` on CygnusBorrow contract and having `amountDai` of DAI
     *  @param lpTokenPair The address of the LP Token
     *  @param token0 The address of token0 from the LP Token
     *  @param token1 The address of token1 from the LP Token
     *  @param amountDai DAI amount to convert to token0 and token1 of an LP Token
     */
    function convertDAIToTokens(
        address lpTokenPair,
        address token0,
        address token1,
        uint256 amountDai
    ) internal returns (uint256 totalAmountA, uint256 totalAmountB) {
        // Create adapter options
        uint8[] memory opts = new uint8[](5);

        // Assign adapters to query, hardcode for gas savings always max 5
        for (uint256 i = 0; i < 5; i++) {
            opts[i] = adapters[i];
        }

        // ─────────────────────── 1. Check if token0 or token1 is already DAI

        // Placeholder tokenA
        address tokenA;

        // Placeholder tokenB
        address tokenB;

        // If dai, then pool has enough liquidity to swap at minimal cost
        if (token0 == dai || token1 == dai) {
            // If token0 is dai, then assign tokenA to token0, else tokenA to token1
            (tokenA, tokenB) = token0 == dai ? (token0, token1) : (token1, token0);
        } else {
            // Not DAI, swap dai to USDc.e for lower slippage in Avalanche
            swapTokensInternal(dai, USDC, amountDai, opts);

            // swap USDc to native token
            swapTokensInternal(USDC, nativeToken, contractBalanceOf(USDC), opts);
            // ─────────────────── 2. Check if token0 or token1 is already AVAX

            if (token0 == nativeToken || token1 == nativeToken) {
                // If token0 is nativeToken, then assign tokenA to token0, else tokenA to token1
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // None are DAI or native token, swap all native token to token0 to calculate optimal deposit
                swapTokensInternal(nativeToken, token0, contractBalanceOf(nativeToken), opts);

                // Assign tokenA to token0 and tokenB to token1
                (tokenA, tokenB) = (token0, token1);
            }
        }
        // ─────────────────────── 3. Calculate optimal deposit amount for an LP Token

        // prettier-ignore
        (uint256 reserves0, uint256 reserves1, /* BlockTimestamp */) = IDexPair(lpTokenPair).getReserves();

        // Get reserves A for calculating optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A - 997/1000 is the swap fee of TraderJoe
        uint256 swapAmount = optimalDepositA(contractBalanceOf(tokenA), reservesA, 997);

        // Swap optimal amount of tokenA to tokenB
        swapTokensInternal(tokenA, tokenB, swapAmount, opts);

        // ─────────────────────── 4. Send token0 and token1 to lp token pair to call `mint` on next function

        // Total Amount A
        totalAmountA = contractBalanceOf(token0);

        // Total Amount B
        totalAmountB = contractBalanceOf(token1);
    }

    /**
     *  @notice IMPORTANT
     *          USDC is used as bridge token to convert to DAI. Avalanche liquidity is very highly concentrated in USDc.
     *          Converting from LP token to USDc to DAI saves a lot for borrowers, even while using dex aggregators.
     *  @notice Converts an amount of LP Token to DAI. It is called after calling `burn` on a uniswapV2 pair, which
     *          receives amountTokenA of token0 and amountTokenB of token1.
     *  @param amountTokenA The amount of token A to convert to DAI
     *  @param amountTokenB The amount of token B to convert to DAI
     *  @param token0 The address of token0 from the LP Token pair
     *  @param token1 The address of token1 from the LP Token pair
     */
    function convertLPTokenToDAI(
        uint256 amountTokenA,
        uint256 amountTokenB,
        address token0,
        address token1
    ) internal returns (uint256 amountDAI) {
        // Create adapter options
        uint8[] memory opts = new uint8[](5);

        // Assign adapters to query, hardcode for gas savings always max 5
        for (uint256 i = 0; i < 5; i++) {
            opts[i] = adapters[i];
        }

        // ─────────────────────── 1. Check if token0 or token1 is already DAI

        // If token0 or token1 is dai then swap with the pool
        if (token0 == dai || token1 == dai) {
            // Convert the other token to DAI and return
            token0 == dai
                ? swapTokensInternal(token1, dai, amountTokenB, opts)
                : swapTokensInternal(token0, dai, amountTokenA, opts);

            // Explicit return
            return contractBalanceOf(dai);
        }
        // Not dai, check for nativeToken
        else {
            // ─────────────────── 3. Check if token0 or token1 is already nativeToken

            if (token0 == nativeToken || token1 == nativeToken) {
                // Avoid converting usdc to avax and back to usdc
                if (token0 != USDC || token1 != USDC) {
                    // Convert token0 or token1 to nativeToken
                    token0 == nativeToken
                        ? swapTokensInternal(token1, nativeToken, amountTokenB, opts)
                        : swapTokensInternal(token0, nativeToken, amountTokenA, opts);
                }
            }
            // None are DAI or nativeToken, convert all to nativeToken
            else {
                // Swap token0 to nativeToken
                swapTokensInternal(token0, nativeToken, amountTokenA, opts);

                // Swap token 1 to nativeToken
                swapTokensInternal(token1, nativeToken, amountTokenB, opts);
            }
        }

        // ─────────────────────── 4. Swap all nativeTokens to DAI */

        // Convert nativeToken to USDc due to liquidity concentrated in USDc
        swapTokensInternal(nativeToken, USDC, contractBalanceOf(nativeToken), opts);

        // Swap USDC to DAI checking Platypus adapter
        swapTokensInternal(USDC, dai, contractBalanceOf(USDC), opts);

        // Total Amount DAI
        amountDAI = contractBalanceOf(dai);
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
        ICygnusCollateral(lpTokenPair).transfer(lpTokenPair, redeemAmount);

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
        uint256 amountDai = convertLPTokenToDAI(amountAMax, amountBMax, token0, token1);

        // Repay DAI
        repayAndRefundInternal(borrowable, dai, borrower, amountDai);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);
    }

    /**
     *  @notice Leverage internal function and calls borrow contract
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus collateral address for this lpTokenPair
     *  @param borrowable The address of the Cygnus borrowable address for this collateral
     *  @param leverageAmount The amount to borrow from borrowable
     *  @param recipient The address of the recipient
     */
    function leverageInternal(
        address lpTokenPair,
        address collateral,
        address borrowable,
        uint256 leverageAmount,
        address recipient
    ) internal virtual {
        // Encode data to bytes
        bytes memory cygnusShuttle = abi.encode(
            CygnusShuttle({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: borrowable,
                recipient: recipient
            })
        );

        // Call borrow with encoded data
        ICygnusBorrow(borrowable).borrow(recipient, address(this), leverageAmount, cygnusShuttle);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function borrow(
        address borrowable,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override checkDeadline(deadline) {
        // Borrow permit
        borrowPermitInternal(borrowable, amount, deadline, permitData);

        // Borrow amount
        ICygnusBorrow(borrowable).borrow(_msgSender(), recipient, amount, LOCAL_BYTES);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  MINT CYGLP / CYGDAI ──────────────────────────
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

        // Transfer DAI from msg sender to borrow contract
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

        // Transfer DAI
        ICygnusBorrow(borrowable).underlying().safeTransferFrom(_msgSender(), borrowable, amount);

        // Liquidate
        seizeTokens = ICygnusBorrow(borrowable).liquidate(borrower, recipient);
    }

    /**
     *  @notice Function used for testing, should or should not be used
     *  @inheritdoc ICygnusAltairX
     */
    function liquidateToDai(
        address borrowable,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amountDai) {
        // Amount to repay
        uint256 amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Transfer DAI
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

        // Convert amountA and amountB to DAI
        amountDai = convertLPTokenToDAI(amountAMax, amountBMax, token0, token1);

        // Transfer DAI to liquidator
        IErc20(dai).transfer(recipient, amountDai);
    }

    //  LEVERAGE ─────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function leverage(
        address collateral,
        uint256 amountDAIDesired,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Get the borrow contract for the permit
        address borrowable = ICygnusCollateral(collateral).borrowable();

        // Permit (if any)
        borrowPermitInternal(borrowable, amountDAIDesired, deadline, permitData);

        // Pass LP Token, collateral, borrowable, amount, recipient
        leverageInternal(lpTokenPair, collateral, borrowable, amountDAIDesired, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function altairBorrow_O9E(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external override {
        // Decode data passed from borrow contract
        CygnusShuttle memory cygnusShuttle = abi.decode(data, (CygnusShuttle));

        // Get Cygnus borrow address for this LP Token pair
        address borrowable = cygnusShuttle.borrowable;

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin, borrower: borrower });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (_msgSender() != borrowable) {
            revert CygnusAltair__MsgSenderNotBorrowable({ sender: _msgSender(), borrowable: borrowable });
        }

        // Token0 Address of the user's deposited LP token
        address token0 = IDexPair(cygnusShuttle.lpTokenPair).token0();

        // Token1 Address of the user's deposited LP Token
        address token1 = IDexPair(cygnusShuttle.lpTokenPair).token1();

        // Converts the borrowed amount of DAI to tokenA and tokenB to mint the LP Token
        (uint256 totalAmountA, uint256 totalAmountB) = convertDAIToTokens(
            cygnusShuttle.lpTokenPair,
            token0,
            token1,
            borrowAmount
        );

        /* 
        Approve dex router in token0
        AltairHelper.approveDexRouter(token0, address(DEX_ROUTER), type(uint256).max);

        // Approve dex router in token1
        AltairHelper.approveDexRouter(token1, address(DEX_ROUTER), type(uint256).max);

        // Add liquidity to DEX and mint LP Token
        DEX_ROUTER.addLiquidity(
            token0,
            token1,
            totalAmountA,
            totalAmountB,
            0,
            0,
            cygnusShuttle.collateral,
            block.timestamp
        );
         */

        // Transfer token0 to LP Token contract
        token0.safeTransfer(cygnusShuttle.lpTokenPair, totalAmountA);
        // Transfer token1 to LP Token contract
        token1.safeTransfer(cygnusShuttle.lpTokenPair, totalAmountB);
        // Mint the LP Token to the router
        uint256 liquidity = IDexPair(cygnusShuttle.lpTokenPair).mint(address(this));

        // Check allowance and deposit the LP token in the collateral contract
        approveDexRouter(cygnusShuttle.lpTokenPair, cygnusShuttle.collateral, liquidity);
        // Mint CygLP to the recipient
        ICygnusCollateral(cygnusShuttle.collateral).deposit(liquidity, cygnusShuttle.recipient);
    }

    //  DELEVERAGE ───────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function deleverage(
        address collateral,
        uint256 redeemTokens,
        uint256 deadline,
        bytes calldata permitData
    ) external override checkDeadline(deadline) {
        // Get collateral
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        /// @custom:error InvalidRedeemAmount Avoid redeeming 0 tokens
        if (redeemTokens <= 0) {
            revert CygnusAltair__InvalidRedeemAmount({ redeemer: _msgSender(), redeemTokens: redeemTokens });
        }

        // Current CygLP exchange rate
        uint256 exchangeRate = ICygnusCollateral(collateral).exchangeRate();

        // Get redeem amount
        uint256 redeemAmount = redeemTokens.mul(exchangeRate);

        // Permit data
        permitInternal(collateral, redeemTokens, deadline, permitData);

        // Encode redeem data
        bytes memory redeemData = abi.encode(
            RedeemLeverageCallData({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: ICygnusCollateral(collateral).borrowable(),
                recipient: _msgSender(),
                redeemTokens: redeemTokens,
                redeemAmount: redeemAmount
            })
        );

        // Flash redeem
        ICygnusCollateral(collateral).flashRedeemAltair(address(this), redeemAmount, redeemData);
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

        // Get collateral contract
        address cygnusCollateralContract = redeemData.collateral;

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        // solhint-disable
        if (sender != address(this)) {
            revert CygnusAltair__MsgSenderNotRouter({
                sender: sender,
                origin: tx.origin,
                borrower: redeemData.recipient
            });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (_msgSender() != cygnusCollateralContract) {
            revert CygnusAltair__MsgSenderNotCollateral({ sender: _msgSender(), collateral: cygnusCollateralContract });
        }
        //solhint-enable

        // Remove liquidity from pool and repay to borrowable
        removeLiquidityAndRepay(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.borrowable,
            redeemData.redeemTokens,
            redeemData.redeemAmount,
            token0,
            token1
        );
    }

    /**
     *  @notice Replace the bonus adapter. Keep at maximum 4 as the first 3 cover most cases
     */
    function addAdapter(uint8 adapter) external override {
        // Get admin from factory
        address admin = ICygnusFactory(hangar18).admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless admin
        if (_msgSender() != admin) {
            revert CygnusAltair__MsgSenderNotAdmin({ sender: _msgSender(), admin: admin });
        }

        // Remove bonus and don't add new adapter
        if (adapter == 0) {
            // Remove bonus adapter
            adapters.pop();
        }
        // Remove bonus and add new adapter
        else {
            // Remove bonus adapter
            adapters.pop();

            // Add new bonus adapter
            adapters.push(adapter);
        }
    }
}
