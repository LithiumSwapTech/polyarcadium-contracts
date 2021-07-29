pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/IERC20.sol";
import "../libs/ERC20.sol";

// PreMyFriends
contract PreMyFriends is ERC20('PREMYFRIENDS', 'PREMYFRIENDS'), ReentrancyGuard {

    address public constant feeAddress = 0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31;

    address public constant usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    // 500k USDC
    uint256 public constant usdcPresaleSize = 5 * (10 ** 5) * (10 ** 6);
    uint256 public constant usdcPerAccountMaxBuy = 3 * (10 ** 3) * (10 ** 6);

    uint256 public preMyFriendsSaleINVPriceE35 = 3 * (10 ** 33);
    uint256 public preArcadiumSaleINVPriceE35 = 15 * (10 ** 33);

    uint256 public preMyFriendsMaximumSupply = ((10 ** 12) *
            usdcPresaleSize * preMyFriendsSaleINVPriceE35) / 1e35;
    uint256 public preArcadiumMaximumSupply = ((10 ** 12) *
            usdcPresaleSize * preArcadiumSaleINVPriceE35) / 1e35;

    uint256 public maxPreMyFriendsPurchase = ((10 ** 12) *
            usdcPerAccountMaxBuy * preMyFriendsSaleINVPriceE35) / 1e35;
    uint256 public maxPreArcadiumPurchase = ((10 ** 12) *
            usdcPerAccountMaxBuy * preArcadiumSaleINVPriceE35) / 1e35;

    // We use a counter to defend against people sending pre{MyFriends,Arcadium} back
    uint256 public preMyFriendsRemaining = preMyFriendsMaximumSupply;
    uint256 public preArcadiumRemaining = preArcadiumMaximumSupply;

    uint256 oneHourMatic = 1800;
    uint256 oneDayMatic = oneHourMatic * 24;
    uint256 twoDaysMatic = oneDayMatic * 2;

    uint256 public startBlock;
    uint256 public endBlock;

    mapping(address => uint256) public userPreMyFriendsTally;
    mapping(address => uint256) public userPreArcadiumTally;

    address public preArcadiumAddress;

    event prePurchased(address sender, uint256 usdcSpent, uint256 preMyFriendsReceived, uint256 preArcadiumReceived);
    event startBlockChanged(uint256 newStartBlock, uint256 newEndBlock);
    event saleINVPricesE35Changed(uint256 newMyFriendsSaleINVPriceE35, uint256 newArcadiumSaleINVPriceE35);

    constructor(uint256 _startBlock, address _preArcadiumAddress) {
        require(block.number < _startBlock, "cannot set start block in the past!");
        require(_preArcadiumAddress != address(0), "_preArcadiumAddress cannot be the zero address");
        startBlock = _startBlock;
        endBlock   = _startBlock + twoDaysMatic;
        preArcadiumAddress = _preArcadiumAddress;
        _mint(feeAddress, uint256(80000 * (10 ** 18)));
    }

    function buyL2Presale(uint256 usdcToSpend) external nonReentrant {
        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(preMyFriendsRemaining > 0 && preArcadiumRemaining > 0, "No more presale tokens remaining! Come back next time!");
        require(IERC20(address(this)).balanceOf(address(this)) > 0, "No more preMyFriends left! Come back next time!");
        require(IERC20(preArcadiumAddress).balanceOf(address(this)) > 0, "No more preMyFriends left! Come back next time!");
        require(usdcToSpend > 1e4, "not enough usdc provided");
        require(usdcToSpend <= 3e22, "too much usdc provided");

        require(userPreMyFriendsTally[msg.sender] < maxPreMyFriendsPurchase &&
            userPreArcadiumTally[msg.sender] < maxPreArcadiumPurchase, "user has already purchased too much of the presale!");

        // The difference between the presale tokens decimal precision and
        // usdc decimal precision is 12, so we multiply by 10^12.
        // USDC is a fixed constant address and has decimals=6
        // while our presale tokens have decimals 18, which we control.
        uint256 originalPreMyFriendsAmount = ((10 ** 12) *
            usdcToSpend * preMyFriendsSaleINVPriceE35) / 1e35;
        uint256 originalPreArcadiumAmount = ((10 ** 12) *
            usdcToSpend * preArcadiumSaleINVPriceE35) / 1e35;

        uint256 preMyFriendsPurchaseAmount = originalPreMyFriendsAmount;
        uint256 preArcadiumPurchaseAmount = originalPreArcadiumAmount;

        if (preMyFriendsPurchaseAmount > maxPreMyFriendsPurchase)
            preMyFriendsPurchaseAmount = maxPreMyFriendsPurchase;

        if (preArcadiumPurchaseAmount > maxPreArcadiumPurchase)
            preArcadiumPurchaseAmount = maxPreArcadiumPurchase;

        if ((userPreMyFriendsTally[msg.sender] + preMyFriendsPurchaseAmount) > maxPreMyFriendsPurchase)
            preMyFriendsPurchaseAmount = maxPreMyFriendsPurchase - userPreMyFriendsTally[msg.sender];

        if ((userPreArcadiumTally[msg.sender] + preArcadiumPurchaseAmount) > maxPreArcadiumPurchase)
            preArcadiumPurchaseAmount = maxPreArcadiumPurchase - userPreArcadiumTally[msg.sender];

        // if we dont have enough left, give them the rest.
        if (preMyFriendsRemaining < preMyFriendsPurchaseAmount)
            preMyFriendsPurchaseAmount = preMyFriendsRemaining;

        if (preArcadiumRemaining < preArcadiumPurchaseAmount)
            preArcadiumPurchaseAmount = preArcadiumRemaining;

        require(preMyFriendsPurchaseAmount > 0, "user cannot purchase 0 preMyFriends");
        require(preArcadiumPurchaseAmount > 0, "user cannot purchase 0 preArcadium");

        // shouldn't be possible to fail these asserts.
        assert(preMyFriendsPurchaseAmount <= preMyFriendsRemaining);
        assert(preMyFriendsPurchaseAmount <= IERC20(address(this)).balanceOf(address(this)));

        assert(preArcadiumPurchaseAmount <= preArcadiumRemaining);
        assert(preArcadiumPurchaseAmount <= IERC20(preArcadiumAddress).balanceOf(address(this)));

        require(IERC20(address(this)).transfer(msg.sender, preMyFriendsPurchaseAmount), "failed sending preMyFriends");
        require(IERC20(preArcadiumAddress).transfer(msg.sender, preArcadiumPurchaseAmount), "failed sending preMyFriends");

        preMyFriendsRemaining = preMyFriendsRemaining - preMyFriendsPurchaseAmount;
        userPreMyFriendsTally[msg.sender] = userPreMyFriendsTally[msg.sender] + preMyFriendsPurchaseAmount;

        preArcadiumRemaining = preArcadiumRemaining - preArcadiumPurchaseAmount;
        userPreArcadiumTally[msg.sender] = userPreArcadiumTally[msg.sender] + preArcadiumPurchaseAmount;

        uint256 usdcSpent = usdcToSpend;
        if (preMyFriendsPurchaseAmount < originalPreMyFriendsAmount) {
            // max PurchaseAmount = 6e20, max USDC 3e9
            // overfow check: 6e20 * 3e9 * 1e24 = 1.8e67 < type(uint256).max
            // Rounding errors by integer division, reduce magnitude of end result.
            // We accept any rounding error (tiny) as a reduction in PAYMENT, not refund.
            usdcSpent = ((preMyFriendsPurchaseAmount * usdcToSpend * 1e24) / originalPreMyFriendsAmount) / 1e24;
        }

        if (usdcSpent > 0)
            require(ERC20(usdcAddress).transferFrom(msg.sender, feeAddress, usdcSpent), "failed to send usdc to fee address");

        emit prePurchased(msg.sender, usdcSpent, preMyFriendsPurchaseAmount, preArcadiumPurchaseAmount);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;
        endBlock   = _newStartBlock + twoDaysMatic;

        emit startBlockChanged(_newStartBlock, endBlock);
    }

    function setSaleINVPriceE35(uint256 _newPreMyFriendsSaleINVPriceE35, uint256 _newPreArcadiumSaleINVPriceE35) external onlyOwner {
        require(block.number < startBlock - (oneHourMatic * 4), "cannot change price 4 hours before start block");
        require(_newPreMyFriendsSaleINVPriceE35 >= 3 * (10 ** 33), "new myfriends price is to high!");
        require(_newPreMyFriendsSaleINVPriceE35 <= 5 * (10 ** 33), "new myfriends price is too low!");

        require(_newPreArcadiumSaleINVPriceE35 >= 15 * (10 ** 33), "new arcadium price is to high!");
        require(_newPreArcadiumSaleINVPriceE35 <= 25 * (10 ** 33), "new arcadium price is too low!");

        preMyFriendsSaleINVPriceE35 = _newPreMyFriendsSaleINVPriceE35;
        preArcadiumSaleINVPriceE35 = _newPreArcadiumSaleINVPriceE35;


        preMyFriendsMaximumSupply = ((10 ** 12) *
            usdcPresaleSize * preMyFriendsSaleINVPriceE35) / 1e35;
        preArcadiumMaximumSupply = ((10 ** 12) *
            usdcPresaleSize * preArcadiumSaleINVPriceE35) / 1e35;

        preMyFriendsRemaining = preMyFriendsMaximumSupply;
        preArcadiumRemaining = preArcadiumMaximumSupply;

        maxPreMyFriendsPurchase = ((10 ** 12) *
            usdcPerAccountMaxBuy * preMyFriendsSaleINVPriceE35) / 1e35;
        maxPreArcadiumPurchase = ((10 ** 12) *
            usdcPerAccountMaxBuy * preArcadiumSaleINVPriceE35) / 1e35;

        emit saleINVPricesE35Changed(preMyFriendsSaleINVPriceE35, preArcadiumSaleINVPriceE35);
    }
}