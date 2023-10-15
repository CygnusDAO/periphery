//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  ICygnusAltairX.sol
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
pragma solidity >=0.8.17;

// Interfaces
import {IERC20} from "./core/IERC20.sol";
import {IHangar18} from "./core/IHangar18.sol";
import {IWrappedNative} from "./IWrappedNative.sol";
import {ICygnusNebulaRegistry} from "./core/ICygnusNebulaRegistry.sol";

/**
 *  @notice Interface to interact with Cygnus' router contract
 */
interface ICygnusAltairX {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Reverts when the msg sender is not the collateral contract
     *
     *  @custom:error MsgSenderNotCollateral
     */
    error CygnusAltair__MsgSenderNotCollateral();

    /**
     *  @dev Reverts when the msg sender is not the router in the leverage function
     *
     *  @custom:error MsgSenderNotRouter
     */
    error CygnusAltair__MsgSenderNotRouter();

    /**
     *  @dev Reverts when the msg sender is not the borrow contract
     *
     *  @custom:error MsgSenderNotBorrowable
     */
    error CygnusAltair__MsgSenderNotBorrowable();

    /**
     *  @dev Reverts when the paraswap transaction fails
     *
     *  @custom:error ParaswapTransactionFailed
     */
    error CygnusAltair__ParaswapTransactionFailed();

    /**
     *  @dev Reverts when the 1inch transaction fails
     *
     *  @custom:error OneInchTransactionFailed
     */
    error CygnusAltair__OneInchTransactionFailed();

    /**
     *  @dev Reverts when the 0x swap api transaction fails
     *
     *  @custom:error 0xProjectTransactionFailed
     */
    error CygnusAltair__0xProjectTransactionFailed();

    /**
     *  @dev Reverts when the Open Ocean swap transaction fails
     *
     *  @custom:error OpenOceanTransactionFailed
     */
    error CygnusAltair__OpenOceanTransactionFailed();

    /**
     *  @dev Reverts when USD amount received is less than minimum asked while liquidating
     *
     *  @custom:error InsufficientLiquidateUsd
     */
    error CygnusAltair__InsufficientLiquidateUsd();

    /**
     *  @dev Reverts when amount of USD received is less than the minimum asked
     *
     *  @custom:error InsufficientUSDAmount
     */
    error CygnusAltair__InsufficientUSDAmount();

    /**
     *  @dev Reverts when the swapped amount is less than the min requested
     *
     *  @custom:error InsufficientLPTokenAmount
     */
    error CygnusAltair__InsufficientLPTokenAmount();

    /**
     *  @dev Reverts if the call is not a delegate call
     *
     *  @custom:error OnlyDelegateCall
     */
    error CygnusAltair__OnlyDelegateCall();

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return name The human readable name this router is for
     */
    function name() external view returns (string memory);

    /**
     *  @return PERMIT Uniswap's Permit2 router
     */
    function PERMIT2() external view returns (address);

    /**
     *  @return PARASWAP_AUGUSTUS_SWAPPER_V5 The address of the Paraswap router used to perform the swaps
     */
    function PARASWAP_AUGUSTUS_SWAPPER_V5() external pure returns (address);

    /**
     *  @return ONE_INCH_ROUTER_V5 The address of the 1Inch router used to perform the swaps
     */
    function ONE_INCH_ROUTER_V5() external pure returns (address);

    /**
     *  @return OxPROJECT_EXCHANGE_PROXY The address of 0x's exchange proxy
     */
    function OxPROJECT_EXCHANGE_PROXY() external pure returns (address);

    /**
     *  @return OPEN_OCEAN_EXCHANGE_PROXY The address of OpenOcean's exchange router
     */
    function OPEN_OCEAN_EXCHANGE_PROXY() external pure returns (address);

    /**
     *  @return UNISWAP_V3_ROUTER The address of UniswapV3's swap router
     */
    function UNISWAP_V3_ROUTER() external pure returns (address);

    /**
     *  @return hangar18 The address of the Cygnus factory contract V1 - Used to get the nativeToken and USD address
     */
    function hangar18() external view returns (IHangar18);

    /**
     *  @return usd The address of USD on this chain, used for the leverage/deleverage swaps
     */
    function usd() external view returns (address);

    /**
     *  @return nativeToken The address of the native token on this chain (ie. WETH)
     */
    function nativeToken() external view returns (IWrappedNative);

    /**
     *  @dev Returns the assets and amounts received by redeeming a given amount of underlying liquidity tokens.
     *  @param underlying The address of the underlying liquidity token (e.g., LP token or Balancer BPT).
     *  @param shares The amount of underlying liquidity tokens to redeem.
     *  @param difference Substract a difference from the estimated amount received to make sure router always has enough
     *                    from the actual amount received.
     *  @return tokens An array of addresses representing the received tokens.
     *  @return amounts An array of corresponding amounts received by redeeming the liquidity tokens.
     */
    function getAssetsForShares(
        address underlying,
        uint256 shares,
        uint256 difference
    ) external view returns (address[] memory tokens, uint256[] memory amounts);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @dev Sets or updates the name of the Extension
     *  @param _name The suffix for the new name of the extension
     *  @custom:security only-admin
     */
    function setName(string memory _name) external;

    /**
     *  @dev Sweeps a token to hangar18 admin
     *  @param token The address of the token
     *  @custom:security only-admin
     */
    function sweepToken(address token) external;

    /**
     *  @dev Sweeps the native token (ETH, etc.)
     *  @custom:security only-admin
     */
    function sweepNative() external;
}
