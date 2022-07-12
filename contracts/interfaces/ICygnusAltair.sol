// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.4;

interface ICygnusAltair {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            1. CUSTOM ERRORS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:error TransactionTooOld Emitted when the current block.timestamp is past deadline
     */
    error CygnusAltair__TransactionTooOld(uint256);

    /**
     *  @custom:error NotnativeTokenSender Emitted when the underlying is not Avax
     */
    error CygnusAltair__NotNativeTokenSender(address poolToken);

    /**
     *  @custom:error InsufficientTokenAmount Emitted when quoting amount is <= 0
     */
    error CygnusAltair__InsufficientTokenAmount(uint256 amountTokenA);

    /**
     *  @custom:error InsufficientTokenAAmount Emitted when optimal Token A amount is less than mininum
     */
    error CygnusAltair__InsufficientTokenAAmount(uint256 amountTokenA);

    /**
     *  @custom:error InsufficientTokenBAmount Emitted when optimal Token B amount is less than mininum
     */
    error CygnusAltair__InsufficientTokenBAmount(uint256 amountTokenB);

    /**
     *  @custom:error InsufficientReserves Emitted when there are no reserves for Token A && Token B
     */
    error CygnusAltair__InsufficientReserves(uint256 reservesTokenA, uint256 reservesTokenB);

    /**
     *  @custom:error MsgSenderNotRouter Emitted when the msg sender is not the router in the leverage function
     */
    error CygnusAltair__MsgSenderNotRouter(address sender, address origin, address borrower);

    /**
     *  @custom:error MsgSenderNotBorrowable Emitted when the msg sender is not the borrow contract
     */
    error CygnusAltair__MsgSenderNotBorrowable(address sender, address borrowable);

    /**
     *  @custom:error MsgSenderNotCollateral Emitted when the msg sender is not the collateral contract
     */
    error CygnusAltair__MsgSenderNotCollateral(address sender, address collateral);

    /**
     *  @custom:error InsufficientBurnAmountA Emitted when the burn amount is 0 for token A
     */
    error CygnusAltair__InsufficientBurnAmountA(uint256 amount);

    /**
     *  @custom:error InsufficientBurnAmountB Emitted when the burn amount is 0 for token B
     */
    error CygnusAltair__InsufficientBurnAmountB(uint256 amount);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @return hangar18 The address of the Cygnus factory contract V1
     */
    function hangar18() external view returns (address);

    /**
     *  @return collateralDeployer The address of the Cygnus collateral deployer contract V1
     */
    function collateralDeployer() external view returns (address);

    /**
     *  @return borrowDeployer The address of the Cygnus borrow deployer contract V1
     */
    function borrowDeployer() external view returns (address);

    /**
     *  @return nativeToken The address of wrapped Avax
     */
    function nativeToken() external view returns (address);

    /**
     *  @return joeRouter The address of TraderJoe's router for swapping from DAI to token0 and token1
     */
    function JOE_ROUTER() external view returns (address);

    /**
     *  @return LOCAL_BYTES Empty bytes 0x
     */
    function LOCAL_BYTES() external view returns (bytes memory);

    /**
     *  @return dai The address of DAI on this chain
     */
    function dai() external view returns (address);

    /**
     *  @notice Function to return collateral and borrow contract addresses for a specific LP Token in Cygnus
     *  @param lpTokenPair The address of the LP Token from DEX
     *  @return collateral The address of the Cygnus collateral for this specific LP Token
     *  @return borrowable The address of the Cygnus borrow contract for this specific LP Token
     */
    function getShuttle(address lpTokenPair) external view returns (address collateral, address borrowable);

    /**
     *  @notice Checks for the optimal liquidity to be added of each token to an LP pair
     *  @param amountTokenADesired The amount of token A Desired
     *  @param amountTokenBDesired The amount of token B Desired
     *  @param amountTokenAMin The minimum amount of token A
     *  @param amountTokenBMin The minimum amount of token B
     */
    function optimalLiquidity(
        address lpTokenPair,
        uint256 amountTokenADesired,
        uint256 amountTokenBDesired,
        uint256 amountTokenAMin,
        uint256 amountTokenBMin
    ) external view returns (uint256 amountTokenA, uint256 amountTokenB);

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Creates a new position in Cygnus for any Erc20 token
     *  @param terminalToken The address of the collateral/borrow pool token that represents the minted position
     *  @param amount The amount to be minted
     *  @param recipient The account that should receive the tokens
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function mint(
        address terminalToken,
        uint256 amount,
        address recipient,
        uint256 deadline
    ) external returns (uint256 tokens);

