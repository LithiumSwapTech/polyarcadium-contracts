pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libs/IERC20.sol";
import "../libs/ERC20.sol";

// PreArcadium
contract PreArcadium is ERC20('PREARCADIUM', 'PREARCADIUM') {
    constructor() {
        _mint(address(0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31), uint256(250000 * (10 ** 18)));
    }
}