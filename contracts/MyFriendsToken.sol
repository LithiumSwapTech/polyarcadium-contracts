// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libs/ERC20.sol";
import "./libs/IERC20.sol";

import "./libs/RHCPToolBox.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";


// MyFriendsToken
contract MyFriendsToken is ERC20("MYFRIENDS", "MYFRIENDS") {

    // Burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    uint256 public constant usdcSwapThreshold = 20 * (10 ** 6);

    // The operator can only update the transfer tax rate
    address private _operator;

    IERC20 public immutable usdcRewardCurrency;

    uint256 usdcRewardBalance = 0;

    RHCPToolBox arcadiumToolBox;

    IUniswapV2Router02 public arcadiumSwapRouter;

    // Events
    event DistributeMyFriends(address recipient, uint256 myFriendsAmount);
    event DepositFeeConvertedToUSDC(address indexed inputToken, uint256 inputAmount, uint256 usdcOutput);
    event USDCTransferredToUser(address recipient, uint256 usdcAmount);
    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event ArcadiumSwapRouterUpdated(address indexed operator, address indexed router);

    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }

    /**
     * @notice Constructs the ArcadiumToken contract.
     */
    constructor(address _usdcCurrency, RHCPToolBox _arcadiumToolBox) public {
        _operator = _msgSender();
        emit OperatorTransferred(address(0), _operator);

        arcadiumToolBox = _arcadiumToolBox;
        usdcRewardCurrency = IERC20(_usdcCurrency);

        // Divvy up myFriends supply.
        _mint(0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31, 80 * (10 ** 3) * (10 ** 18));
        _mint(address(this), 20 * (10 ** 3) * (10 ** 18));
    }

    /// @notice Sends `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function distribute(address _to, uint256 _amount) external onlyOwner returns (uint256){
        uint256 sendAmount = _amount;
        if (balanceOf(address(this)) < _amount)
            sendAmount = balanceOf(address(this));

        if (sendAmount > 0) {
            IERC20(address(this)).transfer(_to, sendAmount);
            emit DistributeMyFriends(_to, sendAmount);
        }

        return sendAmount;
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    // To receive MATIC from arcadiumSwapRouter when swapping
    receive() external payable {}

    /**
     * @dev sell all of a current type of token for usdc.
     * Can only be called by the current operator.
     */
    function convertDepositFeesToUSDC(address token, uint8 tokenType) public onlyOwner returns (uint256) {
        // shouldn't be trying to sell MyFriends
        if (token == address(this))
            return 0;

        // LP tokens aren't destroyed in MyFriends, but this is so MyFriends can process
        // already destroyed LP fees sent to it by the ArcadiumToken contract.
        if (tokenType == 1) {
            return convertDepositFeesToUSDC(IUniswapV2Pair(token).token0(), 0) +
                convertDepositFeesToUSDC(IUniswapV2Pair(token).token1(), 0);
        }

        uint256 totalTokenBalance = IERC20(token).balanceOf(address(this));

        if (token == address(usdcRewardCurrency)) {
            // Incase any usdc has been sent from OTC or otherwise, report that as
            // gained this amount.
            uint256 amountLiquified = totalTokenBalance - usdcRewardBalance;

            usdcRewardBalance = totalTokenBalance;

            return amountLiquified;
        }

        uint256 usdcValue = arcadiumToolBox.getTokenUSDCValue(totalTokenBalance, token, tokenType, false, address(usdcRewardCurrency));

        if (totalTokenBalance == 0)
            return 0;
        if (usdcValue < usdcSwapThreshold)
            return 0;

        // generate the arcadiumSwap pair path of token -> usdc.
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(usdcRewardCurrency);

        uint256 usdcPriorBalance = usdcRewardCurrency.balanceOf(address(this));

        require(IERC20(token).approve(address(arcadiumSwapRouter), totalTokenBalance), 'approval failed');

        // make the swap
        arcadiumSwapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            totalTokenBalance,
            0, // accept any amount of USDC
            path,
            address(this),
            block.timestamp
        );

        uint256 usdcProfit =  usdcRewardCurrency.balanceOf(address(this)) - usdcPriorBalance;

        usdcRewardBalance = usdcRewardBalance + usdcProfit;

        emit DepositFeeConvertedToUSDC(token, totalTokenBalance, usdcProfit);

        return usdcProfit;
    }

    /**
     * @dev send usdc to a user
     * Can only be called by the current operator.
     */
    function transferUSDCToUser(address recipient, uint256 amount) external onlyOwner {
        require(usdcRewardCurrency.balanceOf(address(this)) >= amount, "accounting error, transfering more usdc out than available");
        require(usdcRewardCurrency.transfer(recipient, amount), "transfer failed!");

        usdcRewardBalance = usdcRewardBalance - amount;

        emit USDCTransferredToUser(recipient, amount);
    }

    /**
     * @dev Update the swap router.
     * Can only be called by the current operator.
     */
    function updateArcadiumSwapRouter(address _router) external onlyOperator {
        require(_router != address(0), "updateArcadiumSwapRouter: new _router is the zero address");
        require(address(arcadiumSwapRouter) == address(0), "router already set!");

        arcadiumSwapRouter = IUniswapV2Router02(_router);
        emit ArcadiumSwapRouterUpdated(msg.sender, address(arcadiumSwapRouter));
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */
    function transferOperator(address newOperator) external onlyOperator {
        require(newOperator != address(0), "transferOperator: new operator is the zero address");
        _operator = newOperator;

        emit OperatorTransferred(_operator, newOperator);
    }
}
