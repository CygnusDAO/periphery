// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusHarvester} from "./interfaces/ICygnusHarvester.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries
import {SafeTransferLib} from "./libraries/SafeTransferLib.sol";
import {FixedPointMathLib} from "./libraries/FixedPointMathLib.sol";

// Interfaces
import {IERC20} from "./interfaces/core/IERC20.sol";
import {IHangar18} from "./interfaces/core/IHangar18.sol";
import {ICygnusBorrow} from "./interfaces/core/ICygnusBorrow.sol";
import {IAggregationRouterV5, IAggregationExecutor} from "./interfaces/core/IAggregationRouterV5.sol";

/**
 *  @title  BorrowableHarvester Contract that harvests rewards from a CygnusBorrow contract and reinvests it to
 *          add it to the totalBalance. It uses 1inch aggregator on-chain to swap the rewards to the underlying
 *          borrowable asset (USDC)
 *  @author CygnusDAO
 *  @notice The harvester should only be called from the CygnusBorrow contract via the `reinvestRewards` function.
 *          The function should harvest the rewards and send to this contract the rewards + amounts + swapData.
 *          In order to build the 1inch swap data, the caller can call `getRewards()` via a static call in the
 *          borrowable contract to receive an array of tokens and an array of amounts harvested.
 *  @notice We send USDC to the borrowable contract instead of this address, as opposed to collateral strategies,
 *          saving us a transfer call. See destReceiver in 1inch function.
 *
 *                         ┌───────────────┐       ┌─────────────┐            ┌─────────────┐
 *                         │ 1. Borrowable │       │ 2. Rewarder │            │  4. 1Inch   │
 *                         └───────────────┘       └─────────────┘            └─────────────┘
 *                                 |                      |                          |
 *                                 |    Deposit USDC      |                          |
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
 *                                 |                      |   Swap Rewards Tokens    |
 *                                 |                      |------------------------->|
 *                                 |                                                 |
 *                                 |              Send USDC to borrowable            |
 *                                 |<------------------------------------------------|
 *
 */
