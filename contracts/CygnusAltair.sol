// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.4;

// Dependencies
import { ICygnusAltair } from "./interfaces/ICygnusAltair.sol";
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

// Libraries
import { PRBMath, PRBMathUD60x18 } from "./libraries/PRBMathUD60x18.sol";
import { SafeErc20 } from "./libraries/SafeErc20.sol";
import { CygnusPoolAddress } from "./libraries/CygnusPoolAddress.sol";
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
contract CygnusAltair is ICygnusAltair, Context {
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
     *  @inheritdoc ICygnusAltair
     */
    address public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public immutable override collateralDeployer;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public immutable override borrowDeployer;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public immutable override nativeToken;

    /**
     *  @inheritdoc ICygnusAltair
     */
    bytes public constant override LOCAL_BYTES = new bytes(0);

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override JOE_ROUTER = 0x60aE616a2155Ee3d9A68541Ba4544862310933d4;

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override DAI = 0xd586E7F844cEa2F87f50152665BCbc2C279D8d70;

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

        // Address of the Collateral Deployer for calculating deployed pools
        collateralDeployer = address(ICygnusFactory(factory).collateralDeployer());

        // Address of the Borrow Deployer for calculating deployed pools
        borrowDeployer = address(ICygnusFactory(factory).borrowDeployer());

        // nativeToken Address - 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7
        nativeToken = ICygnusFactory(factory).nativeToken();
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

    /**
     *  @custom:modifier checkAvax Reverts the transaction if the underlying is not native token
     */
    modifier checkAVAX(address terminalToken) {
        checkAvaxInternal(terminalToken);
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
        /// @custom:error TransactionTooOld Avoid transacting past deadline
        if (getBlockTimestamp() > deadline) {
            revert CygnusAltair__TransactionTooOld(deadline);
        }
    }

    /**
     *  @notice Reverts the transaction if the underlying is not AVAX
     *  @param terminalToken The address of the Cygnus Collateral/Borrow tokens
     */
    function checkAvaxInternal(address terminalToken) internal {
        /// @custom:error NotNativeTokenSender Checks if underlying is Wrapped Avax
        if (nativeToken != ICygnusTerminal(terminalToken).underlying()) {
            revert CygnusAltair__NotNativeTokenSender(terminalToken);
        }
    }

    /**
     *  @notice The current block timestamp
     */
    function getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     *  @notice Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
     */
    function quoteInternal(
        uint256 amountTokenA,
        uint256 reservesTokenA,
        uint256 reservesTokenB
    ) internal pure returns (uint256 amountTokenB) {
        /// @custom:error InsufficientTokenAmount Avoid 0 Token A amount
        if (amountTokenA <= 0) {
            revert CygnusAltair__InsufficientTokenAmount(amountTokenA);
        }
        /// @custom:error InsufficientReserves Avoid 0 reserves for both tokens
        else if (reservesTokenA <= 0 && reservesTokenB <= 0) {
            revert CygnusAltair__InsufficientReserves(reservesTokenA, reservesTokenB);
        }

        // Get optimal amount of Token B
        amountTokenB = PRBMath.mulDiv(amountTokenA, reservesTokenB, reservesTokenA);
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusAltair
     */
    function getShuttle(address lpTokenPair)
        public
        view
        virtual
        override
        returns (address collateral, address borrowable)
    {
        // Get Cygnus collateral address for this LP Token pair
        collateral = CygnusPoolAddress.getCollateralContract(lpTokenPair, hangar18, collateralDeployer);

        // Get Cygnus borrow address for this LP Token pair
        borrowable = CygnusPoolAddress.getBorrowContract(collateral, hangar18, borrowDeployer);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function optimalLiquidity(
        address lpTokenPair,
        uint256 amountTokenADesired,
        uint256 amountTokenBDesired,
        uint256 amountTokenAMin,
        uint256 amountTokenBMin
    ) public view virtual override returns (uint256 amountTokenA, uint256 amountTokenB) {
        // Get reserves of token0 and token1 from LP Token pair
        (uint256 reserveA, uint256 reserveB, ) = IDexPair(lpTokenPair).getReserves();

        // Quote optimal amount to deposit for token B
        uint256 amountTokenBOptimal = quoteInternal(amountTokenADesired, reserveA, reserveB);

        if (amountTokenBOptimal <= amountTokenBDesired) {
            /// @custom:error InsufficientTokenBAmount Avoid insufficient token B Amount
            if (amountTokenBOptimal < amountTokenBMin) {
                revert CygnusAltair__InsufficientTokenBAmount(amountTokenBOptimal);
            }

            (amountTokenA, amountTokenB) = (amountTokenADesired, amountTokenBOptimal);
        } else {
            // Get optimal amount of Token A
            uint256 amountAOptimal = quoteInternal(amountTokenBDesired, reserveB, reserveA);

            // Should never reach here
            assert(amountAOptimal <= amountTokenADesired);

            /// @custom:error InsufficientTokenAAmount Avoid insufficient token A Amount
            if (amountAOptimal < amountTokenAMin) {
                revert CygnusAltair__InsufficientTokenAAmount(amountAOptimal);
            }

            // Return amount token A and amount token B
            (amountTokenA, amountTokenB) = (amountAOptimal, amountTokenBDesired);
        }
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
     *  @param cygnusAlbireo The address of the Cygnus borrow contract
     *  @param amount The amount to allow borrow
     *  @param deadline A time in the future when the allowance expires
     */
    function borrowPermitInternal(
        address cygnusAlbireo,
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
        ICygnusBorrow(cygnusAlbireo).borrowPermit(_msgSender(), address(this), value, deadline, v, r, s);
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
    function repayAndRefundInternal(
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
     *  @param cygnusAlbireo The address of the Cygnus borrow arm where the borrowed amount was taken from
     *  @param amountMax The max amount that can be repaid
     *  @param borrower The address of the account that is repaying the borrowed amount
     */
    function repayAmountInternal(
        address cygnusAlbireo,
        uint256 amountMax,
        address borrower
    ) internal virtual returns (uint256 amount) {
        // Accrue interest before repaying
        ICygnusBorrow(cygnusAlbireo).accrueInterest();

        // Accrue interest before repaying
        uint256 borrowedAmount = ICygnusBorrow(cygnusAlbireo).getBorrowBalance(borrower);

        // If amountMax is more than borrowed amount, just repay borrowed amount, else repay amountMax
        amount = amountMax < borrowedAmount ? amountMax : borrowedAmount;
    }

    // Swap Erc20 tokens - tokenIn to tokenOut

    /**
     *  @notice Swap tokens function used by Leverage to turn DAI into LP Token assets
     *  @param tokenIn address of the token we are swapping
     *  @param tokenOut Address of the token we are receiving
     *  @param amount Amount of TokenIn we are swapping
     */
    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal virtual {
        // Create the path for the swap
        address[] memory path = new address[](2);

        // Path of the token we are swapping
        path[0] = address(tokenIn);

        // Path of the token we are receiving
        path[1] = address(tokenOut);

        // Safe Approve router
        AltairHelper.approveDexRouter(tokenIn, JOE_ROUTER, type(uint256).max);

        // Swap tokens
        IDexRouter02(JOE_ROUTER).swapExactTokensForTokens(amount, 0, path, address(this), type(uint256).max);
    }

    // 2 FUNCTIONS: - CONVERT DAI TO LP'S TOKEN0 AND TOKEN1 FOR OPTIMAL LP DEPOSIT
    //              - CONVERT LP TOKEN TO DAI

    /**
     *  @notice This function gets called after calling `borrow` on CygnusBorrow contract and having `amountDai` of DAI
     *  @param lpTokenPair The address of the LP Token we are converting DAI to
     *  @param amountDai DAI amount to convert to token0 and token1 of an LP Token
     */
    function convertDAIToTokens(address lpTokenPair, uint256 amountDai)
        internal
        returns (uint256 totalAmountA, uint256 totalAmountB)
    {
        // ─────────────────────── 1. Get token0 and token1 from LP Token

        // Token0 from the LP Token
        address token0 = IDexPair(lpTokenPair).token0();

        // Token1 from the LP Token
        address token1 = IDexPair(lpTokenPair).token1();

        // ─────────────────────── 2. Check if token0 or token1 is already DAI

        // Placeholder tokenA
        address tokenA;

        // Placeholder tokenB
        address tokenB;

        // Check if token is DAI
        if (token0 == DAI || token1 == DAI) {
            (tokenA, tokenB) = token0 == DAI ? (token0, token1) : (token1, token0);
        } else {
            // Not DAI, swap DAI to native token
            swapExactTokensForTokens(DAI, nativeToken, amountDai);

            // ─────────────────── 3. Check if token0 or token1 is already AVAX

            if (token0 == nativeToken || token1 == nativeToken) {
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // Not native token, convert all AVAX to LP Token's token0
                swapExactTokensForTokens(nativeToken, token0, AltairHelper.contractBalanceOf(nativeToken));

                (tokenA, tokenB) = (token0, token1);
            }
        }

        // ─────────────────────── 4. Calculate optimal deposit amount for an LP Token

        // prettier-ignore
        (uint256 reserves0, uint256 reserves1, /* BlockTimestamp */) = IDexPair(lpTokenPair).getReserves();

        // Get reserves A for calculating optimal deposit
        uint256 reservesA = tokenA == token0 ? reserves0 : reserves1;

        // Get optimal swap amount for token A - 997/1000 is the swap fee of TraderJoe
        uint256 swapAmount = AltairHelper.optimalDepositA(AltairHelper.contractBalanceOf(tokenA), reservesA, 997);

        // Swap optimal amount of tokenA to tokenB
        swapExactTokensForTokens(tokenA, tokenB, swapAmount);

        // ─────────────────────── 5. Send token0 and token1 to lp token pair to call `mint` on next function

        // Total Amount A
        totalAmountA = AltairHelper.contractBalanceOf(token0);

        // Total Amount B
        totalAmountB = AltairHelper.contractBalanceOf(token1);

        // Transfer tokenA and tokenB to LP Token contract to mint the LP token
        IErc20(token1).safeTransfer(lpTokenPair, totalAmountB);

        // Transfer tokenB and tokenB to LP Token contract to mint the LP token
        IErc20(token0).safeTransfer(lpTokenPair, totalAmountA);
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

        if (token0 == DAI || token1 == DAI) {
            // Convert token0 or token1 to nativeToken
            token0 == DAI
                ? swapExactTokensForTokens(token1, nativeToken, amountTokenB)
                : swapExactTokensForTokens(token0, nativeToken, amountTokenA);
        } else {
            // ─────────────────── 3. Check if token0 or token1 is already nativeToken

            if (token0 == nativeToken || token1 == nativeToken) {
                // Convert token0 or token1 to nativeToken
                token0 == nativeToken
                    ? swapExactTokensForTokens(token1, nativeToken, amountTokenB)
                    : swapExactTokensForTokens(token0, nativeToken, amountTokenA);
            } else {
                // Convert both tokens to nativeToken
                swapExactTokensForTokens(token0, nativeToken, amountTokenA);

                swapExactTokensForTokens(token1, nativeToken, amountTokenB);
            }
        }

        // ─────────────────────── 4. Swap all nativeTokens to DAI

        swapExactTokensForTokens(nativeToken, DAI, AltairHelper.contractBalanceOf(nativeToken));

        // Total Amount A
        amountDAI = AltairHelper.contractBalanceOf(DAI);
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
        // Remove liquidity
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
        uint256 daiAmount = convertLPTokenToDAI(amountAMax, amountBMax, lpTokenPair);

        // Repay DAI
        repayAndRefundInternal(borrowable, DAI, borrower, daiAmount);

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
     *  @inheritdoc ICygnusAltair
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

        // Return the amount to redeem
        amount = ICygnusTerminal(terminalToken).redeem(recipient);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function redeemAVAX(
        address terminalToken,
        uint256 tokens,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override checkDeadline(deadline) checkAVAX(terminalToken) returns (uint256 amountAVAX) {
        // Get avax amount to redeem
        amountAVAX = redeem(terminalToken, tokens, address(this), deadline, permitData);

        // Withdraw avax
        IWAVAX(nativeToken).withdraw(amountAVAX);

        // Transfer avax and return amount transferred
        SafeErc20.safeTransferAVAX(recipient, amountAVAX);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function borrow(
        address cygnusAlbireo,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override checkDeadline(deadline) {
        // Borrow permit
        borrowPermitInternal(cygnusAlbireo, amount, deadline, permitData);

        // Borrow amount
        ICygnusBorrow(cygnusAlbireo).borrow(_msgSender(), recipient, amount, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function borrowAVAX(
        address cygnusAlbireo,
        uint256 amountAVAX,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) public virtual override checkDeadline(deadline) checkAVAX(cygnusAlbireo) {
        borrow(cygnusAlbireo, amountAVAX, address(this), deadline, permitData);

        // Withdraw avax
        IWAVAX(nativeToken).withdraw(amountAVAX);

        // Transfer avax
        SafeErc20.safeTransferAVAX(recipient, amountAVAX);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  MINT CYGLP / CYGDAI ──────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
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

    /**
     *  @inheritdoc ICygnusAltair
     */
    function mintAVAX(
        address terminalToken,
        address recipient,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) checkAVAX(terminalToken) returns (uint256 tokens) {
        // deposit avax
        IWAVAX(nativeToken).deposit{ value: msg.value }();

        // Mint internal and return amount
        return mintInternal(terminalToken, nativeToken, msg.value, address(this), recipient);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function mintCollateral(
        address terminalToken,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) returns (uint256 tokens) {
        // Get LP Token
        address lpTokenPair = ICygnusTerminal(terminalToken).underlying();

        // Permit
        permitInternal(lpTokenPair, amount, deadline, permitData);

        // Mint internal and return amount
        return mintInternal(terminalToken, lpTokenPair, amount, _msgSender(), recipient);
    }

    //  REPAY BORROW ─────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function repay(
        address cygnusAlbireo,
        uint256 amountMax,
        address borrower,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount) {
        // Amount to repay
        amount = repayAmountInternal(cygnusAlbireo, amountMax, borrower);

        // Transfer DAI from msg sender to borrow contract
        IErc20(ICygnusBorrow(cygnusAlbireo).underlying()).safeTransferFrom(_msgSender(), cygnusAlbireo, amount);

        // Call borrow to update borrower's borrow balance
        ICygnusBorrow(cygnusAlbireo).borrow(borrower, address(0), 0, LOCAL_BYTES);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function repayAVAX(
        address cygnusAlbireo,
        address borrower,
        uint256 deadline
    ) external payable virtual override checkDeadline(deadline) checkAVAX(cygnusAlbireo) returns (uint256 amountAVAX) {
        // Avax amount to repay
        amountAVAX = repayAmountInternal(cygnusAlbireo, msg.value, borrower);

        // Deposit AVAX
        IWAVAX(nativeToken).deposit{ value: amountAVAX }();

        assert(IWAVAX(nativeToken).transfer(cygnusAlbireo, amountAVAX));

        // Call borrow to update borrower's borrow balance
        ICygnusBorrow(cygnusAlbireo).borrow(borrower, address(0), 0, LOCAL_BYTES);

        if (msg.value > amountAVAX) {
            SafeErc20.safeTransferAVAX(_msgSender(), msg.value - amountAVAX);
        }
    }

    //  LIQUIDATE BORROW ─────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function liquidate(
        address cygnusAlbireo,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external virtual override checkDeadline(deadline) returns (uint256 amount, uint256 seizeTokens) {
        // Amount to repay
        amount = repayAmountInternal(cygnusAlbireo, amountMax, borrower);

        // Transfer DAI
        IErc20(ICygnusBorrow(cygnusAlbireo).underlying()).safeTransferFrom(_msgSender(), cygnusAlbireo, amount);

        // Liquidate
        seizeTokens = ICygnusBorrow(cygnusAlbireo).liquidate(borrower, recipient);

        // address collateral = ICygnusBorrow(cygnusAlbireo).collateral();

        // redeem(collateral, seizeTokens, _msgSender(), deadline, permitData);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function liquidateAVAX(
        address cygnusAlbireo,
        address borrower,
        address recipient,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        checkDeadline(deadline)
        checkAVAX(cygnusAlbireo)
        returns (uint256 amountAVAX, uint256 seizeTokens)
    {
        // Avax amount
        amountAVAX = repayAmountInternal(cygnusAlbireo, msg.value, borrower);

        // Deposit Avax
        IWAVAX(nativeToken).deposit{ value: amountAVAX }();

        // Check successful transfer
        assert(IWAVAX(nativeToken).transfer(cygnusAlbireo, amountAVAX));

        // Seize avax
        seizeTokens = ICygnusBorrow(cygnusAlbireo).liquidate(borrower, recipient);

        if (msg.value > amountAVAX) {
            SafeErc20.safeTransferAVAX(_msgSender(), msg.value - amountAVAX);
        }
    }

    //  LEVERAGE ─────────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function leverage(
        address cygnusCollateral,
        uint256 amountDAIDesired,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external virtual override checkDeadline(deadline) {
        // Get LP TokenPair
        address lpTokenPair = ICygnusCollateral(cygnusCollateral).underlying();

        // Get the borrow contract for the permit
        (address deneb, address albireo) = getShuttle(lpTokenPair);

        // Permit (if any)
        borrowPermitInternal(albireo, amountDAIDesired, deadline, permitData);

        // Pass LP Token, collateral, borrowable, amount, recipient
        leverageInternal(lpTokenPair, deneb, albireo, amountDAIDesired, recipient);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function cygnusBorrow(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external override {
        // Decode data passed from borrow contract
        CygnusShuttle memory cygnusShuttle = abi.decode(data, (CygnusShuttle));

        // Get Cygnus borrow address for this LP Token pair
        address cygnusBorrowContract = CygnusPoolAddress.getBorrowContract(
            cygnusShuttle.collateral,
            hangar18,
            borrowDeployer
        );

        /// @custom:error MsgSenderNotRouter Avoid if the caller is not the router
        if (sender != address(this)) {
            // solhint-disable-next-line
            revert CygnusAltair__MsgSenderNotRouter({ sender: sender, origin: tx.origin, borrower: borrower });
        }
        /// @custom:error MsgSenderNotBorrowable Avoid if the msg sender is not the borrow contract
        else if (_msgSender() != cygnusBorrowContract) {
            revert CygnusAltair__MsgSenderNotBorrowable({ sender: _msgSender(), borrowable: cygnusBorrowContract });
        }

        // Convert the borrow amount to DAI and send to LP Token pair address
        convertDAIToTokens(cygnusShuttle.lpTokenPair, borrowAmount);

        // MINT the LP Token in the DEX to the collateral contract
        IDexPair(cygnusShuttle.lpTokenPair).mint(cygnusShuttle.collateral);

        // Mint the cygnus collateral token to the recipient
        ICygnusCollateral(cygnusShuttle.collateral).mint(cygnusShuttle.recipient);
    }

    //  DELEVERAGE ───────────────────────────────────

    /**
     *  @inheritdoc ICygnusAltair
     */
    function deleverage(
        address lpTokenPair,
        uint256 redeemTokens,
        uint256 deadline,
        bytes calldata permitData
    ) external override checkDeadline(deadline) {
        // Get collateral
        address collateral = CygnusPoolAddress.getCollateralContract(lpTokenPair, hangar18, collateralDeployer);

        uint256 exchangeRate = ICygnusCollateral(collateral).exchangeRate();

        // Must redeem more than 0
        require(redeemTokens > 0, "no");

        uint256 redeemAmount = (redeemTokens - 1).mul(exchangeRate);

        permitInternal(collateral, redeemTokens, deadline, permitData);

        // Encode redeem data
        bytes memory redeemData = abi.encode(
            RedeemLeverageCallData({
                lpTokenPair: lpTokenPair,
                collateral: collateral,
                borrowable: CygnusPoolAddress.getBorrowContract(collateral, hangar18, borrowDeployer),
                recipient: _msgSender(),
                redeemTokens: redeemTokens,
                redeemAmount: redeemAmount
            })
        );

        // Flash redeem
        ICygnusCollateral(collateral).redeemDeneb(address(this), redeemAmount, redeemData);
    }

    /**
     *  @inheritdoc ICygnusAltair
     */
    function cygnusRedeem(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external override {
        redeemAmount;

        // Decode shuttle
        RedeemLeverageCallData memory redeemData = abi.decode(data, (RedeemLeverageCallData));

        // Get collateral contract
        address cygnusCollateralContract = CygnusPoolAddress.getCollateralContract(
            redeemData.lpTokenPair,
            hangar18,
            collateralDeployer
        );

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
            revert CygnusAltair__MsgSenderNotCollateral({ sender: _msgSender(), collateral: redeemData.collateral });
        }
        // solhint-enable

        // underlyhing, recipient, redeem tokens, redeem amount, amountA min, amountB min)
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
