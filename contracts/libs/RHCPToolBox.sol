// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./IERC20.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract RHCPToolBox {
    // The swap router, modifiable. Will be changed to ArcadiumSwap's router when our own AMM release
    IUniswapV2Router02 public arcadiumSwapRouter;

    uint256 public startBlock;

    // The operator can only update the transfer tax rate
    address private _operator;

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    /**
     * @notice Constructs the ArcadiumToken contract.
     */
    constructor(uint256 _startBlock) public {
        startBlock = _startBlock;

        _operator = msg.sender;
    }

    function convertToTargetValueFromPair(IUniswapV2Pair pair, uint256 sourceTokenAmount, address targetAddress) public view returns (uint256) {
        require(pair.token0() == targetAddress || pair.token1() == targetAddress, "one of the pairs must be the targetAddress");
        if (sourceTokenAmount == 0)
            return 0;

        uint256 targetEquivalentAmount = 0;
        if (pair.token0() == targetAddress) {
            (uint256 res0, uint256 res1, ) = pair.getReserves();
            if (res0 == 0 || res1 == 0)
                return 0;
            uint8 token1Decimals = ERC20(pair.token1()).decimals();
            uint8 targetDecimal  = ERC20(targetAddress).decimals();
            targetEquivalentAmount = (res0 * sourceTokenAmount) / res1;
            if (token1Decimals < targetDecimal)
                targetEquivalentAmount = targetEquivalentAmount / (10 ** (targetDecimal - token1Decimals));
            else if (token1Decimals > targetDecimal)
                targetEquivalentAmount = targetEquivalentAmount  / (10 ** (token1Decimals - targetDecimal));
        } else if (pair.token1() == targetAddress){
            (uint256 res0, uint256 res1, ) = pair.getReserves();
            if (res0 == 0 || res1 == 0)
                return 0;
            uint8 token0Decimals = ERC20(pair.token0()).decimals();
            uint8 targetDecimal  = ERC20(targetAddress).decimals();
            targetEquivalentAmount = (res1 * sourceTokenAmount) / res0;
            if (token0Decimals < targetDecimal)
                targetEquivalentAmount = targetEquivalentAmount / (10 ** (targetDecimal - token0Decimals));
            else if (token0Decimals > targetDecimal)
                targetEquivalentAmount = targetEquivalentAmount * (10 ** (token0Decimals - targetDecimal));
        }

        return targetEquivalentAmount;
    }

    function getTokenUSDCValue(uint256 tokenBalance, address token, uint8 tokenType, bool viaBnbUSDC, address usdcAddress) external view returns (uint256) {
        require(tokenType == 0 || tokenType == 1, "invalid token type provided");
        if (token == address(usdcAddress))
            return tokenBalance;

        // lp type
        if (tokenType == 1) {
            IUniswapV2Pair lpToken = IUniswapV2Pair(token);
            if (lpToken.totalSupply() == 0)
                return 0;
            // If lp contains usdc, we can take a short cut
            if (lpToken.token0() == address(usdcAddress)) {
                return tokenBalance * ((IERC20(lpToken.token0()).balanceOf(address(lpToken))) * 2) / lpToken.totalSupply();
            } else if (lpToken.token1() == address(usdcAddress)){
                return tokenBalance * ((IERC20(lpToken.token1()).balanceOf(address(lpToken))) * 2) / lpToken.totalSupply();
            }
        }

        // Only used for lp type tokens.
        address lpTokenAddress = token;
        // If token0 or token1 is bnb, use that, else use token0.
        if (tokenType == 1) {
            token = IUniswapV2Pair(token).token0() == arcadiumSwapRouter.WETH() ? arcadiumSwapRouter.WETH() :
                        (IUniswapV2Pair(token).token1() == arcadiumSwapRouter.WETH() ? arcadiumSwapRouter.WETH() : IUniswapV2Pair(token).token0());
        }

        uint256 tokenAmount = (tokenType == 1) ? IERC20(token).balanceOf(lpTokenAddress) : tokenBalance;

        uint256 usdcEquivalentAmount = 0;

        if (viaBnbUSDC) {
            uint256 bnbAmount = 0;

            if (token == arcadiumSwapRouter.WETH()) {
                bnbAmount = tokenAmount;
            } else {

                // As we arent working with usdc at this point (early return), this is okay.
                IUniswapV2Pair bnbPair = IUniswapV2Pair(IUniswapV2Factory(arcadiumSwapRouter.factory()).getPair(arcadiumSwapRouter.WETH(), token));

                if (address(bnbPair) == address(0))
                    return 0;

                bnbAmount = convertToTargetValueFromPair(bnbPair, tokenAmount, arcadiumSwapRouter.WETH());
            }

            // As we arent working with usdc at this point (early return), this is okay.
            IUniswapV2Pair usdcbnbPair = IUniswapV2Pair(IUniswapV2Factory(arcadiumSwapRouter.factory()).getPair(arcadiumSwapRouter.WETH(), address(usdcAddress)));

            if (address(usdcbnbPair) == address(0))
                return 0;

            usdcEquivalentAmount = convertToTargetValueFromPair(usdcbnbPair, bnbAmount, usdcAddress);
        } else {
            // As we arent working with usdc at this point (early return), this is okay.
            IUniswapV2Pair usdcPair = IUniswapV2Pair(IUniswapV2Factory(arcadiumSwapRouter.factory()).getPair(address(usdcAddress), token));

            if (address(usdcPair) == address(0))
                return 0;

            usdcEquivalentAmount = convertToTargetValueFromPair(usdcPair, tokenAmount, usdcAddress);
        }

        if (tokenType == 1)
            return (usdcEquivalentAmount * 2 * tokenBalance) / IUniswapV2Pair(lpTokenAddress).totalSupply();
        else
            return usdcEquivalentAmount;
    }

    function getArcadiumEmissionForBlock(uint256 _block, bool isIncreasingGradient, uint256 releaseGradient, uint256 gradientEndBlock, uint256 endEmission) public pure returns (uint256) {
        if (_block >= gradientEndBlock)
            return endEmission;

        if (releaseGradient == 0)
            return endEmission;
        uint256 currentArcadiumEmission = endEmission;
        uint256 deltaHeight = (releaseGradient * (gradientEndBlock - _block)) / 1e24;

        if (isIncreasingGradient) {
            // if there is a logical error, we return 0
            if (endEmission < deltaHeight)
                currentArcadiumEmission = endEmission - deltaHeight;
            else
                currentArcadiumEmission = 0;
        } else
            currentArcadiumEmission = endEmission + deltaHeight;

        return currentArcadiumEmission;
    }

    function calcEmissionGradient(uint256 _block, uint256 currentEmission, uint256 gradientEndBlock, uint256 endEmission) external pure returns (uint256) {
        uint256 arcadiumReleaseGradient;

        // if th gradient is 0 we interpret that as an unchanging 0 gradient.
        if (currentEmission != endEmission && _block < gradientEndBlock) {
            bool isIncreasingGradient = endEmission > currentEmission;
            if (isIncreasingGradient)
                arcadiumReleaseGradient = ((endEmission - currentEmission) * 1e24) / (gradientEndBlock - _block);
            else
                arcadiumReleaseGradient = ((currentEmission - endEmission) * 1e24) / (gradientEndBlock - _block);
        } else
            arcadiumReleaseGradient = 0;

        return arcadiumReleaseGradient;
    }

    // Return if we are in the normal operation era, no promo
    function isFlatEmission(uint256 _gradientEndBlock, uint256 _blocknum) internal pure returns (bool) {
        return _blocknum >= _gradientEndBlock;
    }

    // Return ARCADIUM reward release over the given _from to _to block.
    function getArcadiumRelease(bool isIncreasingGradient, uint256 releaseGradient, uint256 gradientEndBlock, uint256 endEmission, uint256 _from, uint256 _to) external view returns (uint256) {
        if (_to <= _from || _to <= startBlock)
            return 0;
        uint256 clippedFrom = _from < startBlock ? startBlock : _from;
        uint256 totalWidth = _to - clippedFrom;

        if (releaseGradient == 0 || isFlatEmission(gradientEndBlock, clippedFrom))
            return totalWidth * endEmission;

        if (!isFlatEmission(gradientEndBlock, _to)) {
            uint256 heightDelta = releaseGradient * totalWidth;

            uint256 baseEmission;
            if (isIncreasingGradient)
                baseEmission = getArcadiumEmissionForBlock(_from, isIncreasingGradient, releaseGradient, gradientEndBlock, endEmission);
            else
                baseEmission = getArcadiumEmissionForBlock(_to, isIncreasingGradient, releaseGradient, gradientEndBlock, endEmission);
            return (((totalWidth * baseEmission) + (totalWidth * heightDelta) / 1e24) / 2);
        }

        // Special case when we are transitioning between promo2 and normal era.
        if (!isFlatEmission(gradientEndBlock, clippedFrom) && isFlatEmission(gradientEndBlock, _to)) {
            uint256 blocksUntilGradientEnd = gradientEndBlock - clippedFrom;
            uint256 heightDelta = releaseGradient * blocksUntilGradientEnd;

            uint256 baseEmission;
            if (isIncreasingGradient)
                baseEmission = getArcadiumEmissionForBlock(_to, isIncreasingGradient, releaseGradient, gradientEndBlock, endEmission);
            else
                baseEmission = getArcadiumEmissionForBlock(_from, isIncreasingGradient, releaseGradient, gradientEndBlock, endEmission);

            return (((totalWidth * baseEmission) - (blocksUntilGradientEnd * heightDelta) / 1e24) / 2);
        }

        // huh?
        // shouldnt happen, but also don't want to assert false here either.
        return 0;
    }

    /**
     * @dev Update the swap router.
     * Can only be called by the current operator.
     */
    function updateArcadiumSwapRouter(address _router) public onlyOperator {
        require(_router != address(0), "router cannot be the 0 address");
        arcadiumSwapRouter = IUniswapV2Router02(_router);
    }
}