contract BorrowableHarvester is ICygnusHarvester, ReentrancyGuard {
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
     *  @custom:struct Harvester Struct for the strategy
     *  @custom:member underlying Address of the borrowable's underlying (stablecoin)
     *  @custom:member wantToken Address of the optimal token for swaps. Harvester can only swap to this token, else reverts.
     */
    struct Harvester {
        address underlying;
        address wantToken;
    }

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
    uint256 public constant override MIN_X1_REWARD = 0;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    uint256 public constant override MAX_X1_REWARD = 1e18;

    /**
     *  @inheritdoc ICygnusHarvester
     */
    string public constant override name = "Cygnus Harvester: Sonne Rewards";

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
            revert CygnusHarvester__MsgSenderNotAdmin({sender: msg.sender, admin: admin});
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
     *       - The `dstReceiver` must be an initialized borrowable
     *  @param swapData Encoded data that specifies the swap details for the 1inch aggregator
     *  @param token The token we should be swapping
     *  @param amount The updated amount of tokens to be swapped.
     *  @return amountOut The amount of `dstToken` received after the swap.
     */
    function swapTokensPrivateInch(
        bytes calldata swapData,
        address token,
        address wantToken,
        uint256 amount,
        address receiver
    ) private returns (uint256 amountOut) {
        // Get aggregation executor, swap params and the encoded calls for the executor from 1inch API call
        // prettier-ignore
        (address caller, IAggregationRouterV5.SwapDescription memory desc, /* permit */, bytes memory data) = abi
            .decode(swapData, (address, IAggregationRouterV5.SwapDescription, bytes, bytes));

        // Update swap amount to current balance of src token (if needed)
        if (desc.amount != amount) desc.amount = amount;

        /// @custom:error SrcTokenNotValid Avoid swapping anything but rewards token
        if (address(desc.srcToken) != token) {
            revert CygnusHarvester__SrcTokenNotValid({srcToken: address(desc.srcToken), token: token});
        }

        /// @custom:error DstTokenNotValid Avoid swapping to anything but the want token
        if (address(desc.dstToken) != wantToken) {
            revert CygnusHarvester__DstTokenNotValid({dstToken: address(desc.dstToken), token: wantToken});
        }

        // NOTE: We optimistically send the swap amount to an initialized borrowable. It's odd but saves us from having to do
        //       a transfer

        /// @custom:error DstReceiverNotValid Avoid swapping to another address except borrowable
        if (desc.dstReceiver != receiver) {
            revert CygnusHarvester__DstReceiverNotValid({dstReceiver: desc.dstReceiver, receiver: msg.sender}); //
        }

        // Allow 1inch router to access our `srcToken` (REWARDS_TOKEN)
        // This is safe because we only approve a constant (1inch router) and we only use `swap()` from the router which
        // transfers from sender
        approveTokenPrivate(address(desc.srcToken), address(ONE_INCH_ROUTER_V5), desc.amount);

        // Swap `srcToken` to `dstToken` with no permit
        (amountOut, ) = ONE_INCH_ROUTER_V5.swap(IAggregationExecutor(caller), desc, new bytes(0), data);
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
     *  @dev Harvest rewards and add liquidity to the pool
     *  @param swapData The 1inch swap data for each token
     *  @return liquidity The amount of LP tokens received from adding liquidity
     */
    function reinvestRewards(address borrowable, bytes[] calldata swapData) external override returns (uint256 liquidity) {
        // ─────────────────────── 1. Get harvester
        // Harvester for borrowable
        Harvester memory harvester = getHarvester[borrowable];

        /// @custom:error HarvesterNotInitialized
        if (harvester.underlying == address(0)) {
            revert CygnusHarvester__HarvesterNotInitialized({harvester: msg.sender});
        }

        // Harvest rewards
        (address[] memory tokens, uint256[] memory amounts) = ICygnusBorrow(borrowable).getRewards();

        // ─────────────────────── 2. Harvest and convert rewards to optimal token

        // Loop through each token reward
        for (uint256 i = 0; i < tokens.length; ) {
            // If token is not want and we have rewards swap
            if (amounts[i] > 0) {
                // ─────────────── 3. Swap reward to `wantToken`
                // Transfer token from Collateral
                tokens[i].safeTransferFrom(msg.sender, address(this), amounts[i]);

                // Check that token is not wantToken
                if (tokens[i] != harvester.wantToken) {
                    // Pass swap data `i` along with the token to be swapped
                    liquidity += swapTokensPrivateInch(
                        // The swap data for token `i` from harvested rewards
                        swapData[i],
                        // The token being swapped
                        tokens[i],
                        // The token we should be receiving.
                        // Passing any other token in the 1inch call will cause tx to revert
                        harvester.wantToken,
                        // The amount of token `i` we are swapping to wantToken and
                        // reinvesting for the borrowable pools
                        amounts[i],
                        // Receiver
                        borrowable
                    );
                }
                // token is wantToken, add to liquidity
                else liquidity += amounts[i];
            }
            unchecked {
                // Next iteration
                i++;
            }
        }

        /// @custom;error CantReinvestZero
        if (liquidity == 0) revert CygnusHarvester__CantReinvestZero();

        // Never underflows
        unchecked {
            // Reduce liquidity by harvestFee percentage
            liquidity -= liquidity.mulWad(x1VaultReward);
        }

        // Reinvest
        ICygnusBorrow(borrowable).reinvestRewards_y7b(liquidity);
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
        for (uint256 i = 0; i < rewardTokens.length; i++) {
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
        }

        /// @custom:event CygnusX1VaultCollect
        emit CygnusX1VaultCollect(lastX1Collect = block.timestamp, msg.sender, totalTokens);
    }

    //  Admin 👽  //

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function initializeHarvester(address borrowable) external override cygnusAdmin {
        // Get harvester from msg.sender
        Harvester memory harvester = getHarvester[borrowable];

        /// @custom:error HarvesterAlreadyInitialized
        if (harvester.underlying != address(0)) {
            revert CygnusHarvester__HarvesterAlreadyInitialized({harvester: borrowable});
        }

        // Get the stablecoin underlying for this borrowable
        address usd = ICygnusBorrow(borrowable).underlying();

        // Set harvester
        getHarvester[borrowable] = Harvester({underlying: usd, wantToken: usd});

        // Check and add tokenA to reward token list
        addRewardTokenPrivate(usd);

        // Add to array
        allHarvesters.push(borrowable);

        /// @custom:event InitializeHarvester
        emit InitializeHarvester(allHarvesters.length, borrowable, usd);
    }

    /**
     *  @inheritdoc ICygnusHarvester
     *  @custom:security only-admin 👽
     */
    function newX1VaultReward(uint256 vaultReward) external override cygnusAdmin {
        /// @custom:error VaultRewardNotInRange
        if (vaultReward > MAX_X1_REWARD || vaultReward < MIN_X1_REWARD) {
            revert CygnusHarvester__X1RewardNotInRange({min: MIN_X1_REWARD, max: MAX_X1_REWARD, reward: vaultReward});
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
