// SPDX-License-Identifier: Unlicensed

pragma solidity >=0.8.4;

// Dependencies
import { ICygnusTerminal } from "./ICygnusTerminal.sol";

// Interfaces
import { IDexPair } from "./IDexPair.sol";
import { IDexRouter02 } from "./IDexRouter.sol";
import { IMiniChef } from "./IMiniChef.sol";

/**
 *  @title ICygnusCollateralVoid The interface for the masterchef
 */
interface ICygnusCollateralVoid is ICygnusTerminal {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error InvalidRewardsToken The rewards token can't be the zero address
     */
    error CygnusCollateralChef__VoidAlreadyInitialized(address tokenReward);

    /**
     *  @custom:error OnlyAccountsAllowed Avoid contracts
     */
    error CygnusCollateralChef__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @custom:error NotNativeTokenSender Avoid receiving unless sender is native token
     */
    error CygnusCollateralVoid__NotNativeTokenSender(address sender, address origin);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Logs when the chef is initialized and rewards can be reinvested
     *  @param _dexRouter The address of the router that is used by the DEX (must be UniswapV2 compatible)
     *  @param _rewarder The address of the masterchef or rewarder contract (Must be compatible with masterchef)
     *  @param _rewardsToken The address of the token that rewards are paid in
     *  @param _pid The Pool ID of this LP Token pair in Masterchef's contract
     *  @param _swapFeeFactor The swap fee factor used by this DEX
     *  @custom:event Reinvest Emitted when reinvesting rewards from Masterchef
     */
    event ChargeVoid(
        IDexRouter02 _dexRouter,
        IMiniChef _rewarder,
        address _rewardsToken,
        uint256 _pid,
        uint256 _swapFeeFactor
    );

    /**
     *  @notice Logs when rewards are reinvested
     *  @param shuttle The address of this shuttle
     *  @param reinvestor The address of the caller who reinvested reward and receives bounty
     *  @param rewardBalance The amount reinvested
     *  @param reinvestReward The reward received by the reinvestor
     *  @custom:event Reinvest Emitted when reinvesting rewards from Masterchef
     */
    event RechargeVoid(address indexed shuttle, address reinvestor, uint256 rewardBalance, uint256 reinvestReward);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    function nativeToken() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function pid() external view returns (uint256);

    function rewarder() external view returns (IMiniChef);

    /**
     *  @return The address of the router from the DEX this shuttle's LP Token belongs to
     */
    function dexRouter() external view returns (IDexRouter02);

    /**
     *  @return The address of the token that is earned as a bonus by providing liquidity to the DEX
     */
    function rewardsToken() external view returns (address);

    /**
     *  @return The fee that each DEX charges for a swap (usually 0.3%)
     */
    function swapFeeFactor() external view returns (uint256);

    /**
     *  @return The reward that is handed to the user who reinvested the shuttle's rewards to buy more LP Tokens
     */
    function REINVEST_REWARD() external view returns (uint256);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Reinvests all rewards from the masterchef to buy more LP Tokens
     */
    function chargeVoid() external;

    function voidActivated() external view returns (bool);
}