    /**
     *  @notice Creates a new position in Cygnus when underlying is Avax
     *  @param terminalToken The address of the collateral/borrow pool token that represents the minted position
     *  @param recipient The account that should receive the tokens
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function mintAVAX(
        address terminalToken,
        address recipient,
        uint256 deadline
    ) external payable returns (uint256 tokens);

    /**
     *  @notice Destroys `amount` of tokens, emitting a burn event and decreasing total supply
     *  @param terminalToken The address of the collateral/borrow pool token
     *  @param tokens The Cygnus pool token
     *  @param recipient The account that should receive the tokens
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function redeem(
        address terminalToken,
        uint256 tokens,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external returns (uint256 amount);

    /**
     *  @notice Redeems when underling is AVAX
     *  @param terminalToken The address of the collateral/borrow pool token
     *  @param tokens The amount being redeemed
     *  @param recipient The address of the redeemer
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function redeemAVAX(
        address terminalToken,
        uint256 tokens,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external returns (uint256 amount);

    /**
     *  @notice Main function used in Cygnus to borrow DAI
     *  @param amount Amount of DAI to borrow
     *  @param recipient The address of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function borrow(
        address cygnusAlbireo,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external;

    /**
     *  @notice Main function used in Cygnus to borrow AVAX
     *  @param cygnusAlbireo The address of the Cygnus borrow contract
     *  @param amountAVAX The amount of AVAX being borrowed
     *  @param recipient The address of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function borrowAVAX(
        address cygnusAlbireo,
        uint256 amountAVAX,
        address recipient,
        uint256 deadline,
        bytes memory permitData
    ) external;

    /**
     *  @notice Main function used in Cygnus to repay borrows
     *  @param amountMax The max amount to repay
     *  @param borrower Thea ddress of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function repay(
        address cygnusAlbireo,
        uint256 amountMax,
        address borrower,
        uint256 deadline
    ) external returns (uint256 amount);

    /**
     *  @notice Main function used in Cygnus to repay AVAX
     *  @param cygnusAlbireo The address of Cygnus albireo
     *  @param borrower Thea ddress of the borrower
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function repayAVAX(
        address cygnusAlbireo,
        address borrower,
        uint256 deadline
    ) external payable returns (uint256 amountAVAX);

    /**
     *  @notice Main function used in Cygnus to liquidate borrows
     *  @param cygnusAlbireo The address of Cygnus albireo
     *  @param amountMax The maximum amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidate(
        address cygnusAlbireo,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amount, uint256 seizeTokens);

    /**
     *  @param cygnusAlbireo The address of Cygnus albireo
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidateAVAX(
        address cygnusAlbireo,
        address borrower,
        address recipient,
        uint256 deadline
    ) external payable returns (uint256 amountAVAX, uint256 seizeTokens);

    /**
     *  @notice Function to liquidate a borrower and immediately convert holdings to DAI
     *  @param cygnusAlbireo The address of Cygnus albireo
     *  @param amountMax The amount to liquidate
     *  @param borrower The address of the borrower
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     */
    function liquidateToDai(
        address cygnusAlbireo,
        uint256 amountMax,
        address borrower,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountDai);

    /**
     *  @notice Main leverage function
     *  @param collateral The address of the Cygnus collateral
     *  @param amount The amount to leverage
     *  @param recipient The address of the recipient
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function leverage(
        address collateral,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Function that is called by the CygnusBorrow contract and decodes data to carry out the leverage
     *  @notice Will only succeed if: Caller is borrow contract & Borrow contract was called by router
     *  @param sender Address of the contract that initialized the borrow transaction (address of the router)
     *  @param borrower Address of the borrower that is leveraging
     *  @param borrowAmount The amount to leverage
     *  @param data The encoded byte data passed from the CygnusBorrow contract to the router
     */
    function cygnusBorrow(
        address sender,
        address borrower,
        uint256 borrowAmount,
        bytes calldata data
    ) external;

    /**
     *  @notice Main deleverage function
     *  @param lpTokenPair The address of the LP Token of the lending pool
     *  @param redeemTokens The amount to CygLP to deleverage
     *  @param deadline The time by which the transaction must be included to effect the change
     *  @param permitData The permit calldata (if any)
     */
    function deleverage(
        address lpTokenPair,
        uint256 redeemTokens,
        uint256 deadline,
        bytes calldata permitData
    ) external;

    /**
     *  @notice Function that is called by the CygnusCollateral contract and decodes data to carry out the deleverage
     *  @notice Will only succeed if: Caller is collateral contract & collateral contract was called by router
     *  @param sender Address of the contract that initialized the redeem transaction (address of the router)
     *  @param redeemAmount The amount to deleverage
     *  @param data The encoded byte data passed from the CygnusCollateral contract to the router
     */
    function cygnusRedeem(
        address sender,
        uint256 redeemAmount,
        bytes calldata data
    ) external;
}
