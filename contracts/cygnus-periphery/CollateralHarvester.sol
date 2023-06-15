// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import { ICygnusHarvester } from "./interfaces/ICygnusHarvester.sol";
import { ReentrancyGuard } from "./utils/ReentrancyGuard.sol";

// Libraries
import { CygnusDexLib } from "./libraries/CygnusDexLib.sol";
import { SafeTransferLib } from "./libraries/SafeTransferLib.sol";
import { FixedPointMathLib } from "./libraries/FixedPointMathLib.sol";

// Interfaces
import { IERC20 } from "./interfaces/core/IERC20.sol";
import { IHangar18 } from "./interfaces/core/IHangar18.sol";
import { ICygnusCollateral } from "./interfaces/core/ICygnusCollateral.sol";
import { IAggregationRouterV5, IAggregationExecutor } from "./interfaces/core/IAggregationRouterV5.sol";

// Strategy
import { IDexPair } from "./interfaces/core/CollateralVoid/IDexPair.sol";
import { IDexRouter } from "./interfaces/core/CollateralVoid/IDexRouter.sol";

/**
 *  @title  CollateralHarvester Contract that harvests rewards from a CygnusCollateral contract and reinvests it to
 *          add it to the totalBalance. It uses 1inch aggregator on-chain to swap the rewards to the underlying
 *          borrowable asset (LP Token)
 *  @author CygnusDAO
 *  @notice The harvester should only be called from the CygnusCollateral contract via the `reinvestRewards` function.
 *          The function should harvest the rewards and send to this contract the rewards + amounts + swapData.
 *          In order to build the 1inch swap data, the caller can call `getRewards()` via a static call in the
 *          collateral contract to receive an array of tokens and an array of amounts harvested.
 *
 *                         ┌───────────────┐       ┌─────────────┐            ┌─────────────┐
 *                         │ 1. Collateral │       │ 2. Rewarder │            │  4. 1Inch   │
 *                         └───────────────┘       └─────────────┘            └─────────────┘
 *                                 |                      |                          |
 *                                 |   Deposit LP Tokens  |                          |
 *                                 |--------------------->|                          |
 *                                 |                      |                          |
 *                                 |                      |                          |
 *                                 |                      |                          |
 *                                 |                      |                          |
 *                                 |    Accrue Rewards    |                          |
 *                                 |<---------------------+                          |
 *                                 |                                                 |
 *                                 |                                                 |
 *                                 |              ┌───────────────┐                  |
 *              reinvestRewards()  |------------->│  3. Harvester │                  |
 *                                 |              └───────────────┘                  |
 *                                 |                      |                          |
 *                                 |                      |    Swap Rewards Tokens   |
 *                                 |                      |------------------------->|
 *                                 |                      |                          |
 *                                 |                      |  Receive Token0/Token1   |
 *                                 |                      |<-------------------------|
 *                                 |                      |
 *                                 |    Add Liquidity     |
 *                                 |    to Collateral     |
 *                                 |<---------------------+
 *
 */
