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
 *            2. 1Inch (Legacy and Optimized Routers)
 *            3. Paraswap
 *            4. OpenOcean
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
     *  @notice Internal record of all Altair Extensions - Borrowable/Collateral/LP address to extension contract implementation.
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
    string public constant override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusAltair
     */
    address public constant override PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    // Aggregator addresses are not used in this contract, kept here for consistency with extensions

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

    /**
     *  @notice Convert shares to assets
     *  @param collateral Address of the CygLP
     *  @param shares Amount of CygLP redeemed
     */
    function _convertToAssets(address collateral, uint256 shares) internal view returns (uint256) {
        // CygLP Supply
        uint256 _totalSupply = ICygnusCollateral(collateral).totalSupply();

        // LP assets in collateral
        uint256 _totalAssets = ICygnusCollateral(collateral).totalAssets();

        // Return the amount of LPs we get by redeeming shares, rounds down
        return shares.fullMulDiv(_totalAssets, _totalSupply);
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
    function getShuttleExtension(uint256 shuttleId) external view override returns (address) {
        // Get the collateral or borrowable (borrowable, collateral and lp share the extension anyways)
        (, , , address collateral, ) = hangar18.allShuttles(shuttleId);

        // Return extension
        return altairExtensions[collateral];
    }

    /**
     *  @dev Same calculation as all vault tokens, asset = shares * balance / supply
     *  @dev Relies on the extension to perform the logic
     *  @inheritdoc ICygnusAltair
     */
    function getAssetsForShares(
        address lpTokenPair,
        uint256 shares,
        uint256 difference
    ) external view returns (address[] memory tokens, uint256[] memory amounts) {
        // Get the extension for this lp token pair
        address altairX = altairExtensions[lpTokenPair];

        /// @custom:error ExtensionDoesntExist Avoid if the extension does not exist
        if (altairX == address(0)) revert CygnusAltair__AltairXDoesNotExist();

        // The extension should implement the assets for shares function - ie. Which assets and how much we receive
        // by redeeming `shares` amount of a liquidity token
        return ICygnusAltairX(altairX).getAssetsForShares(lpTokenPair, shares, difference);
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

    /**
     *  @notice Avoid stack too deep
     */
    function _latestBorrowerInfo(
        address collateral,
        address user
    )
        internal
        view
        returns (
            uint256 cygLPBalance,
            uint256 principal,
            uint256 borrowBalance,
            uint256 price,
            uint256 rate,
            uint256 positionUsd,
            uint256 positionLp,
            uint256 health
        )
    {
        // Position info
        (cygLPBalance, principal, borrowBalance, price, rate, positionUsd, positionLp, health) = ICygnusCollateral(collateral)
            .getBorrowerPosition(user);
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    //  POSITIONS ────────────────────────────────────

    /**
     *  @notice Returns the borrower`s overall positions (borrows, position in usd and balance) across the whole protocol
     *  @notice Accrues interest
     *  @inheritdoc ICygnusAltair
     */
    function latestBorrowerAll(address user) external returns (uint256 principal, uint256 borrowBalance, uint256 positionUsd) {
        // Total lending pools in Cygnus
        uint256 totalShuttles = hangar18.shuttlesDeployed();

        // Loop through each pool and update borrower's position
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Get borrowale and collateral for shuttle `i`
            (, , address borrowable, address collateral, ) = hangar18.allShuttles(i);

            // Accrue interest in borrowable
            ICygnusBorrow(borrowable).sync();

            // Get collateral position
            (, uint256 _principal, uint256 _borrowBalance, , , uint256 _positionUsd, , ) = ICygnusCollateral(collateral)
                .getBorrowerPosition(user);

            // Increase total principal
            principal += _principal;

            // Increase total borrowed balance
            borrowBalance += _borrowBalance;

            // Increase the borrower`s position in USD
            positionUsd += _positionUsd;
        }
    }

    /**
     *  @notice Returns the lenders`s overall positions (cygUsd and position in USD) across the whole protocol
     *  @notice Accrues interest
     *  @inheritdoc ICygnusAltair
     */
    function latestLenderAll(address user) external returns (uint256 cygUsdBalance, uint256 positionUsd) {
        // Total lending pools in Cygnus
        uint256 totalShuttles = hangar18.shuttlesDeployed();

        // Loop through each pool and update lender's position
        for (uint256 i = 0; i < totalShuttles; i++) {
            // Get borrowable contract for shuttle `i`
            (, , address borrowable, , ) = hangar18.allShuttles(i);

            // Accrue interest
            ICygnusBorrow(borrowable).sync();

            // Get lender position
            (uint256 _cygUsdBalance, , uint256 _positionUsd) = ICygnusBorrow(borrowable).getLenderPosition(user);

            // Increase shares balance
            cygUsdBalance += _cygUsdBalance;

            // Increase assets balance
            positionUsd += _positionUsd;
        }
    }

    /**
     *  @notice Accrues interest
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
     *  @notice Accrues interest
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
            uint256 health
        )
    {
        // Accrue interest and update balance
        borrowable.sync();

        // Get collateral contract
        address collateral = borrowable.collateral();

        // Return latest info
        return _latestBorrowerInfo(collateral, borrower);
    }

    /**
     *  @notice Accrues interest
     *  @inheritdoc ICygnusAltair
     */
    function latestAccountLiquidity(ICygnusBorrow borrowable, address borrower) external returns (uint256 liquidity, uint256 shortfall) {
        // Accrue interest and update balance
        borrowable.sync();

        // Get collateral contract
        address collateral = borrowable.collateral();

        // Liquidity info
        (liquidity, shortfall) = ICygnusCollateral(collateral).getAccountLiquidity(borrower);
    }

    /**
     *  @notice Accrues interest
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

    // Start periphery functions:
    //   1. Borrow
    //   2. Repay (+ permit2)
    //   3. Liquidate (+ permit2)
    //   4. Flash Liquidate
    //   5. Leverage
    //   6. Deleverage

    //  1. BORROW ────────────────────────────────────

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

    //  2. REPAY ─────────────────────────────────────

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

    //  3. LIQUIDATE ─────────────────────────────────

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

    //  4. FLASH LIQUIDATE ───────────────────────────

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

    //  5. LEVERAGE ──────────────────────────────────

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

    //  6. DELEVERAGE ────────────────────────────────

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

        // Get redeem amount, rounding down
        uint256 redeemAmount = _convertToAssets(collateral, cygLPAmount);

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

        // Add to array - Allow admin to update extension for the lending pool
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

    /**
     *  @inheritdoc ICygnusAltair
     *  @custom:security only-admin
     */
    function sweepTokens(IERC20[] memory tokens, address to) external override {
        // Get latest admin
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin
        if (msg.sender != admin) revert CygnusAltair__MsgSenderNotAdmin();

        // Transfer each token to admin
        for (uint256 i = 0; i < tokens.length; i++) {
            // Balance of token
            uint256 balance = tokens[i].balanceOf(address(this));

            // Send to admin
            if (balance > 0) address(tokens[i]).safeTransfer(to, balance);
        }
    }

    /**
     *  @inheritdoc ICygnusAltair
     *  @custom:security only-admin
     */
    function sweepNative() external override {
        // Get latest admin
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin
        if (msg.sender != admin) revert CygnusAltair__MsgSenderNotAdmin();

        // Get native balance
        uint256 balance = address(this).balance;

        // Get ETH out
        if (balance > 0) SafeTransferLib.safeTransferETH(admin, balance);
    }
}
