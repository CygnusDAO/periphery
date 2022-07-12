// SPDX-License-Identifier: Unlicensed

/// @notice this interface is used for CygnusNebula contracts
pragma solidity >=0.8.4;

interface ICygnusNebulaFactory {
    /**
     *  @custom:event Emitted when a LP Pair is created
     *  @param underlying Address of the underlying LP Token
     *  @param token0 Indexed address of the TokenA of the underlying LP Token
     *  @param token1 Indexed address of the TokenB of the underlying LP Token
     *  @param collateral Address of the Cygnus Collateral token
     *  @param borrowTokenA Address of the Cygnus Borrow TokenA
     *  @param borrowTokenB Address of the Cygnus Borrow TokenB
     *  @param cygnusPoolID Address of the underlying LP Token
     */
    event PairCreated(
        address indexed underlying,
        address indexed token0,
        address indexed token1,
        address collateral,
        address borrowTokenA,
        address borrowTokenB,
        uint256 cygnusPoolID
    );

    /**
     *  @return addres
     */
    function feeTo() external view returns (address);

    /// @return address
    function feeToSetter() external view returns (address);

    /// @return address
    function migrator() external view returns (address);

    /// @return pair address of token A and B
    /// @param tokenA address of token A
    /// @param tokenB address of token B
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    /// @return pair is address of LP Token of tokenA and tokenB
    /// @param tokenA address of token A
    /// @param tokenB address of token B
    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

    function setMigrator(address) external;
}
