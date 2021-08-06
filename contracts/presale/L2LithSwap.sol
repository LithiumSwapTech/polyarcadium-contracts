pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/IERC20.sol";


contract L2LithSwap is Ownable, ReentrancyGuard {

    address public constant feeAddress = 0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31;

    address public constant lithAddress = 0xfE1a200637464FBC9B60Bc7AeCb9b86c0E1d486E;
    address public immutable preMyFriendsAddress;
    address public immutable preArcadiumAddress;

    uint256 public constant lithiumPresaleSize = (10 ** 5) * (10 ** 18);

    uint256 public preMyFriendsSaleINVPriceE35 = 36 * (10 ** 33);
    uint256 public preArcadiumSaleINVPriceE35 = 2 * (10 ** 35);

    uint256 public preMyFriendsMaximumAvailable = (lithiumPresaleSize * preMyFriendsSaleINVPriceE35) / 1e35;
    uint256 public preArcadiumMaximumAvailable = (lithiumPresaleSize * preArcadiumSaleINVPriceE35) / 1e35;

    // We use a counter to defend against people sending pre{MyFriends,Arcadium} back
    uint256 public preMyFriendsRemaining = preMyFriendsMaximumAvailable;
    uint256 public preArcadiumRemaining = preArcadiumMaximumAvailable;

    uint256 public constant oneHourMatic = 1500;
    uint256 public constant presaleDuration = 86399;

    uint256 public startBlock;
    uint256 public endBlock = startBlock + presaleDuration;

    event PrePurchased(address sender, uint256 usdcSpent, uint256 preMyFriendsReceived, uint256 preArcadiumReceived);
    event RetrieveDepreciatedLithTokens(address feeAddress, uint256 tokenAmount);
    event SaleINVPricesE35Changed(uint256 newMyFriendsSaleINVPriceE35, uint256 newArcadiumSaleINVPriceE35);
    event StartBlockChanged(uint256 newStartBlock, uint256 newEndBlock);

    constructor(uint256 _startBlock, address _preMyFriendsAddress, address _preArcadiumAddress) {
        require(block.number < _startBlock, "cannot set start block in the past!");
        require(lithAddress != _preMyFriendsAddress, "lithAddress cannot be equal to preArcadium");
        require(_preMyFriendsAddress != _preArcadiumAddress, "preMyFriends cannot be equal to preArcadium");
        require(_preMyFriendsAddress != address(0), "_preMyFriendsAddress cannot be the zero address");
        require(_preArcadiumAddress != address(0), "_preArcadiumAddress cannot be the zero address");

        startBlock = _startBlock;
        endBlock   = _startBlock + presaleDuration;

        preMyFriendsAddress = _preMyFriendsAddress;
        preArcadiumAddress = _preArcadiumAddress;
    }

    function swapLithForPresaleTokensL2(uint256 lithToSwap) external nonReentrant {
        require(msg.sender != feeAddress, "fee address cannot partake in presale");
        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(preMyFriendsRemaining > 0 && preArcadiumRemaining > 0, "No more presale tokens remaining! Come back next time!");
        require(IERC20(preMyFriendsAddress).balanceOf(address(this)) > 0, "No more PreMyFriends left! Come back next time!");
        require(IERC20(preArcadiumAddress).balanceOf(address(this)) > 0, "No more PreArcadium left! Come back next time!");
        require(lithToSwap > 1e6, "not enough lithium provided");

        uint256 originalPreMyFriendsAmount = (lithToSwap * preMyFriendsSaleINVPriceE35) / 1e35;
        uint256 originalPreArcadiumAmount = (lithToSwap * preArcadiumSaleINVPriceE35) / 1e35;

        uint256 preMyFriendsPurchaseAmount = originalPreMyFriendsAmount;
        uint256 preArcadiumPurchaseAmount = originalPreArcadiumAmount;

        // if we dont have enough left, give them the rest.
        if (preMyFriendsRemaining < preMyFriendsPurchaseAmount)
            preMyFriendsPurchaseAmount = preMyFriendsRemaining;

        if (preArcadiumRemaining < preArcadiumPurchaseAmount)
            preArcadiumPurchaseAmount = preArcadiumRemaining;


        require(preMyFriendsPurchaseAmount > 0, "user cannot purchase 0 preMyFriends");
        require(preArcadiumPurchaseAmount > 0, "user cannot purchase 0 preArcadium");

        // shouldn't be possible to fail these asserts.
        assert(preMyFriendsPurchaseAmount <= preMyFriendsRemaining);
        assert(preMyFriendsPurchaseAmount <= IERC20(preMyFriendsAddress).balanceOf(address(this)));

        assert(preArcadiumPurchaseAmount <= preArcadiumRemaining);
        assert(preArcadiumPurchaseAmount <= IERC20(preArcadiumAddress).balanceOf(address(this)));


        require(IERC20(preMyFriendsAddress).transfer(msg.sender, preMyFriendsPurchaseAmount), "failed sending preMyFriends");
        require(IERC20(preArcadiumAddress).transfer(msg.sender, preArcadiumPurchaseAmount), "failed sending preArcadium");

        preMyFriendsRemaining = preMyFriendsRemaining - preMyFriendsPurchaseAmount;
        preArcadiumRemaining = preArcadiumRemaining - preArcadiumPurchaseAmount;

        require(IERC20(lithAddress).transferFrom(msg.sender, address(this), lithToSwap), "failed to collect lithium from user");

        emit PrePurchased(msg.sender, lithToSwap, preMyFriendsPurchaseAmount, preArcadiumPurchaseAmount);
    }


    function sendDepreciatedLithToFeeAddress() external onlyOwner {
        require(block.number > endBlock, "can only retrieve excess tokens after lith swap has ended");

        uint256 lithInContract = IERC20(lithAddress).balanceOf(address(this));

        if (lithInContract > 0)
            IERC20(lithAddress).transfer(feeAddress, lithInContract);

        emit RetrieveDepreciatedLithTokens(feeAddress, lithInContract);
    }

    function setSaleINVPriceE35(uint256 _newPreMyFriendsSaleINVPriceE35, uint256 _newPreArcadiumSaleINVPriceE35) external onlyOwner {
        require(block.number < startBlock - (oneHourMatic * 4), "cannot change price 4 hours before start block");
        require(_newPreMyFriendsSaleINVPriceE35 >= 5 * (10 ** 33), "new myfriends price is to high!");
        require(_newPreMyFriendsSaleINVPriceE35 <= 5 * (10 ** 34), "new myfriends price is too low!");

        require(_newPreArcadiumSaleINVPriceE35 >= 3 * (10 ** 34), "new arcadium price is to high!");
        require(_newPreArcadiumSaleINVPriceE35 <= 25 * (10 ** 34), "new arcadium price is too low!");

        preMyFriendsSaleINVPriceE35 = _newPreMyFriendsSaleINVPriceE35;
        preArcadiumSaleINVPriceE35 = _newPreArcadiumSaleINVPriceE35;

        preMyFriendsMaximumAvailable = (lithiumPresaleSize * preMyFriendsSaleINVPriceE35) / 1e35;
        preArcadiumMaximumAvailable  = (lithiumPresaleSize * preArcadiumSaleINVPriceE35) / 1e35;

        preMyFriendsRemaining = preMyFriendsMaximumAvailable;
        preArcadiumRemaining = preArcadiumMaximumAvailable;

        emit SaleINVPricesE35Changed(preMyFriendsSaleINVPriceE35, preArcadiumSaleINVPriceE35);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;
        endBlock   = _newStartBlock + presaleDuration;

        emit StartBlockChanged(_newStartBlock, endBlock);
    }
}