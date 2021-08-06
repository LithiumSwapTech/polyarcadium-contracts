// The locker stores IERC20 tokens and only allows the owner to withdraw them after the UNLOCK_BLOCKNUMBER has been reached.
import "@openzeppelin/contracts/access/Ownable.sol";

import "./libs/IERC20.sol";

contract Locker is Ownable {
    uint256 public immutable UNLOCK_BLOCKNUMBER;

    event Claim(IERC20 token, address to);


    /**
     * @notice Constructs the ArcadiumToken contract.
     */
    constructor(uint256 blockNumber) public {
        UNLOCK_BLOCKNUMBER = blockNumber;
    }

    // claimToken allows the owner to withdraw tokens sent manually to this contract.
    // It is only callable once UNLOCK_BLOCKNUMBER has passed.
    function claimToken(IERC20 token, address to) external onlyOwner {
        require(block.number > UNLOCK_BLOCKNUMBER, "still vesting...");

        token.transfer(to, token.balanceOf(address(this)));

        emit Claim(token, to);
    }
}