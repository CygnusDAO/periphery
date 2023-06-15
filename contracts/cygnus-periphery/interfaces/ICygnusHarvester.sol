// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

import {IHangar18} from "./core/IHangar18.sol";
import {IAggregationRouterV5} from "./core/IAggregationRouterV5.sol";

// Interface to interact with harvester if needed
interface ICygnusHarvester {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */
    /**
     *  @dev Reverts if tx.origin is different to msg.sender
     *
     *  @param sender The sender of the transaction
     *  @param origin The origin of the transaction
     *
     *  @custom:error OnlyAccountsAllowed
     */
    error CygnusHarvester__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @dev Reverts if the receiver of the swap is not this contract
     *
     *  @param dstReceiver The expected receiver address of the swap
     *  @param receiver The actual receiver address of the swap
     *
     *  @custom:error DstReceiverNotValid
     */
    error CygnusHarvester__DstReceiverNotValid(address dstReceiver, address receiver);

    /**
     *  @dev Reverts if the token received is not underlying
     *
     *  @param dstToken The expected address of the token received
     *  @param token The actual address of the token received
     *
     *  @custom:error DstTokenNotValid
     */
    error CygnusHarvester__DstTokenNotValid(address dstToken, address token);

    /**
     *  @dev Reverts if the src token we are swapping is not the rewards token
     *
     *  @param srcToken The expected address of the token to be swapped
     *  @param token The actual address of the token to be swapped
     *
     *  @custom:error SrcTokenNotValid
     */
    error CygnusHarvester__SrcTokenNotValid(address srcToken, address token);

    /**
     *  @dev Reverts if the harvester is not initialized
     *
     *  @param harvester The address of the collateral passed
     *
     *  @custom:error HarvesterNotInitialized
     */
    error CygnusHarvester__HarvesterNotInitialized(address harvester);

    /**
     *  @dev Reverts if the harvester is already initialized
     *
     *  @param harvester The address of the collateral passed
     *
     *  @custom:error HarvesterAlreadyInitialized
     */
    error CygnusHarvester__HarvesterAlreadyInitialized(address harvester);

    /**
     *  @dev Reverts if msg.sender is not harvester admin
     *
     *  @param sender The address of the msg.sender
     *  @param admin The address of the harvester admin
     *
     *  @custom:error MsgSenderNotAdmin
     */
    error CygnusHarvester__MsgSenderNotAdmin(address sender, address admin);

    /**
     *  @dev Reverts if reinvest amount is zero
     *
     *  @custom:error CantReinvestZero
     */
    error CygnusHarvester__CantReinvestZero();

    /**
     *  @dev Reverts when the new fee exceeds the maximum fee limit.
     *
     *  @param newFee The new fee that was attempted to be set.
     *  @param maxFee The maximum fee allowed for this operation.
     *
     *  @custom:error FeeExceedsLimit
     */
    error CygnusHarvester__FeeExceedsLimit(uint256 newFee, uint256 maxFee);

    /**
     *  @dev Reverts when setting the X1 Vault reward outside ranges allowed
     *
     *  @param min The minimum percentage allowed
     *  @param max The maximum percentage allowed.
     *  @param reward The reward percentage we are attempting to set
     *
     *  @custom:error X1RewardNotInRange
     */
    error CygnusHarvester__X1RewardNotInRange(uint256 min, uint256 max, uint256 reward);

    /**
     *  @dev Reverts when admin attempts to sweep a token that is a rewards token
     *
     *  @param token The address of the token we are attempting to sweep
     *
     *  @custom:error CantSweepRewardToken
     */
    error CygnusHarvester__CantSweepRewardToken(address token);

    /**
     *  @dev Reverts when harvesting to the vault (without reinvesting) but the x1VaultReward is not 100%
     *
     *  @custom:error X1VaultRewardNotOne
     */
    error CygnusHarvester__X1VaultRewardNotOne();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when a borrowable harvester is initialized for a shuttle.
     *
     *  @param harvesterId The ID for this harvester
     *  @param poolToken The address of the Cygnus Collateral or Cygnus Borrow contract
     *  @param underlying The address of the underlying LP or stablecoin for `poolToken`
     *
     *  @custom:event InitializeCollateralHarvester
     */
    event InitializeHarvester(uint256 indexed harvesterId, address poolToken, address underlying);

    /**
     *  @dev Logs when the harvest fee is updated. This is the fee that DAO keeps from each reinvest (default is 0)
     *
     *  @param sender The address that updated the fee.
     *  @param oldFee The previous harvest fee.
     *  @param newFee The new harvest fee.
     *
     *  @custom:event NewHarvestFee
     */
    event NewHarvestFee(address indexed sender, uint256 oldFee, uint256 newFee);

    /**
     *  @dev Logs when the x1 vault reward is updated for a given terminal token.
     *
     *  @param sender The address that called the function to update the reward
     *  @param oldReward The old value of the reward before the update
     *  @param newReward The new value of the reward after the update
     *
     *  @custom:event NewX1VaultReward
     */
    event NewX1VaultReward(address indexed sender, uint256 oldReward, uint256 newReward);

    /**
     *  @dev Logs when a new reward token is added
     *
     *  @param newToken The address of the new reward token
     *  @param rewardTokensLength The total amount of reward tokens
     *
     *  @custom:event NewX1RewardToken
     */
    event NewX1RewardToken(address newToken, uint256 rewardTokensLength);

