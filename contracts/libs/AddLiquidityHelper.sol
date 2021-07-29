// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


// MyFriendsToken with Governance.
contract AddLiquidityHelper is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public arcadiumAddress;

    // The swap router, modifiable. Will be changed to ArcadiumSwap's router when our own AMM release
    IUniswapV2Router02 public arcadiumSwapRouter;

    /**
     * @notice Constructs the AddLiquidityHelper contract.
     */
    constructor(address _arcadiumAddress, address _router) public  {
        require(_router != address(0), "_router is the zero address");
        require(_arcadiumAddress != address(0), "_arcadiumAddress is the zero address");
        arcadiumAddress = _arcadiumAddress;
        arcadiumSwapRouter = IUniswapV2Router02(_router);
    }

    function addArcadiumLiquidity(address baseTokenAddress, uint256 baseAmount, uint256 nativeAmount) external nonReentrant {
        IERC20(baseTokenAddress).safeTransferFrom(msg.sender, address(this), baseAmount);
        IERC20(arcadiumAddress).safeTransferFrom(msg.sender, address(this), nativeAmount);

        // approve token transfer to cover all possible scenarios
        IERC20(baseTokenAddress).approve(address(arcadiumSwapRouter), baseAmount);
        IERC20(arcadiumAddress).approve(address(arcadiumSwapRouter), nativeAmount);

        // add the liquidity
        arcadiumSwapRouter.addLiquidity(
            baseTokenAddress,
            arcadiumAddress,
            baseAmount,
            nativeAmount ,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            msg.sender,
            block.timestamp
        );
    }

    function removeArcadiumLiquidity(address baseTokenAddress, uint256 liquidity) external nonReentrant {
        address lpTokenAddress = IUniswapV2Factory(arcadiumSwapRouter.factory()).getPair(baseTokenAddress, arcadiumAddress);
        require(lpTokenAddress != address(0), "pair hasn't been created yet, so can't remove liquidity!");

        IERC20(lpTokenAddress).safeTransferFrom(msg.sender, address(this), liquidity);
        // approve token transfer to cover all possible scenarios
        IERC20(lpTokenAddress).approve(address(arcadiumSwapRouter), liquidity);

        // add the liquidity
        arcadiumSwapRouter.removeLiquidity(
            baseTokenAddress,
            arcadiumAddress,
            liquidity,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            msg.sender,
            block.timestamp
        );
    }
}
