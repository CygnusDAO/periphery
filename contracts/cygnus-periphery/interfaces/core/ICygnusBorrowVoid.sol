// SPDX-License-Identifier: Unlicense

pragma solidity >=0.8.17;

// Dependencies
import {ICygnusBorrowModel} from "./ICygnusBorrowModel.sol";

// Stargate
import {ICygnusHarvester} from "./ICygnusHarvester.sol";

/**
 *  @title ICygnusBorrowVoid
 */
interface ICygnusBorrowVoid is ICygnusBorrowModel {
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
    error CygnusBorrowVoid__OnlyEOAAllowed(address sender, address origin);

    /**
     *  @dev Strategy specific error
     *  @dev Reverts if there was a mint or redeem error on the cToken
     *
     *  @param errorcode The errorcode given by the cToken
     *
     *  @custom:error CTokenError
     */
    error CygnusBorrowVoid__CTokenError(uint256 errorcode);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. CUSTOM EVENTS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Logs when the strategy is first initialized or re-approves contracts
     *
     *  @param underlying The address of the underlying stablecoin
     *  @param shuttleId The unique ID of the lending pool
     *  @param sender The address of the msg.sender (admin)
     *
     *  @custom:event ChargeVoid
     */
    event ChargeVoid(address underlying, uint256 shuttleId, address sender);

    /**
     *  @dev Logs when user reinvests rewards
     *
     *  @param reinvestor The address of the caller who reinvested reward and received bounty
     *  @param liquidity The amount of underlying USD received and reinvested
     *  @param timestamp The timestamp of the reinvest
     *
     *  @custom:event RechargeVoid
     */
    event RechargeVoid(address indexed reinvestor, uint256 liquidity, uint256 timestamp);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @return harvester The address of the harvester contract
     */
    function harvester() external view returns (ICygnusHarvester);

    /**
     *  @return lastReinvest Timestamp of the last reinvest performed by the harvester contract
     */
    function lastReinvest() external view returns (uint256);


    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @return rewarder The address of the rewarder contract
     */
    function rewarder() external view returns (address);

    /**
     *  @return rewardToken The address of the main reward token
     */
    function rewardToken() external view returns (address);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @notice Only EOA can call
     *  @notice Get the pending rewards manually - helpful to get rewards through static calls
     *
     *  @return tokens The addresses of the reward tokens earned by harvesting rewards
     *  @return amounts The amounts of each token received
     *
     *  @custom:security non-reentrant only-eoa
     */
    function getRewards() external returns (address[] memory tokens, uint256[] memory amounts);

    /**
     *  @notice Only EOA can call
     *  @notice Reinvests all rewards from the rewarder to buy more USD to then deposit back into the rewarder
     *          This makes totalBalance increase in this contract, increasing the exchangeRate between
     *          CygUSD and underlying and thus lowering utilization rate and borrow rate
     *
     *  @custom:security non-reentrant only-eoa
     */
    function reinvestRewards_y7b(uint256 liquidity) external;

    /**
     *  @notice Only EOA can call
     *  @notice Charges approvals needed for deposits and withdrawals along with setting rewarders (if any)
     *
     *  @custom:security non-reentrant only-eoa
     */
    function chargeVoid() external;

    /**
     *  @notice Admin 👽
     *  @notice Sets the harvester address to harvest and reinvest rewards into more underlying
     *
     *  @param _harvester The address of the new harvester contract
     *
     *  @custom:security non-reentrant only-admin
     */
    function setHarvester(ICygnusHarvester _harvester) external;
}