    /**
     *  @dev Logs when the X1 vault collects rewards
     *
     *  @param timestamp The current timestamp of the collect
     *  @param sender The msg.sender
     *  @param tokensLength The amount of reward tokens we sent to vault (even if balance is 0)
     *
     *  @custom:event CygnusX1VaultCollect
     */
    event CygnusX1VaultCollect(uint256 timestamp, address sender, uint256 tokensLength);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Max reward from each harvest allowed to be sent to the X1 Vault, expressed as a fixed point decimal with 18 decimals.
     */
    function MAX_X1_REWARD() external pure returns (uint256);

    /**
     *  @dev Min reward from each harvest allowed to be sent to the X1 Vault, expressed as a fixed point decimal with 18 decimals.
     */
    function MIN_X1_REWARD() external pure returns (uint256);

    /**
     *  @dev Returns the address of the harvester at the given index.
     *
     *  @param index The index of the harvester.
     *  @return The address of the harvester at the given index.
     */
    function allHarvesters(uint256 index) external view returns (address);

    /**
     *  @dev Returns the reward token at `index`
     *
     *  @param index The index in the array.
     *  @return The address of the reward token at the given index.
     */
    function allX1RewardTokens(uint256 index) external view returns (address);

    /**
     *  @dev Returns the name of the contract.
     *
     *  @return The name of the contract.
     */
    function name() external pure returns (string memory);

    /**
     *  @dev Returns the current percentage of rewards that is kept for the Cygnus X1 Vault on this chain.
     *
     *  @return The current X1 Vault reward.
     */
    function x1VaultReward() external view returns (uint256);

    /**
     *  @dev Returns the Hangar18 contract.
     *
     *  @return The Hangar18 contract.
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @dev Returns the address of the native token.
     *
     *  @return The address of the native token.
     */
    function nativeToken() external view returns (address);

    /**
     *  @dev Returns the address of the CygnusX1Vault contract.
     *
     *  @return The address of the CygnusX1Vault contract.
     */
    function cygnusX1Vault() external view returns (address);

    /**
     *  @dev Returns the address of the AggregationRouterV5 contract, used to make the 1inch swaps
     *
     *  @return The address of the AggregationRouterV5 contract.
     */
    function ONE_INCH_ROUTER_V5() external pure returns (IAggregationRouterV5);

    /**
     *  @dev Returns the amount of collaterals initialized
     */
    function harvestersLength() external view returns (uint256);

    /**
     *  @dev Returns the amount of reward tokens to be sent to the X1 Vault
     */
    function x1RewardTokensLength() external view returns (uint256);

    /**
     *  @notice Returns the balance of the specified reward token held by the contract.
     *
     *  @param rewardToken The address of the reward token to check the balance of.
     *
     *  @return The balance of the specified reward token.
     */
    function rewardTokenBalance(address rewardToken) external view returns (uint256);

    /**
     *  @notice Returns the balance of the index token at the specified index.
     *  @notice Helpful to use in case we use a script or a collector function to get all reward tokens of the array
     *
     *  @param index The index of the index token to check the balance of.
     *
     *  @return The balance of the index token at the specified index.
     */
    function rewardTokenBalanceAtIndex(uint256 index) external view returns (uint256);

    /**
     *  @notice Returns the timestamp of the last X1 Vault collect. Updates after
     *
     *  @return Timestamp of the last collect
     */
    function lastX1Collect() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice harvest rewards from the underlying protocols, swap them to `wanttoken` and buys more underlying
     *
     *  @param swapData List of swap data for each token.
     *  @return lpTokens Amount of LP tokens minted from the liquidity deposit.
     *
     *  Requirements:
     *  - `msg.sender` must be an initialized harvester.
     *  - `wantToken` must be set in the harvester.
     *  - At least one non-zero reward amount must be harvested.
     */
    // prettier-ignore
    function reinvestRewards(address terminalToken, bytes[] calldata swapData) external returns (uint256);

    /**
     *  @notice Collects all pending rewards of approved tokens and sends it to the X1 vault
     *
     *  @custom:security non-reentrant
     */
    function collectX1RewardsAll() external;

    /**  Admin 👽  **/

    /**
     *  @notice Admin 👽
     *  @notice Initializes a new harvester for the provided `terminalToken` collateral.
     *
     *  @param collateral The collateral token to initialize the harvester for.
     *
     *  @custom:security only-admin
     */
    function initializeHarvester(address collateral) external;

    /**
     *  @notice Admin 👽
     *  @notice Allows the Cygnus admin to set a new x1VaultReward
     *  @notice must be within min-max ranges allowed
     *
     *  @param vaultreward the new x1vaultreward to set.
     *
     *  @custom:security only-admin
     */
    function newX1VaultReward(uint256 vaultreward) external;

    /**
     *  @notice Admin 👽
     *  @notice Add a reward token to be collected by the X1 Vault
     *
     *  @param token The address of the token
     *
     *  @custom:security only-admin
     */
    function addX1VaultRewardToken(address token) external;

    /**
     *  @notice Admin 👽
     *  @notice Collects the pending reward for the specified reward token and sends it to the X1 vault
     *
     *  @param rewardToken The address of the reward token to collect.
     *
     *  @custom:security only-admin
     */
    function collectX1RewardToken(address rewardToken) external;

    /**
     *  @notice Admin 👽
     *  @notice Recovers any ERC20 token accidentally sent to this contract, sent to msg.sender
     *
     *  @param token The address of the token we are recovering
     *
     *  @custom:security only-admin
     */
    function sweepToken(address token) external;
}
