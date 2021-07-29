// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./libs/IERC20.sol";
import "./libs/SafeERC20.sol";
import "./libs/IArcadiumReferral.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./MyFriendsToken.sol";
import "./ArcadiumToken.sol";


// MasterChef is the master of Arcadium. He can make Arcadium and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once ARCADIUM is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public usdcRewardCurrency;

    // Burn address
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // Founder 1 address
    address public constant FOUNDER1_ADDRESS = 0x3a1D1114269d7a786C154FE5278bF5b1e3e20d31;
    // Founder 2 address
    address public constant FOUNDER2_ADDRESS = 0x30139dfe2D78aFE7fb539e2F2b765d794fe52cB4;

    // less for testing.
    uint256 initialFounderMyFriendsStake = 18750 * (10 ** 18);

    // Must be after startBlock.
    uint256 public founderFinalLockupEndBlock;

    uint256 public totalUSDCCollected = 0;

    uint256 accDepositUSDCRewardPerShare = 0;

    // The MYFRIENDS TOKEN!
    MyFriendsToken myFriends;
    // The ARCADIUM TOKEN!
    ArcadiumToken arcadium;
    // Arcadium's trusty utility belt.
    RHCPToolBox arcadiumToolBox;

    uint256 public arcadiumReleaseGradient;
    uint256 public endArcadiumGradientBlock;
    uint256 public endGoalArcadiumEmission;
    bool public isIncreasingGradient = false;

    // MYFRIENDS tokens created per block.
    uint256 public constant myFriendsPerBlock = 32 * (10 ** 15);

    // The block number when ARCADIUM & MYFRIENDS mining ends.
    uint256 public myFriendsEmmissionEndBlock = type(uint256).max;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 arcadiumRewardDebt;     // Reward debt. See explanation below.
        uint256 myFriendsRewardDebt;     // Reward debt. See explanation below.
        uint256 usdcRewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of ARCADIUMs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accArcadiumPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accArcadiumPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. ARCADIUMs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that ARCADIUMs distribution occurs.
        uint256 accArcadiumPerShare;   // Accumulated ARCADIUMs per share, times 1e24. See below.
        uint256 accMyFriendsPerShare;   // Accumulated MYFRIENDSs per share, times 1e24. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint8 tokenType;          // 0=Token, 1=LP Token
        uint256 totalLocked;      // total units locked in the pool
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when normal ARCADIUM mining starts.
    uint256 public startBlock;


    // The last checked balance of ARCADIUM in the burn waller
    uint256 public lastArcadiumBurnBalance = 0;
    // How much of burn do myFriends stakers get out of 10000
    uint256 public myFriendsShareOfBurn = 8197;

    // Arcadium referral contract address.
    IArcadiumReferral arcadiumReferral;
    // Referral commission rate in basis points.
    // This is split into 2 halves 3% for the referrer and 3% for the referee.
    uint16 public constant referralCommissionRate = 600;

    uint256 public gradientEra = 1;

    uint256 public gradient2EndBlock;
    uint256 public gradient2EndEmmissions = 768915 * (10 ** 12);

    uint256 public gradient3EndBlock;
    uint256 public gradient3EndEmmissions  = 153783 * (10 ** 13);

    uint256 public myFriendsPID = 0;

    uint256 public constant maxPools = 69;

    event addPool(uint256 indexed pid, uint8 tokenType, uint256 allocPoint, address lpToken, uint256 depositFeeBP);
    event setPool(uint256 indexed pid, uint8 tokenType, uint256 allocPoint, uint256 depositFeeBP);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event GradientUpdated(uint256 newEndGoalArcadiumEmmission, uint256 newEndArcadiumEmmissionBlock);

    constructor(
        MyFriendsToken _myFriends,
        ArcadiumToken _arcadium,
        RHCPToolBox _arcadiumToolBox,
        address _usdcCurrencyAddress,
        uint256 _startBlock,
        uint256 _founderFinalLockupEndBlock,
        uint256 _beginningArcadiumEmission,
        uint256 _endArcadiumEmission,
        uint256 _gradient1EndBlock,
        uint256 _gradient2EndBlock,
        uint256 _gradient3EndBlock
    ) public {
        myFriends = _myFriends;
        arcadium = _arcadium;
        arcadiumToolBox = _arcadiumToolBox;

        startBlock = _startBlock;
        usdcRewardCurrency = IERC20(_usdcCurrencyAddress);

        require(_startBlock < _founderFinalLockupEndBlock, "founder MyFriends lockup block too early");
        founderFinalLockupEndBlock = _founderFinalLockupEndBlock;

        require(_startBlock < _gradient1EndBlock + 40, "gradient period 1 invalid");
        require(_gradient1EndBlock < _gradient2EndBlock + 40, "gradient period 2 invalid");
        require(_gradient2EndBlock < _gradient3EndBlock + 40, "gradient period 3 invalid");

        require(_beginningArcadiumEmission > 0.166666 ether && _endArcadiumEmission > 0.166666 ether,
            "ARCADIUM release must be > 0.166666 per block");

        endArcadiumGradientBlock = _gradient1EndBlock;
        endGoalArcadiumEmission = _endArcadiumEmission;

        gradient2EndBlock = _gradient2EndBlock;
        gradient3EndBlock = _gradient3EndBlock;

        require(endGoalArcadiumEmission < 101 ether, "cannot allow > than 101 ARCADIUM per block");

        if (endArcadiumGradientBlock > startBlock && _beginningArcadiumEmission != endGoalArcadiumEmission) {
            isIncreasingGradient = endGoalArcadiumEmission > _beginningArcadiumEmission;
            if (isIncreasingGradient)
                arcadiumReleaseGradient = ((endGoalArcadiumEmission - _beginningArcadiumEmission) * 1e24) / (endArcadiumGradientBlock - startBlock);
            else
                arcadiumReleaseGradient = ((_beginningArcadiumEmission - endGoalArcadiumEmission) * 1e24) / (endArcadiumGradientBlock - startBlock);
        } else {
            require(_beginningArcadiumEmission == endGoalArcadiumEmission, "invalid arcadium release data");
            arcadiumReleaseGradient = 0;
        }
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint8 _tokenType, uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(poolInfo.length < maxPools,  "too many pools!");
        // Make sure the provided token is ERC20
        _lpToken.balanceOf(address(this));

        require(_depositFeeBP <= 401/*, "add: invalid deposit fee basis points"*/);
        require(_tokenType == 0 || _tokenType == 1, "invalid token type");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accArcadiumPerShare: 0,
            accMyFriendsPerShare: 0,
            depositFeeBP: _depositFeeBP,
            tokenType: _tokenType,
            totalLocked: 0
        }));

        // We must track the pid of myfriends token
        if (address(_lpToken) == address(myFriends))
            myFriendsPID = poolInfo.length - 1;

        emit addPool(poolInfo.length - 1, _tokenType, _allocPoint, address(_lpToken), _depositFeeBP);
    }

    // Update the given pool's ARCADIUM allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint8 _tokenType, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 401, "bad depositBP");
        require(_tokenType == 0 || _tokenType == 1, "invalid token type");

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].tokenType = _tokenType;
        //poolInfo[_pid].totalLocked = poolInfo[_pid].totalLocked;

        emit setPool(_pid, _tokenType, _allocPoint, _depositFeeBP);
    }

    // View function to see pending USDCs on frontend.
    function pendingUSDC(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[myFriendsPID][_user];

        return ((user.amount * accDepositUSDCRewardPerShare) / (1e24)) - user.usdcRewardDebt;
    }

    // View function to see pending ARCADIUMs on frontend.
    function pendingArcadium(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accArcadiumPerShare = pool.accArcadiumPerShare;

        uint256 lpSupply = pool.totalLocked;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 farmingLimitedBlock = block.number <= gradient3EndBlock ? block.number : gradient3EndBlock;
            uint256 release = arcadiumToolBox.getArcadiumRelease(isIncreasingGradient, arcadiumReleaseGradient, endArcadiumGradientBlock, endGoalArcadiumEmission, pool.lastRewardBlock, farmingLimitedBlock);
            uint256 arcadiumReward = (release * pool.allocPoint) / totalAllocPoint;
            accArcadiumPerShare = accArcadiumPerShare + ((arcadiumReward * 1e24) / lpSupply);
        }
        return ((user.amount * accArcadiumPerShare) / 1e24) - user.arcadiumRewardDebt;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMyFriendsMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        // As we set the multiplier to 0 here after myFriendsEmmissionEndBlock
        // deposits aren't blocked after farming ends.
        if (_from > myFriendsEmmissionEndBlock)
            return 0;
        if (_to > myFriendsEmmissionEndBlock)
            return myFriendsEmmissionEndBlock - _from;
        else
            return _to - _from;
    }

    // View function to see pending ARCADIUMs on frontend.
    function pendingMyFriends(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMyFriendsPerShare = pool.accMyFriendsPerShare;

        uint256 lpSupply = pool.totalLocked;
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 release = getMyFriendsMultiplier(pool.lastRewardBlock, block.number);
            uint256 myFriendsReward = (release * myFriendsPerBlock * pool.allocPoint) / totalAllocPoint;
            accMyFriendsPerShare = accMyFriendsPerShare + ((myFriendsReward * 1e24) / lpSupply);
        }

        return ((user.amount * accMyFriendsPerShare) / 1e24) - user.myFriendsRewardDebt;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        // we only allow 80 pools to be upda
        for (uint256 pid = 0; pid < length && pid < maxPools; ++pid) {
            updatePool(pid);
        }
    }

    // Transfers any excess coins gained through reflection
    // to ARCADIUM and MYFRIENDS
    function skimPool(uint256 poolId) internal {
        PoolInfo storage pool = poolInfo[poolId];
        //n Cannot skim any tokens we use for staking rewards.
        if (isNativeToken(address(pool.lpToken)))
            return;

        uint256 skim = pool.lpToken.balanceOf(address(this)) > pool.totalLocked ?
            pool.lpToken.balanceOf(address(this)) - pool.totalLocked :
            0;

        // No point skimming super small dust.
        if (skim < ((10 ** 2) * (10 ** ERC20(address(pool.lpToken)).decimals())))
            return;

        uint256 myFriendsShare = skim / 2;
        uint256 arcadiumShare = skim - myFriendsShare;
        pool.lpToken.safeTransfer(address(myFriends), myFriendsShare);
        pool.lpToken.safeTransfer(address(arcadium), arcadiumShare);
    }

    // Updates arcadium release goal and phase change duration
    function updateArcadiumRelease(uint256 endBlock, uint256 endArcadiumEmission) internal returns (bool) {
        // give some buffer as to stop extrememly large gradients
        if (block.number + 4 >= endBlock)
            return false;

        // this will be called infrequently
        // and deployed are on a cheap gas network POLYGON (MATIC)
        // Founders will also be attempting the gradient update
        // at the right time.
        massUpdatePools();

        uint256 currentArcadiumEmission = arcadiumToolBox.getArcadiumEmissionForBlock(block.number,
            isIncreasingGradient, arcadiumReleaseGradient, endArcadiumGradientBlock, endGoalArcadiumEmission);

        isIncreasingGradient = endArcadiumEmission > currentArcadiumEmission;
        arcadiumReleaseGradient = arcadiumToolBox.calcEmissionGradient(block.number,
            currentArcadiumEmission, endBlock, endArcadiumEmission);

        endArcadiumGradientBlock = endBlock;
        endGoalArcadiumEmission = endArcadiumEmission;

        emit GradientUpdated(endGoalArcadiumEmission, endArcadiumGradientBlock);

        return true;
    }

    function autoUpdateArcadiumGradient() internal returns (bool) {
        if (block.number < endArcadiumGradientBlock || gradientEra > 2)
            return false;

        // still need to check if we are too late even though we assert in updateArcadiumRelease
        // as we might need to skip this gradient era and not fail this assert
        if (gradientEra == 1) {
            if (block.number + 4 < gradient2EndBlock &&
                updateArcadiumRelease(gradient2EndBlock, gradient2EndEmmissions)) {
                gradientEra = gradientEra + 1;
                return true;
            }
            // if we missed it skip to the next era anyway
            gradientEra = gradientEra + 1;

        }

        if (gradientEra == 2) {
            if (block.number + 4 < gradient3EndBlock &&
                updateArcadiumRelease(gradient3EndBlock, gradient3EndEmmissions))
                gradientEra = gradientEra + 1;
                return true;
        }

        return false;
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock)
            return;

        uint256 lpSupply = pool.totalLocked;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 farmingLimitedBlock = block.number <= gradient3EndBlock ? block.number : gradient3EndBlock;
        uint256 arcadiumRelease = arcadiumToolBox.getArcadiumRelease(isIncreasingGradient, arcadiumReleaseGradient, endArcadiumGradientBlock, endGoalArcadiumEmission, pool.lastRewardBlock, farmingLimitedBlock);
        uint256 arcadiumReward = (arcadiumRelease * pool.allocPoint) / totalAllocPoint;

        // Arcadium Txn fees ONLY for myFriends stakers.
        if (address(pool.lpToken) == address(myFriends)) {
            uint256 burnBalance = arcadium.balanceOf(BURN_ADDRESS);
            arcadiumReward = arcadiumReward + (((burnBalance - lastArcadiumBurnBalance) * myFriendsShareOfBurn) / 10000);

            lastArcadiumBurnBalance = burnBalance;
        }

        // the end of gradient 3 is the end of arcadium release
        if (arcadiumReward > 0)
            arcadium.mint(address(this), arcadiumReward);

        if (myFriendsEmmissionEndBlock == type(uint256).max && address(pool.lpToken) != address(myFriends) &&
            totalAllocPoint > poolInfo[myFriendsPID].allocPoint) {

            uint256 myFriendsRelease = getMyFriendsMultiplier(pool.lastRewardBlock, block.number);

            if (myFriendsRelease > 0) {
                uint256 myFriendsReward = ((myFriendsRelease * myFriendsPerBlock * pool.allocPoint) / (totalAllocPoint - poolInfo[myFriendsPID].allocPoint));

                // Getting MyFriends allocated specificlly for initial distribution.
                myFriendsReward = myFriends.distribute(address(this), myFriendsReward);
                // once we run out end myfriends emmissions.
                if (myFriendsReward == 0 || myFriends.balanceOf(address(myFriends)) == 0)
                    myFriendsEmmissionEndBlock = block.number;

                pool.accMyFriendsPerShare = pool.accMyFriendsPerShare + ((myFriendsReward * 1e24) / lpSupply);
            }
        }

        pool.accArcadiumPerShare = pool.accArcadiumPerShare + ((arcadiumReward * 1e24) / lpSupply);
        pool.lastRewardBlock = block.number;
    }

    // Return if address a founder address.
    function isFounder(address addr) public pure returns (bool) {
        return addr == FOUNDER1_ADDRESS || addr == FOUNDER2_ADDRESS;
    }

    // Return if address a founder address.
    function isNativeToken(address addr) public view returns (bool) {
        return addr == address(myFriends) || addr == address(arcadium);
    }

    // Deposit LP tokens to MasterChef for ARCADIUM allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        // check if we need to update the gradients
        // this will only do useful work a few times in masterChefs life
        // if autoUpdateArcadiumGradient is called we have already called massUpdatePools.
        if (!autoUpdateArcadiumGradient())
            updatePool(_pid);

        if (_amount > 0 && address(arcadiumReferral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            arcadiumReferral.recordReferral(msg.sender, _referrer);
        }

        payOrLockupPendingMyFriendsArcadium(_pid);
        if (address(pool.lpToken) == address(myFriends)) {
            payPendingUSDCReward();
        }
        if (_amount > 0) {
            // Accept the balance of coins we recieve (useful for coins which take fees).
            uint256 previousBalance = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)) - previousBalance;
            require(_amount > 0, "no funds were recieved");

            if (pool.depositFeeBP > 0 && !isNativeToken(address(pool.lpToken))) {
                uint256 depositFee = ((_amount * pool.depositFeeBP) / 10000);
                // For LPs arcadium handles it 100%, destroys and distributes
                uint256 arcadiumDepositFee = pool.tokenType == 1 ? depositFee : ((depositFee * 1e24) / 4) / 1e24;
                pool.lpToken.safeTransfer(address(arcadium), arcadiumDepositFee);
                // arcadium handles all LP type tokens
                arcadium.swapDepositFeeForETH(address(pool.lpToken), pool.tokenType);

                uint256 usdcRecieved = 0;
                if (pool.tokenType == 1) {
                    // make sure we pick up any tokens from destroyed LPs from Arcadium
                    // (not guaranteed to have single sided pools to trigger).
                   usdcRecieved  = myFriends.convertDepositFeesToUSDC(address(pool.lpToken), 1);
                }
                // Lp tokens get liquidated in Arcadium not MyFriends.
                if (pool.tokenType == 0) {
                    pool.lpToken.safeTransfer(address(myFriends), depositFee - arcadiumDepositFee);
                    usdcRecieved = myFriends.convertDepositFeesToUSDC(address(pool.lpToken), 0);
                }

                // pickup up and usdc that hasn't been collected yet (OTC or from Arcadium).
                usdcRecieved = usdcRecieved + myFriends.convertDepositFeesToUSDC(address(usdcRewardCurrency), 0);

                // MyFriends pool is always pool 0.
                if (poolInfo[myFriendsPID].totalLocked > 0) {
                    accDepositUSDCRewardPerShare = accDepositUSDCRewardPerShare + ((usdcRecieved * 1e24) / poolInfo[myFriendsPID].totalLocked);
                    totalUSDCCollected = totalUSDCCollected + usdcRecieved;
                }

                user.amount = (user.amount + _amount) - depositFee;
                pool.totalLocked = (pool.totalLocked + _amount) - depositFee;
            } else {
                user.amount = user.amount + _amount;

                pool.totalLocked = pool.totalLocked + _amount;
            }
        }

        user.arcadiumRewardDebt = ((user.amount * pool.accArcadiumPerShare) / 1e24);
        user.myFriendsRewardDebt = ((user.amount * pool.accMyFriendsPerShare) / 1e24);

        if (address(pool.lpToken) == address(myFriends))
            user.usdcRewardDebt = ((user.amount * accDepositUSDCRewardPerShare) / 1e24);

        skimPool(_pid);

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Return how much myFriends should be saked by the founders at any time.
    function getCurrentComplsoryFounderMyFriendsDeposit(uint256 blocknum) public view returns (uint256) {
        // No MyFriends withdrawals before farmiing
        if (blocknum < startBlock)
            return type(uint256).max;
        if (blocknum > founderFinalLockupEndBlock)
            return 0;

        uint256 lockupDuration = founderFinalLockupEndBlock - startBlock;
        uint256 currentUpTime = blocknum - startBlock;
        return (((initialFounderMyFriendsStake * (lockupDuration - currentUpTime) * 1e6) / lockupDuration) / 1e6);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        if (address(pool.lpToken) == address(myFriends) && isFounder(msg.sender)) {
            require((user.amount - _amount) >= getCurrentComplsoryFounderMyFriendsDeposit(block.number),
                "founder wallets are locked up");
        }

        updatePool(_pid);
        payOrLockupPendingMyFriendsArcadium(_pid);
        if (address(pool.lpToken) == address(myFriends))
            payPendingUSDCReward();

        if (_amount > 0) {
            user.amount = user.amount - _amount;
            pool.totalLocked = pool.totalLocked - _amount;
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }

        user.arcadiumRewardDebt = ((user.amount * pool.accArcadiumPerShare) / 1e24);
        user.myFriendsRewardDebt = ((user.amount * pool.accMyFriendsPerShare) / 1e24);

        if (address(pool.lpToken) == address(myFriends))
            user.usdcRewardDebt = ((user.amount * accDepositUSDCRewardPerShare) / 1e24);

        skimPool(_pid);

        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.arcadiumRewardDebt = 0;
        user.myFriendsRewardDebt = 0;
        user.usdcRewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        // In the case of an accounting error, we choose to let the user emergency withdraw anyway
        if (pool.totalLocked >=  amount)
            pool.totalLocked = pool.totalLocked - amount;
        else
            pool.totalLocked = 0;

        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Pay pending ARCADIUMs & MYFRIENDSs.
    function payOrLockupPendingMyFriendsArcadium(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 arcadiumPending = ((user.amount * pool.accArcadiumPerShare) / 1e24) - user.arcadiumRewardDebt;
        uint256 myFriendsPending = ((user.amount * pool.accMyFriendsPerShare) / 1e24) - user.myFriendsRewardDebt;

        if (arcadiumPending > 0) {
            // send rewards
            if (isFounder(msg.sender)) {
                safeTokenTransfer(address(arcadium), BURN_ADDRESS, arcadiumPending/2);
                arcadiumPending = arcadiumPending - arcadiumPending/2;
            }
            // arcadiumPending can't be zero
            safeTokenTransfer(address(arcadium), msg.sender, arcadiumPending);
            payReferralCommission(msg.sender, arcadiumPending);
        }
        if (myFriendsPending > 0) {
            // send rewards
            if (isFounder(msg.sender))
                safeTokenTransfer(address(myFriends), BURN_ADDRESS, myFriendsPending);
            else
                safeTokenTransfer(address(myFriends), msg.sender, myFriendsPending);
        }
    }

    // Pay pending USDC from the MyFriends staking reward scheme.
    function payPendingUSDCReward() internal {
        UserInfo storage user = userInfo[myFriendsPID][msg.sender];

        uint256 usdcPending = ((user.amount * accDepositUSDCRewardPerShare) / 1e24) - user.usdcRewardDebt;

        if (usdcPending > 0) {
            // send rewards
            myFriends.transferUSDCToUser(msg.sender, usdcPending);
        }
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough ARCADIUMs.
    function safeTokenTransfer(address token, address _to, uint256 _amount) internal {
        uint256 tokenBal = IERC20(token).balanceOf(address(this));
        if (_amount > tokenBal) {
            IERC20(token).safeTransfer(_to, tokenBal);
        } else {
            IERC20(token).safeTransfer(_to, _amount);
        }
    }

    // Update the arcadium referral contract address by the owner
    function setArcadiumReferral(IArcadiumReferral _arcadiumReferral) external onlyOwner {
        require(address(_arcadiumReferral) != address(0), "arcadiumReferral cannot be the 0 address");
        arcadiumReferral = _arcadiumReferral;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(arcadiumReferral) != address(0) && referralCommissionRate > 0) {
            address referrer = arcadiumReferral.getReferrer(_user);
            uint256 commissionAmount = ((_pending * referralCommissionRate) / 10000);

            if (referrer != address(0) && commissionAmount > 0) {
                arcadium.mint(referrer, commissionAmount / 2);
                arcadium.mint(_user, commissionAmount - (commissionAmount / 2));
                arcadiumReferral.recordReferralCommission(referrer, commissionAmount);
            }
        }
    }
}
