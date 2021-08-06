pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/IERC20.sol";

import "./PreMyFriends.sol";
import "./PreArcadium.sol";

import "./L2LithSwap.sol";


contract L2TokenRedeem is Ownable, ReentrancyGuard {

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public constant feeAddress = 0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31;

    PreMyFriends public immutable preMyFriends;
    address public immutable preArcadiumAddress;

    address public immutable myFriendsAddress;
    address public immutable arcadiumAddress;

    L2LithSwap public immutable l2LithSwap;

    uint256 public startBlock;

    bool public hasRetrievedUnsoldPresale = false;

    event MyFriendsSwap(address sender, uint256 amount);
    event ArcadiumSwap(address sender, uint256 amount);
    event RetrieveUnclaimedTokens(uint256 MyFriendsAmount, uint256 Arcadiummount);
    event StartBlockChanged(uint256 newStartBlock);

    constructor(uint256 _startBlock, L2LithSwap _l2LithSwap, PreMyFriends _preMyFriendsAddress, address _preArcadiumAddress, address _myFriendsAddress, address _arcadiumAddress) {
        require(block.number < _startBlock, "cannot set start block in the past!");
        require(address(_preMyFriendsAddress) != _preArcadiumAddress, "preMyFriends cannot be equal to preArcadium");
        require(address(_myFriendsAddress) != _arcadiumAddress, "preMyFriends cannot be equal to preArcadium");
        require(address(_preMyFriendsAddress) != address(0), "_preMyFriendsAddress cannot be the zero address");
        require(_myFriendsAddress != address(0), "_MyFriendsAddress cannot be the zero address");

        startBlock = _startBlock;

        l2LithSwap = _l2LithSwap;

        preMyFriends = _preMyFriendsAddress;
        preArcadiumAddress = _preArcadiumAddress;
        myFriendsAddress = _myFriendsAddress;
        arcadiumAddress = _arcadiumAddress;
    }

    function swapPreMyFriendsForMyFriends(uint256 myFriendsSwapAmount) external nonReentrant {
        require(block.number >= startBlock, "token redemption hasn't started yet, good things come to those that wait");
        require(ERC20(myFriendsAddress).balanceOf(address(this)) >= myFriendsSwapAmount, "Not Enough tokens in contract for swap");

        preMyFriends.transferFrom(msg.sender, BURN_ADDRESS, myFriendsSwapAmount);
        ERC20(myFriendsAddress).transfer(msg.sender, myFriendsSwapAmount);

        emit MyFriendsSwap(msg.sender, myFriendsSwapAmount);
    }

    function swapPreArcadiumForArcadium(uint256 arcadiumSwapAmount) external nonReentrant {
        require(block.number >= startBlock, "token redemption hasn't started yet, good things come to those that wait");
        require(ERC20(arcadiumAddress).balanceOf(address(this)) >= arcadiumSwapAmount, "Not Enough tokens in contract for swap");

        ERC20(preArcadiumAddress).transferFrom(msg.sender, BURN_ADDRESS, arcadiumSwapAmount);
        ERC20(arcadiumAddress).transfer(msg.sender, arcadiumSwapAmount);

        emit ArcadiumSwap(msg.sender, arcadiumSwapAmount);
    }

    function sendUnclaimedsToFeeAddress() external onlyOwner {
        require(block.number > l2LithSwap.endBlock(), "can only retrieve excess tokens after lith swap has ended");
        require(block.number > preMyFriends.endBlock(), "can only retrieve excess tokens after presale has ended");
        require(!hasRetrievedUnsoldPresale, "can only burn unsold presale once!");

        uint256 wastedPreMyFriendsTokend = preMyFriends.preMyFriendsRemaining() + l2LithSwap.preMyFriendsRemaining();
        uint256 wastedPreArcadiumTokens = preMyFriends.preArcadiumRemaining() + l2LithSwap.preArcadiumRemaining();

        require(wastedPreMyFriendsTokend <= ERC20(myFriendsAddress).balanceOf(address(this)),
            "retreiving too much preMyFriends, has this been setup properly?");

        require(wastedPreArcadiumTokens <= ERC20(arcadiumAddress).balanceOf(address(this)),
            "retreiving too much preArcadium, has this been setup properly?");

        if (wastedPreMyFriendsTokend > 0)
            ERC20(myFriendsAddress).transfer(feeAddress, wastedPreMyFriendsTokend);

        if (wastedPreArcadiumTokens > 0)
            ERC20(arcadiumAddress).transfer(feeAddress, wastedPreArcadiumTokens);

        hasRetrievedUnsoldPresale = true;

        emit RetrieveUnclaimedTokens(wastedPreMyFriendsTokend, wastedPreArcadiumTokens);
    }

    function setStartBlock(uint256 _newStartBlock) external onlyOwner {
        require(block.number < startBlock, "cannot change start block if sale has already commenced");
        require(block.number < _newStartBlock, "cannot set start block in the past");
        startBlock = _newStartBlock;

        emit StartBlockChanged(_newStartBlock);
    }
}