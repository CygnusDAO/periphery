// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusAltairX, ICygnusAltairCall } from "./interfaces/ICygnusAltairX.sol";
import { Context } from "./utils/Context.sol";

// Interfaces
import { ICygnusBorrow } from "./interfaces/ICygnusBorrow.sol";
import { ICygnusCollateral } from "./interfaces/ICygnusCollateral.sol";
import { ICygnusTerminal } from "./interfaces/ICygnusTerminal.sol";
import { IWAVAX } from "./interfaces/IWAVAX.sol";
import { IDexPair } from "./interfaces/IDexPair.sol";
import { IErc20 } from "./interfaces/IErc20.sol";
import { IDexRouter02 } from "./interfaces/IDexRouter.sol";
import { ICygnusFactory } from "./interfaces/ICygnusFactory.sol";
import { ICygnusCollateralVoid } from "./interfaces/ICygnusCollateralVoid.sol";
import { IYakAdapter } from "./interfaces/IYakAdapter.sol";

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeErc20 } from "./libraries/SafeErc20.sol";
import { AltairHelper } from "./libraries/AltairHelper.sol";

/**
 *  @title  CygnusAltair Periphery contract to interact with Cygnus Core contracts
 *  @author CygnusDAO
 *  @notice This contract details the functions for:
 *          - Minting CygLP and CygDAI
 *          - Redeeming CygLP and CygDAI
 *          - Borrowing DAI
 *          - Repaying DAI
 *          - Liquidating user's with DAI (pay back DAI, receive CygLP + bonus liquidation reward)
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
     *  @custom:library SafeErc20 For safe transfers of Erc20 tokens
     */
    using SafeErc20 for IErc20;

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
    bytes public constant override LOCAL_BYTES = new bytes(0);

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IYakAdapter public constant override JOE_ADAPTER = IYakAdapter(0xDB66686Ac8bEA67400CF9E5DD6c8849575B90148);

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IYakAdapter public constant override PANGOLIN_ADAPTER = IYakAdapter(0x3614657EDc3cb90BA420E5f4F61679777e4974E3);

    /**
     *  @inheritdoc ICygnusAltairX
     */
    IYakAdapter public constant override PLATYPUS_ADAPTER = IYakAdapter(0x6da140B4004D1EcCfc5FffEb010Bb7A58575b446);

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

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    // PERMITS

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
     *  @param cygnusDai The address of the Cygnus borrow contract
     *  @param amount The amount to allow borrow
     *  @param deadline A time in the future when the allowance expires
     */
    function borrowPermitInternal(
        address cygnusDai,
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
        ICygnusBorrow(cygnusDai).borrowPermit(_msgSender(), address(this), value, deadline, v, r, s);
    }

    /**
     *  @notice Safe internal mint after doing the sufficient checks
     *  @param terminalToken The address of the Cygnus pool token
     *  @param token The address of token deposited
     *  @param amount The amount to be minted
     *  @param from The address who is sending the token
     *  @param recipient The account that should receive the tokens
     */
    function mintInternal(
        address terminalToken,
        address token,
        uint256 amount,
        address from,
        address recipient
    ) internal virtual returns (uint256 tokens) {
        // Check caller
        if (from == address(this)) {
            IErc20(token).safeTransfer(terminalToken, amount);
        }
        // Else transferFrom caller
        else {
            IErc20(token).safeTransferFrom(from, terminalToken, amount);
        }

        // Return mint amount
        tokens = ICygnusTerminal(terminalToken).mint(recipient);
    }

    /**
     *  @param borrowable Address of the Cygnus borrow contract
     *  @param token Address of the token we are repaying (DAI)
     *  @param borrower Address of the borrower who is repaying the loan
     *  @param amountMax The max available amount
     */
    function refundCygnusBorrow(
        address borrowable,
        address token,
        address borrower,
        uint256 amountMax
    ) internal virtual {
        // Repay
        uint256 amount = repayAmountInternal(borrowable, amountMax, borrower);

        // Safe transfer DAI to borrowable
        IErc20(token).safeTransfer(borrowable, amount);

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
                SafeErc20.safeTransferAVAX(borrower, refundAmount);
            } else {
                // Transfer Token
                IErc20(token).safeTransfer(borrower, refundAmount);
            }
        }
    }

    /**
     *  @notice Safe internal function to repay borrowed amount
     *  @param cygnusDai The address of the Cygnus borrow arm where the borrowed amount was taken from
     *  @param amountMax The max amount that can be repaid
     *  @param borrower The address of the account that is repaying the borrowed amount
     */
    function repayAmountInternal(
        address cygnusDai,
        uint256 amountMax,
        address borrower
    ) internal virtual returns (uint256 amount) {
        ICygnusBorrow(cygnusDai).accrueInterest();

        // Get borrow balance of borrower
        uint256 borrowedAmount = ICygnusBorrow(cygnusDai).getBorrowBalance(borrower);

        // Avoid repaying more than borrowedAmount
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    // 2 FUNCTIONS: - CONVERT DAI TO LP'S TOKEN0 AND TOKEN1 FOR OPTIMAL LP DEPOSIT
    //              - CONVERT LP TOKEN TO DAI

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
        // Query 3 dexes in this chain
        (uint256 a, uint256 b, uint256 c) = (
            PLATYPUS_ADAPTER.query(amountIn, tokenIn, tokenOut),
            JOE_ADAPTER.query(amountIn, tokenIn, tokenOut),
            PANGOLIN_ADAPTER.query(amountIn, tokenIn, tokenOut)
        );

        (address adapter, uint256 amountOut) = a > b
            ? (a > c ? (address(PLATYPUS_ADAPTER), a) : (address(PANGOLIN_ADAPTER), c))
            : (b > c ? (address(JOE_ADAPTER), b) : (address(PANGOLIN_ADAPTER), c));

        // Approve adapter in router
        AltairHelper.approveDexRouter(tokenIn, adapter, type(uint256).max);

        // Send `amountIn` of `tokenIn` to the adapter
        IErc20(tokenIn).safeTransfer(adapter, amountIn);

        // Swap `amountIn` and receive `amountOut`
        IYakAdapter(adapter).swap(amountIn, amountOut, tokenIn, tokenOut, address(this));
    }

    /**
     *  @notice This function gets called after calling `borrow` on CygnusBorrow contract and having `amountDai` of DAI
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
        // Placeholder tokenA
        address tokenA;

        // Placeholder tokenB
        address tokenB;
        // ─────────────────────── 1. Check if token0 or token1 is already DAI

        if (token0 == dai || token1 == dai) {
            // If token0 is dai, then assign tokenA to token0, else tokenA to token1
            (tokenA, tokenB) = token0 == dai ? (token0, token1) : (token1, token0);
        } else {
            // Not DAI, swap DAI to native token
            swapTokensInternal(dai, nativeToken, amountDai);
            // ─────────────────── 2. Check if token0 or token1 is already AVAX

            if (token0 == nativeToken || token1 == nativeToken) {
                // If token0 is nativeToken, then assign tokenA to token0, else tokenA to token1
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // None are DAI or native token, swap all native token to token0 to calculate optimal deposit
                swapTokensInternal(nativeToken, token0, AltairHelper.contractBalanceOf(nativeToken));

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
        uint256 swapAmount = AltairHelper.optimalDepositA(AltairHelper.contractBalanceOf(tokenA), reservesA, 997);

        // Swap optimal amount of tokenA to tokenB
        swapTokensInternal(tokenA, tokenB, swapAmount);

        // ─────────────────────── 4. Send token0 and token1 to lp token pair to call `mint` on next function

        // Total Amount A
        totalAmountA = AltairHelper.contractBalanceOf(token0);

        // Total Amount B
        totalAmountB = AltairHelper.contractBalanceOf(token1);
    }

    /**
     *  @notice Converts an amount of LP Token to DAI. It is called after calling `burn` on a uniswapV2 pair, which
     *          receives amountTokenA of token0 and amountTokenB of token1. It then converts both tokens to nativeToken
     *          (WETH, WAVAX, etc.) and converts all native token held by this contract to DAI
     *  @param amountTokenA The amount of token A to convert to DAI
     *  @param amountTokenB The amount of token B to convert to DAI
     *  @param lpTokenPair The address of the LP Token
     */
    function convertLPTokenToDAI(
        uint256 amountTokenA,
        uint256 amountTokenB,
        address lpTokenPair
    ) internal returns (uint256 amountDAI) {
        // ─────────────────────── 1. Get token0 and token1

        // Token0 from the LP Token
        address token0 = IDexPair(lpTokenPair).token0();

        // Token1 from the LP Token
        address token1 = IDexPair(lpTokenPair).token1();

        // ─────────────────────── 2. Check if token0 or token1 is already DAI

        if (token0 == dai || token1 == dai) {
            // Convert token0 or token1 to nativeToken
            token0 == dai
                ? swapTokensInternal(token1, nativeToken, amountTokenB)
                : swapTokensInternal(token0, nativeToken, amountTokenA);
        } else {
            // ─────────────────── 3. Check if token0 or token1 is already nativeToken

            if (token0 == nativeToken || token1 == nativeToken) {
                // Convert token0 or token1 to nativeToken
                token0 == nativeToken
                    ? swapTokensInternal(token1, nativeToken, amountTokenB)
                    : swapTokensInternal(token0, nativeToken, amountTokenA);
            } else {
                // None are DAI or nativeToken, convert all to nativeToken

                // Swap token0 to nativeToken
                swapTokensInternal(token0, nativeToken, amountTokenA);

                // Swap token 1 to nativeToken
                swapTokensInternal(token1, nativeToken, amountTokenB);
            }
        }
        // ─────────────────────── 4. Swap all nativeTokens to DAI

        // Swap tokens
        swapTokensInternal(nativeToken, dai, AltairHelper.contractBalanceOf(nativeToken));

        // Total Amount DAI
        amountDAI = AltairHelper.contractBalanceOf(dai);
    }

    /**
     *  @notice Removes liquidity from the Dex by calling the pair's `burn` function, receiving tokenA and tokenB
     *  @param lpTokenPair The address of the LP Token
     *  @param borrower The address of the borrower
     *  @param collateral The address of the Cygnus Collateral contract
     *  @param borrowable The address of the Cygnus Borrow contract
     *  @param redeemTokens The amount of CygLP to redeem
     *  @param redeemAmount The amount of LP to redeem
     */
    function removeLiquidityAndRepay(
        address lpTokenPair,
        address borrower,
        address collateral,
        address borrowable,
        uint256 redeemTokens,
        uint256 redeemAmount
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
        uint256 amountDai = convertLPTokenToDAI(amountAMax, amountBMax, lpTokenPair);

        // Repay DAI
        refundCygnusBorrow(borrowable, dai, borrower, amountDai);

        // repay flash redeem
        ICygnusCollateral(collateral).transferFrom(borrower, collateral, redeemTokens);
    }

    /**
     *  @notice Leverage internal function and calls borrow contract
     *  @param lpTokenPair The address of the LP Token
     *  @param collateral The address of the Cygnus collateral address for this LP Token
     *  @param borrowable The address of the Cygnus borrowable address for this LP Token
     *  @param leverageAmount The amount to borrow
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
    function redeem(
        address terminalToken,
        uint256 tokens,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Permit (if any)
        permitInternal(terminalToken, tokens, deadline, permitData);

        // Transfer tokens from sender to CygnusTerminal
        ICygnusTerminal(terminalToken).transferFrom(_msgSender(), terminalToken, tokens);

        // Redeem Borrow or Collateral token
        amount = ICygnusTerminal(terminalToken).redeem(recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function borrow(
        address cygnusDai,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external virtual override checkDeadline(deadline) {
        // Borrow permit
        borrowPermitInternal(cygnusDai, amount, deadline, permitData);

        // Borrow amount
        ICygnusBorrow(cygnusDai).borrow(_msgSender(), recipient, amount, LOCAL_BYTES);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  MINT CYGLP / CYGDAI ──────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function mint(
        address terminalToken,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 tokens) {
        return
            mintInternal(terminalToken, ICygnusTerminal(terminalToken).underlying(), amount, _msgSender(), recipient);
    }

    function mintCollateral(
        address collateral,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual checkDeadline(deadline) returns (uint256 tokens) {
        // Validate permit
        permitInternal(collateral, amount, deadline, permitData);

        // Return normal mint
        return mintInternal(collateral, ICygnusTerminal(collateral).underlying(), amount, _msgSender(), recipient);
    }

    //  REPAY BORROW ─────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function repay(
        address cygnusDai,
        uint256 amountMax,
        address borrower,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Amount to repay
        amount = repayAmountInternal(cygnusDai, amountMax, borrower);

        // Transfer DAI from msg sender to borrow contract
        IErc20(ICygnusBorrow(cygnusDai).underlying()).safeTransferFrom(_msgSender(), cygnusDai, amount);

        // Call borrow to update borrower's borrow balance
        ICygnusBorrow(cygnusDai).borrow(borrower, address(0), 0, LOCAL_BYTES);
    }

    //  LIQUIDATE BORROW ─────────────────────────────

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function liquidate(
        address cygnusDai,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Amount to repay
        amount = repayAmountInternal(cygnusDai, amountMax, borrower);

        // Transfer DAI
        IErc20(ICygnusBorrow(cygnusDai).underlying()).safeTransferFrom(_msgSender(), cygnusDai, amount);

        // Liquidate
        seizeTokens = ICygnusBorrow(cygnusDai).liquidate(borrower, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairX
     */
    function liquidateToDai(
        address cygnusDai,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amountDai) {
        // Amount to repay
        uint256 amount = repayAmountInternal(cygnusDai, amountMax, borrower);

        // Transfer DAI
        IErc20(ICygnusBorrow(cygnusDai).underlying()).safeTransferFrom(_msgSender(), cygnusDai, amount);

        // Liquidate and increase liquidator's CygLP amount
        uint256 seizeTokens = ICygnusBorrow(cygnusDai).liquidate(borrower, recipient);

        // Get Collateral
        address collateral = ICygnusBorrow(cygnusDai).collateral();

        // Redeem CygLP for LP Token
        uint256 redeemAmount = redeem(collateral, seizeTokens, _msgSender(), deadline, LOCAL_BYTES);

        // Get LP Token pair
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Remove `redeemAmount` of liquidity from the LP Token pair
        IDexPair(lpTokenPair).transferFrom(recipient, lpTokenPair, redeemAmount);

        // Burn LP Token and return amountA and amountB
        (uint256 amountAMax, uint256 amountBMax) = IDexPair(lpTokenPair).burn(address(this));

        // Convert amountA and amountB to DAI
        amountDai = convertLPTokenToDAI(amountAMax, amountBMax, lpTokenPair);

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
        address cygnusDai = ICygnusCollateral(collateral).cygnusDai();

        // Permit (if any)
        borrowPermitInternal(cygnusDai, amountDAIDesired, deadline, permitData);

        // Pass LP Token, collateral, borrowable, amount, recipient
        leverageInternal(lpTokenPair, collateral, cygnusDai, amountDAIDesired, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
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
        address cygnusDai = cygnusShuttle.borrowable;

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin, borrower: borrower });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (_msgSender() != cygnusDai) {
            revert CygnusAltair__MsgSenderNotBorrowable({ sender: _msgSender(), borrowable: cygnusDai });
        }

        // Token0 Address of the user's deposited LP token
        address token0 = IDexPair(cygnusShuttle.lpTokenPair).token0();

        // Token1 Address of the user's deposited LP Token
        address token1 = IDexPair(cygnusShuttle.lpTokenPair).token1();

        // Converts the borrowed amount of DAI to tokenA and tokenB to mint the LP Token
        // Queries reserves from the DEX to get the reserves of each token and obtain the optimum amount of each token
        (uint256 totalAmountA, uint256 totalAmountB) = convertDAIToTokens(
            cygnusShuttle.lpTokenPair,
            token0,
            token1,
            borrowAmount
        );

        // Transfer tokenA to LP Token contract
        IErc20(token0).safeTransfer(cygnusShuttle.lpTokenPair, totalAmountA);

        // Transfer tokenA and tokenB to LP Token contract to mint the LP token
        IErc20(token1).safeTransfer(cygnusShuttle.lpTokenPair, totalAmountB);

        // MINT the LP Token in the DEX to the collateral contract
        IDexPair(cygnusShuttle.lpTokenPair).mint(cygnusShuttle.collateral);

        // Mint the cygnus collateral token to the recipient
        ICygnusCollateral(cygnusShuttle.collateral).mint(cygnusShuttle.recipient);
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
        uint256 redeemAmount = (redeemTokens - 1).mul(exchangeRate);

        // Permit data
        permitInternal(collateral, redeemTokens, deadline, permitData);

        // Encode redeem data
        bytes memory redeemData = abi.encode(
            RedeemLeverageCallData({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: ICygnusCollateral(collateral).cygnusDai(),
                recipient: _msgSender(),
                redeemTokens: redeemTokens,
                redeemAmount: redeemAmount
            })
        );

        // Flash redeem
        ICygnusCollateral(collateral).redeemDeneb(address(this), redeemAmount, redeemData);
    }

    /**
     *  @inheritdoc ICygnusAltairCall
     */
    function altairRedeem_u91A(
        address sender,
        uint256 redeemAmount,
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
            revert CygnusAltair__MsgSenderNotCollateral({ sender: _msgSender(), origin: tx.origin, collateral: redeemData.collateral });
        }
        //solhint-enable

        // Remove liquidity from pool and repay to borrowable
        removeLiquidityAndRepay(
            redeemData.lpTokenPair,
            redeemData.recipient,
            redeemData.collateral,
            redeemData.borrowable,
            redeemData.redeemTokens,
            redeemData.redeemAmount
        );
    }
}
