// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libs/ERC20.sol";
import "./libs/IERC20.sol";
import "./libs/SafeERC20.sol";
import "./libs/IWETH.sol";

import "./libs/RHCPToolBox.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

// ArcadiumToken.
contract ArcadiumToken is ERC20("ARCADIUM", "ARCADIUM")  {
    using SafeERC20 for IERC20;

    // Transfer tax rate in basis points. (default 6.66%)
    uint16 public transferTaxRate = 666;
    // Extra transfer tax rate in basis points. (default 2.00%)
    uint16 public extraTransferTaxRate = 200;
    // Burn rate % of transfer tax. (default 54.95% x 6.66% = 3.660336% of total amount).
    uint32 public constant burnRate = 549549549;
    // Max transfer tax rate: 10.01%.
    uint16 public constant MAXIMUM_TRANSFER_TAX_RATE = 1001;
    // Burn address
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public constant usdcCurrencyAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    uint256 public constant usdcSwapThreshold = 20 * (10 ** 6);

    // Automatic swap and liquify enabled
    bool public swapAndLiquifyEnabled = true;
    // Min amount to liquify. (default 10 ARCADIUMs)
    uint256 public minAmountToLiquify = 10 * (10 ** 18);
    // The swap router, modifiable. Will be changed to ArcadiumSwap's router when our own AMM release
    IUniswapV2Router02 public arcadiumSwapRouter;
    // The trading pair
    address public arcadiumSwapPair;
    // In swap and liquify
    bool private _inSwapAndLiquify;

    RHCPToolBox arcadiumToolBox;
    IERC20 public usdcRewardCurrency;
    address public myFriends;

    mapping(address => bool) public excludeFromMap;
    mapping(address => bool) public excludeToMap;

    mapping(address => bool) public extraFromMap;
    mapping(address => bool) public extraToMap;

    // The operator can only update the transfer tax rate
    address private _operator;

    modifier onlyOperator() {
        require(_operator == msg.sender, "!operator");
        _;
    }

    modifier lockTheSwap {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    modifier transferTaxFree {
        uint16 _transferTaxRate = transferTaxRate;
        uint16 _extraTransferTaxRate = extraTransferTaxRate;
        transferTaxRate = 0;
        extraTransferTaxRate = 0;
        _;
        transferTaxRate = _transferTaxRate;
        extraTransferTaxRate = _extraTransferTaxRate;
    }

    /**
     * @notice Constructs the ArcadiumToken contract.
     */
    constructor(address _myFriends, RHCPToolBox _arcadiumToolBox) public {
        arcadiumToolBox = _arcadiumToolBox;
        myFriends = _myFriends;
        usdcRewardCurrency = IERC20(usdcCurrencyAddress);
        _operator = _msgSender();

        // pre-mint
        _mint(address(0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31), uint256(250000 * (10 ** 18)));
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /// @dev overrides transfer function to meet tokenomics of ARCADIUM
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override {
        // swap and liquify
        if (
            swapAndLiquifyEnabled == true
            && _inSwapAndLiquify == false
            && address(arcadiumSwapRouter) != address(0)
            && arcadiumSwapPair != address(0)
            && sender != arcadiumSwapPair
            && sender != owner()
        ) {
            swapAndLiquify();
        }

        if (recipient == BURN_ADDRESS || transferTaxRate == 0 || excludeFromMap[sender] || excludeToMap[recipient]) {
            super._transfer(sender, recipient, amount);
        } else {
            // default tax is 6.66% of every transfer, but extra 2% for dumping tax
            uint256 taxAmount = (amount * (transferTaxRate +
                ((extraFromMap[sender] || extraToMap[recipient]) ? extraTransferTaxRate : 0))) / 10000;

            uint256 burnAmount = (taxAmount * burnRate) / 1000000000;
            uint256 liquidityAmount = taxAmount - burnAmount;
            require(taxAmount == burnAmount + liquidityAmount, "Burn invalid");

            // default 95% of transfer sent to recipient
            uint256 sendAmount = amount - taxAmount;
            require(amount == sendAmount + taxAmount, "Tax invalid");

            super._transfer(sender, BURN_ADDRESS, burnAmount);
            super._transfer(sender, address(this), liquidityAmount);
            super._transfer(sender, recipient, sendAmount);
            amount = sendAmount;
        }
    }

    /// @dev Swap and liquify
    function swapAndLiquify() private lockTheSwap transferTaxFree {
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance >= minAmountToLiquify) {
            uint256 WETHbalance = IERC20(arcadiumSwapRouter.WETH()).balanceOf(address(this));

            if (WETHbalance > 0)
                IWETH(arcadiumSwapRouter.WETH()).withdraw(WETHbalance);

            (uint256 res0, uint256 res1, ) = IUniswapV2Pair(arcadiumSwapPair).getReserves();

            if (res0 != 0 && res1 != 0) {
                // making weth res0
                if (IUniswapV2Pair(arcadiumSwapPair).token0() == address(this))
                    (res1, res0) = (res0, res1);

                // only min amount to liquify
                uint256 arcadiumLiquifyAmount = minAmountToLiquify;

                // calculate how much eth is needed to use all of arcadiumLiquifyAmount
                // also boost precision a tad.
                uint256 totalETHNeeded = ((1e6 * res0 * arcadiumLiquifyAmount) / res1) / 1e6;

                uint256 existingETH = address(this).balance;
                uint256 unmatchedArcadium = 0;

                if (existingETH < totalETHNeeded) {
                    // calculate how much arcadium will match up with our existing eth.
                    uint256 matchedArcadium = (((1e6 * res1 * existingETH) / res0) / 1e6);
                    if (arcadiumLiquifyAmount >= matchedArcadium)
                        unmatchedArcadium = arcadiumLiquifyAmount - matchedArcadium;
                } else
                    existingETH = totalETHNeeded;

                uint256 unmatchedArcadiumToSwap = unmatchedArcadium / 2;

                // capture the contract's current ETH balance.
                // this is so that we can capture exactly the amount of ETH that the
                // swap creates, and not make the liquidity event include any ETH that
                // has been manually sent to the contract
                uint256 initialBalance = address(this).balance;

                // swap tokens for ETH
                if (unmatchedArcadiumToSwap > 0) {
                    swapTokensForEth(unmatchedArcadiumToSwap);
                }

                // how much ETH did we just swap into?
                uint256 newBalance = address(this).balance - initialBalance;

                // add liquidity
                addLiquidity(arcadiumLiquifyAmount - unmatchedArcadiumToSwap, existingETH + newBalance);
            }
        }
    }

    /// @dev Swap tokens for eth
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the arcadiumSwap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = arcadiumSwapRouter.WETH();

        _approve(address(this), address(arcadiumSwapRouter), tokenAmount);

        // make the swap
        arcadiumSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /// @dev Add liquidity
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(arcadiumSwapRouter), tokenAmount);

        // add the liquidity
        arcadiumSwapRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31),
            block.timestamp
        );
    }

    /**
     * @dev unenchant the lp token into its original components.
     * Can only be called by the current operator.
     */
    function swapLpTokensForFee(address token, uint256 amount) internal {
        require(IERC20(token).approve(address(arcadiumSwapRouter), amount), '!approve');

        IUniswapV2Pair lpToken = IUniswapV2Pair(token);

        uint256 token0BeforeLiquidation = IERC20(lpToken.token0()).balanceOf(address(this));
        uint256 token1BeforeLiquidation = IERC20(lpToken.token1()).balanceOf(address(this));

        // make the swap
        arcadiumSwapRouter.removeLiquidity(
            lpToken.token0(),
            lpToken.token1(),
            amount,
            0,
            0,
            address(this),
            block.timestamp
        );

        uint256 token0FromLiquidation = IERC20(lpToken.token0()).balanceOf(address(this)) - token0BeforeLiquidation;
        uint256 token1FromLiquidation = IERC20(lpToken.token1()).balanceOf(address(this)) - token1BeforeLiquidation;

        address tokenForMyFriendsUSDCReward = lpToken.token0();
        address tokenForArcadiumAMMReward = lpToken.token1();

        // If we already have, usdc, save a swap.
       if (lpToken.token1() == address(usdcRewardCurrency)){

            (tokenForArcadiumAMMReward, tokenForMyFriendsUSDCReward) = (tokenForMyFriendsUSDCReward, tokenForArcadiumAMMReward);
        } else if (lpToken.token0() == arcadiumSwapRouter.WETH()){
            // if one is weth already use the other one for myfriends and
            // the weth for arcadium AMM to save a swap.

            (tokenForArcadiumAMMReward, tokenForMyFriendsUSDCReward) = (tokenForMyFriendsUSDCReward, tokenForArcadiumAMMReward);
        }

        // send myfriends all of 1 half of the LP to be convereted to USDC later.
        IERC20(tokenForMyFriendsUSDCReward).safeTransfer(address(myFriends),
            tokenForMyFriendsUSDCReward == lpToken.token0() ? token0FromLiquidation : token1FromLiquidation);

        // send myfriends 50% share of the other 50% to give myfriends 75% in total.
        IERC20(tokenForArcadiumAMMReward).safeTransfer(address(myFriends),
            (tokenForArcadiumAMMReward == lpToken.token0() ? token0FromLiquidation : token1FromLiquidation)/2);

        swapDepositFeeForTokensInternal(tokenForArcadiumAMMReward, 0,  0 /* zero means use all */, arcadiumSwapRouter.WETH());
    }

    /**
     * @dev sell all of a current type of token for weth, to be used in arcadium liquidity later.
     * Can only be called by the current operator.
     */
    function swapDepositFeeForETH(address token, uint8 tokenType) external onlyOwner {
        uint256 usdcValue = arcadiumToolBox.getTokenUSDCValue(IERC20(token).balanceOf(address(this)), token, tokenType, false, address(usdcRewardCurrency));

        // If arcadium or weth already no need to do anything.
        if (token == address(this) || token == arcadiumSwapRouter.WETH())
            return;

        // only swap if a certain usdc value
        if (usdcValue < usdcSwapThreshold)
            return;

        swapDepositFeeForTokensInternal(token, tokenType, 0 /* zero means use all */, arcadiumSwapRouter.WETH());
    }

    function swapDepositFeeForTokensInternal(address token, uint8 tokenType, uint256 amountToSwap, address toToken) internal {
        uint256 totalTokenBalance = amountToSwap == 0 ? IERC20(token).balanceOf(address(this)) : amountToSwap;
        require(totalTokenBalance <= IERC20(token).balanceOf(address(this)), "!sufficient funds");

        // can't trade to arcadium inside of arcadium anyway, we also do usually want arcadium here.
        if (token == toToken || totalTokenBalance == 0 || toToken == address(this))
            return;

        if (tokenType == 1)
            return swapLpTokensForFee(token, totalTokenBalance);

        require(IERC20(token).approve(address(arcadiumSwapRouter), totalTokenBalance), "swap approval failed");

        // generate the arcadiumSwap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = toToken;

        // make the swap
        arcadiumSwapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            totalTokenBalance,
            0, // accept any amount of tokens
            path,
            address(this),
            block.timestamp
        );

        // Unfortunately can't swap directly to arcadium inside of arcadium (Uniswap INVALID_TO Assert, boo).
        // Also dont want to add an extra swap here.
        // Will leave as WETH and make the arcadium Txn AMM utilise available WETH first.
    }

    // To receive BNB from arcadiumSwapRouter when swapping
    receive() external payable {}

    /**
     * @dev Update the swapAndLiquifyEnabled.
     * Can only be called by the current operator.
     */
    function updateSwapAndLiquifyEnabled(bool _enabled) external onlyOperator {
        swapAndLiquifyEnabled = _enabled;
    }

    /**
     * @dev Update the transfer tax rate.
     * Can only be called by the current operator.
     */
    function updateTransferTaxRate(uint16 _transferTaxRate, uint16 _extraTransferTaxRate) external onlyOperator {
        require(_transferTaxRate + _extraTransferTaxRate  <= MAXIMUM_TRANSFER_TAX_RATE,
            "tax rate too high");
        transferTaxRate = _transferTaxRate;
        extraTransferTaxRate = _extraTransferTaxRate;
    }

    /**
     * @dev Update the excludeFromMap
     * Can only be called by the current operator.
     */
    function updateExcludeMap(address _contract, bool fromExcluded, bool toExcluded) external onlyOperator {
        excludeFromMap[_contract] = fromExcluded;
        excludeToMap[_contract] = toExcluded;
    }

    /**
     * @dev Update the excludeFromMap
     * Can only be called by the current operator.
     */
    function updateExtraMap(address _contract, bool fromHasExtra, bool toHasExtra) external onlyOperator {
        extraFromMap[_contract] = fromHasExtra;
        extraFromMap[_contract] = toHasExtra;
    }
    /**
     * @dev Update the swap router.
     * Can only be called by the current operator.
     */
    function updateArcadiumSwapRouter(address _router) external onlyOperator {
        require(_router != address(0), "zero address");
        arcadiumSwapRouter = IUniswapV2Router02(_router);
        arcadiumSwapPair = IUniswapV2Factory(arcadiumSwapRouter.factory()).getPair(address(this), arcadiumSwapRouter.WETH());
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */
    function transferOperator(address newOperator) external onlyOperator {
        require(newOperator != address(0), "zero address");
        _operator = newOperator;
    }
}