contract CollateralHarvester is ICygnusHarvester, ReentrancyGuard {
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
     *  @dev A struct representing a harvester that holds information about the LP token pair and its components
     *  @custom:member underlying The address of the LP token pair
     *  @custom:member wantToken The address of the token the harvester wants to swap rewards into (tokenA)
     *  @custom:member needToken The address of the token that the harvester needs to provide as liquidity (tokenB)
     */
    struct Harvester {
        address underlying;
        address wantToken;
        address needToken;
    }

    /**
     *  @notice VELO The address of the base rewards token
     */
    address private constant VELO = 0x3c8B650257cFb5f272f799F5e2b4e65093a11a05;

    /**
     *  @notice The address of the Velo Router to add liquidity to
     */
    IDexRouter private constant DEX_ROUTER = IDexRouter(0x9c12939390052919aF3155f41Bf4160Fd3666A6f);

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /// @notice Total collaterals
    mapping(address => Harvester) public getHarvester;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    IAggregationRouterV5 public constant override ONE_INCH_ROUTER_V5 =
        IAggregationRouterV5(0x1111111254EEB25477B68fb85Ed929f73A960582);

    /**
     *  @inheritdoc ICygnusHarvester
     */
    address[] public override allHarvesters;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    address[] public override allX1RewardTokens;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    string public constant override name = "Cygnus Harvester: VELO Rewards";

    /**
     *  @inheritdoc ICygnusHarvester
     */
    uint256 public constant override MIN_X1_REWARD = 0;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    uint256 public constant override MAX_X1_REWARD = 1e18;

    // Harvester Reward
    uint256 public constant HARVESTER_REWARD = 0.03e18;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    uint256 public override x1VaultReward = 0.20e18;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    IHangar18 public immutable override hangar18;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    address public immutable override nativeToken;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    address public immutable override cygnusX1Vault;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    uint256 public override lastX1Collect;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the harvester, use the hangar18 contract to get important addresses
     *  @param _hangar18 The address of the contract that deploys Cygnus lending pools on this chain
     */
    constructor(IHangar18 _hangar18) {
        // Hangar18 on this chain
        hangar18 = _hangar18;

        // Get native token for this chain (ie WETH)
        nativeToken = _hangar18.nativeToken();

        // Vault
        cygnusX1Vault = _hangar18.cygnusX1Vault();

        // Add DEX token
        addRewardTokenPrivate(VELO);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Controls important parameters in both Collateral and Borrow contracts 👽
     */
    modifier cygnusAdmin() {
        checkAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Internal check for msg.sender admin, checks factory's current admin 👽
     */
    function checkAdmin() private view {
        // Current admin from the factory
        address admin = hangar18.admin();

        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) {
            revert CygnusHarvester__MsgSenderNotAdmin({ sender: msg.sender, admin: admin });
        }
    }

    /**
     *  @notice Calculates the optimal order of the tokens in a given LP token pair for trading.
     *  @dev This function gets the address of the underlying LP token pair and sorts the tokens based on their reserve value.
     *  @param lpTokenPair Address of the LP token pair.
     *  @return tokenA Address of the optimal token
     *  @return tokenB Address of the need token
     */
    function getOptimalDstToken(address lpTokenPair) private view returns (address tokenA, address tokenB) {
        // Token0 from the LP
        address token0 = IDexPair(lpTokenPair).token0();

        // Token1 from the LP
        address token1 = IDexPair(lpTokenPair).token1();

        // Check if rewards token is already token0 or token1 from LP
        if (token0 == VELO || token1 == VELO) {
            // Check which token is rewardsToken
            (tokenA, tokenB) = token0 == VELO ? (token0, token1) : (token1, token0);
        } else {
            // Check if token0 or token1 is native token
            if (token0 == nativeToken || token1 == nativeToken) {
                // Check which token is nativeToken
                (tokenA, tokenB) = token0 == nativeToken ? (token0, token1) : (token1, token0);
            } else {
                // Assign tokenA and tokenB to token0 and token1 respectively
                (tokenA, tokenB) = (token0, token1);
            }
        }
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Private ────────────────────────────────────────────────  */

    /**
     *  @notice Adds a reward token to be collected by the X1 Vault on this chain
     *  @param rewardToken The address of the token to be added
     */
    function addRewardTokenPrivate(address rewardToken) private {
        // Load array to memory, gas savings
        address[] memory tokens = allX1RewardTokens;

        // Loop through all reward tokens
        for (uint256 i = 0; i < tokens.length; i++) {
            // If reward token is already included return and exit
            if (rewardToken == tokens[i]) return;
        }

        // Push reward token to array
        allX1RewardTokens.push(rewardToken);

        /// @custom:event NewX1RewardToken
        emit NewX1RewardToken(rewardToken, allX1RewardTokens.length);
    }

    /**
     *  @notice Uses the 1inch Aggregator. It updates the amount to swap in case the estimations are slightly off
     *  @dev Swaps tokens using the 1inch aggregator with the provided swap data and updated amount.
     *  @dev Requirements:
     *       - The `srcToken` must be the rewards token.
     *       - The `dstToken` must be the underlying token.
     *       - The `dstReceiver` must be this contract address.
     *  @param swapData Encoded data that specifies the swap details for the 1inch aggregator
     *  @param token The token we should be swapping
     *  @param amount The updated amount of tokens to be swapped.
     *  @return amountOut The amount of `dstToken` received after the swap.
     */
    function swapTokensPrivateInch(
        bytes calldata swapData,
        address token,
        address wantToken,
        uint256 amount
    ) private returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        // prettier-ignore
        (address caller, IAggregationRouterV5.SwapDescription memory desc, bytes memory permit, bytes memory data) = abi
            .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != amount) desc.amount = amount;

        /// @custom:error SrcTokenNotValid Avoid swapping anything but rewards token
        if (address(desc.srcToken) != token) {
            revert CygnusHarvester__SrcTokenNotValid({ srcToken: address(desc.srcToken), token: token });
        }

        /// @custom:error DstTokenNotValid Avoid swapping to anything but the want token
        if (address(desc.dstToken) != wantToken) {
            revert CygnusHarvester__DstTokenNotValid({ dstToken: address(desc.dstToken), token: wantToken });
        }

        /// @custom:error DstReceiverNotValid Avoid swapping to another address
        if (desc.dstReceiver != address(this)) {
            revert CygnusHarvester__DstReceiverNotValid({ dstReceiver: desc.dstReceiver, receiver: address(this) });
        }

        // Allow 1inch router to access our `srcToken` (REWARDS_TOKEN)
        // This is safe because we only approve a constant (1inch router) and we only use `swap()` from the router which
        // transfers from sender
        approveTokenPrivate(address(desc.srcToken), address(ONE_INCH_ROUTER_V5), desc.amount);

        // Swap `srcToken` to `dstToken` with no permit
        (amountOut, ) = ONE_INCH_ROUTER_V5.swap(IAggregationExecutor(caller), desc, permit, data);
    }

    /**
     *  @notice Sets `amount` of ERC20 `token` for `to` to manage on behalf of the current contract
     *  @param token The address of the token we are approving
     *  @param amount The amount to approve
     */
    function approveTokenPrivate(address token, address to, uint256 amount) private {
        // Check allowance for `router` for deposit
        if (IERC20(token).allowance(address(this), to) >= amount) {
            return;
        }

        // Is less than amount, safe approve max
        token.safeApprove(to, type(uint256).max);
    }

    /**
     *  @notice Swap tokens using the dex router for the second swap
     *  @param tokenIn The address of the token we are swapping
     *  @param tokenOut The address of the token we are receiving
     *  @param amount Amount of `tokenIn` we are swapping to `tokenOut`
     */
    function swapTokensPrivateDex(address tokenIn, address tokenOut, uint256 amount) private returns (uint256) {
        // Check approve tokenIn
        approveTokenPrivate(tokenIn, address(DEX_ROUTER), amount);

        // Swap tokenIn to tokenOut
        uint256[] memory amounts = DEX_ROUTER.swapExactTokensForTokensSimple(
            amount,
            0,
            tokenIn,
            tokenOut,
            false,
            address(this),
            block.timestamp
        );

        // Return amount out of tokenOut (last index)
        return amounts[amounts.length - 1];
    }

    /**
     * @dev Adds liquidity to the designated DEX pool.
     * @param tokenA The address of the first token to add liquidity for.
     * @param tokenB The address of the second token to add liquidity for.
     * @param amountA The amount of the first token to add to the liquidity pool.
     * @param amountB The amount of the second token to add to the liquidity pool.
     * @return liquidity The amount of liquidity tokens received
     */
    function addLiquidityPrivate(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address cygnus
    ) private returns (uint256 liquidity) {
        // Check tokenA approval
        approveTokenPrivate(tokenA, address(DEX_ROUTER), amountA);

        // Check tokenB approval
        approveTokenPrivate(tokenB, address(DEX_ROUTER), amountB);

        // Never underflows
        unchecked {
            // Reduce amountA by harvestFee percentage
            amountA -= amountA.mulWad(x1VaultReward);

            // Reduce amountB by harvestFee percentage
            amountB -= amountB.mulWad(x1VaultReward);
        }

        // Mint LP directly to msg.sender which must be an initialized collateral, else transaction would have
        // reverted by now.
        (, , liquidity) = DEX_ROUTER.addLiquidity(
            tokenA,
            tokenB,
            false,
            amountA,
            amountB,
            0,
            0,
            cygnus,
            block.timestamp
        );
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusHarvester
     */
    function harvestersLength() public view override returns (uint256) {
        // Return the amount of initialized harvesters
        return allHarvesters.length;
    }

    /**
     *  @inheritdoc ICygnusHarvester
     */
    function x1RewardTokensLength() public view override returns (uint256) {
        // Return the amount of tokens we are sending to X1 Vault
        return allX1RewardTokens.length;
    }

    /**
     *  @inheritdoc ICygnusHarvester
     */
    function rewardTokenBalance(address rewardToken) public view override returns (uint256) {
        // Get the balance of `rewardToken` which is the left-over after harvests
        return rewardToken.balanceOf(address(this));
    }

    /**
     *  @inheritdoc ICygnusHarvester
     */
    function rewardTokenBalanceAtIndex(uint256 index) public view override returns (uint256) {
        // Get our balance of reward token at `index`
        return allX1RewardTokens[index].balanceOf(address(this));
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusHarvester
     */
    function reinvestRewards(
        address collateral,
        bytes[] calldata swapData
    ) external override returns (uint256 liquidity) {
        // ─────────────────────── 1. Get harvester
        // Harvester for collateral
        Harvester storage harvester = getHarvester[collateral];

        /// @custom:error HarvesterNotInitialized
        if (harvester.underlying == address(0)) {
            revert CygnusHarvester__HarvesterNotInitialized({ harvester: msg.sender });
        }

        // ─────────────────────── 2. Harvest and convert rewards to optimal token
        // Harvest rewards
        (address[] memory tokens, uint256[] memory amounts) = ICygnusCollateral(collateral).getRewards();

        // Get want token
        address wantToken = harvester.wantToken;

        // Amount of want token
        uint256 wantAmount;

        // Loop through each token reward
        for (uint256 i = 0; i < tokens.length; ) {
            // If token is not want and we have rewards swap
            if (amounts[i] > 0) {
                // ─────────────── 3. Swap reward to `wantToken`
                // Transfer token from Collateral
                tokens[i].safeTransferFrom(collateral, address(this), amounts[i]);

                // Check that token is not wantToken
                if (tokens[i] != wantToken) {
                    // Pass swap data `i` along with the token to be swapped
                    wantAmount += swapTokensPrivateInch(
                        // The swap data for token `i` from harvested rewards
                        swapData[i],
                        // The token being swapped
                        tokens[i],
                        // The token we should be receiving.
                        // Passing any other token in the 1inch call will cause tx to revert
                        wantToken,
                        // The amount of token `i` we are swapping to wantToken and
                        // reinvesting for the borrowable pools
                        amounts[i]
                    );
                }
                // token is wantToken, add to `wantAmount`
                else wantAmount += amounts[i];
            }
            unchecked {
                // Next iteration
                i++;
            }
        }

        /// @custom;error CantReinvestZero
        if (wantAmount == 0) revert CygnusHarvester__CantReinvestZero();

        // ─────────────────────── 4. Convert wantToken to LP Token underlying
        // Reserves of wantToken
        uint256 reservesA = IERC20(wantToken).balanceOf(harvester.underlying);

        // Get optimal swap amount of wantToken (use maximum swap fee for velo which is 0.05%, ie 9995/1000)
        uint256 swapAmount = CygnusDexLib.optimalDepositA(wantAmount, reservesA, 5);

        // Swap optimal amount to wantToken to needToken for liquidity deposit
        uint256 needTokenAmount = swapTokensPrivateDex(wantToken, harvester.needToken, swapAmount);

        // Add liquidity and get LP Token
        liquidity = addLiquidityPrivate(
            wantToken,
            harvester.needToken,
            wantAmount - swapAmount,
            needTokenAmount,
            collateral
        );

        // Reinvest
        ICygnusCollateral(collateral).reinvestRewards_y7b(liquidity);
    }

    function harvestToVault(address collateral) external nonReentrant {
        /// @custom:error X1VaultRewardNotOne
        if (x1VaultReward != 1e18) revert CygnusHarvester__X1VaultRewardNotOne();

        // Harvest rewards
        (address[] memory tokens, uint256[] memory amounts) = ICygnusCollateral(collateral).getRewards();

        // Loop through each token
        for (uint256 i = 0; i < tokens.length; i++) {
            // If amount `i` is greater than 0
            if (amounts[i] > 0) {
                // Caller reward
                uint256 callerReward = amounts[i].mulWad(HARVESTER_REWARD);

                // Transfer to harvester
                tokens[i].safeTransferFrom(collateral, msg.sender, callerReward);

                // Transfer the rest to the vault
                tokens[i].safeTransferFrom(collateral, cygnusX1Vault, amounts[i] - callerReward);
            }
        }
    }

    //  Admin 👽  //

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function initializeHarvester(address collateral) external override cygnusAdmin {
        // Get harvester from msg.sender
        Harvester memory harvester = getHarvester[collateral];

        /// @custom:error HarvesterAlreadyInitialized
        if (harvester.underlying != address(0)) {
            revert CygnusHarvester__HarvesterAlreadyInitialized({ harvester: collateral });
        }

        // Get the LP Token pair for this collateral
        address lpTokenPair = ICygnusCollateral(collateral).underlying();

        // Get optimal wantToken to swap rewards to and cache the other token of the LP
        (address wantToken, address needToken) = getOptimalDstToken(lpTokenPair);

        // Set harvester
        getHarvester[collateral] = Harvester({ underlying: lpTokenPair, wantToken: wantToken, needToken: needToken });

        // Check and add tokenA to reward token list
        addRewardTokenPrivate(wantToken);

        // Check and add tokenB to reward token list
        addRewardTokenPrivate(needToken);

        // Add to array
        allHarvesters.push(collateral);

        /// @custom:event InitializeHarvester
        emit InitializeHarvester(allHarvesters.length, collateral, lpTokenPair);
    }

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function newX1VaultReward(uint256 vaultReward) external override cygnusAdmin {
        /// @custom:error VaultRewardNotInRange
        if (vaultReward > MAX_X1_REWARD || vaultReward < MIN_X1_REWARD) {
            revert CygnusHarvester__X1RewardNotInRange({ min: MIN_X1_REWARD, max: MAX_X1_REWARD, reward: vaultReward });
        }

        // Old percentage which was sent to the X1 Vault from each harvest
        uint256 oldX1VaultReward = vaultReward;

        // Store new percentage
        x1VaultReward = vaultReward;

        /// @custom:event NewX1VaultReward
        emit NewX1VaultReward(msg.sender, oldX1VaultReward, vaultReward);
    }

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security non-reentrant
     */
    function collectX1RewardsAll() external override nonReentrant {
        // Gas savings, get all reward tokens
        address[] memory rewardTokens = allX1RewardTokens;

        // Start at 0
        uint256 totalTokens;

        // Loop through each reward token
        for (uint256 i = 0; i < rewardTokens.length; ) {
            // Get our balance of reward token `i`
            uint256 balance = rewardTokens[i].balanceOf(address(this));

            if (balance > 0) {
                // Transfer token balance to X1 Vault
                rewardTokens[i].safeTransfer(cygnusX1Vault, balance);

                // Add to total tokens transfered to vault
                unchecked {
                    totalTokens++;
                }
            }
            unchecked {
                i++;
            }
        }

        /// @custom:event CygnusX1VaultCollect
        emit CygnusX1VaultCollect(lastX1Collect = block.timestamp, msg.sender, totalTokens);
    }

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function collectX1RewardToken(address rewardToken) external override cygnusAdmin {
        // Get our balance of reward token `i`
        uint256 balance = rewardToken.balanceOf(address(this));

        if (balance > 0) {
            // Transfer token balance to X1 Vault
            rewardToken.safeTransfer(cygnusX1Vault, balance);
        }

        /// @custom:event CygnusX1VaultCollect
        emit CygnusX1VaultCollect(lastX1Collect = block.timestamp, msg.sender, 1);
    }

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function addX1VaultRewardToken(address rewardToken) external override cygnusAdmin {
        // Add reward private
        // Checks the array and if token does not exist then we add and emit an event,
        // else it returns and escapes function. TX always succeeds.
        addRewardTokenPrivate(rewardToken);
    }

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function sweepToken(address token) external override cygnusAdmin {
        // Get token balance
        uint256 balance = token.balanceOf(address(this));

        // If positive balance then transfer
        if (balance > 0) token.safeTransfer(msg.sender, balance);
    }
}
