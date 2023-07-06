// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.17;

interface IHypervisor {
    function getTotalAmounts() external view returns (uint256 total0, uint256 total1);

    function getBasePosition() external view returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    function baseLower() external view returns (int24);

    function baseUpper() external view returns (int24);

    function limitLower() external view returns (int24);

    function limitUpper() external view returns (int24);

    function pool() external view returns (address);

    function totalSupply() external view returns (uint256);

    /// @param shares Number of liquidity tokens to redeem as pool assets
    /// @param to Address to which redeemed pool assets are sent
    /// @param from Address from which liquidity tokens are sent
    /// @param minAmounts min amount0,1 returned for shares of liq
    /// @return amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(
        uint256 shares,
        address to,
        address from,
        uint256[4] memory minAmounts
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Deposit tokens
    /// @param deposit0 Amount of token0 transfered from sender to Hypervisor
    /// @param deposit1 Amount of token1 transfered from sender to Hypervisor
    /// @param to Address to which liquidity tokens are minted
    /// @param from Address from which asset tokens are transferred
    /// @param inMin min spend for directDeposit is true
    /// @return shares Quantity of liquidity tokens minted as a result of deposit
    function deposit(
        uint256 deposit0,
        uint256 deposit1,
        address to,
        address from,
        uint256[4] memory inMin
    ) external returns (uint256 shares);

    function token0() external view returns (address);

    function token1() external view returns (address);
}

interface IGammaProxy {
    function deposit(uint256 deposit0, uint256 deposit1, address to, address pos, uint256[4] memory inMin) external returns (uint256 liquidity);

    function getDepositAmount(address, address, uint256) external returns (uint256, uint256);
}
