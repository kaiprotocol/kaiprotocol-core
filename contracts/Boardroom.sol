// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/ITreasury.sol";

contract sKAIWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public skai;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        skai.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public {
        uint256 directorSKAI = _balances[msg.sender];
        require(directorSKAI >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = directorSKAI.sub(amount);
        skai.safeTransfer(msg.sender, amount);
    }
}

contract Boardroom is sKAIWrapper, ContractGuard, Operator {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Boardseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 roundTimerStart;
    }

    struct BoardSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerSKAI;
    }

    /* ========== STATE VARIABLES ========== */
    bool public initialized;

    IERC20 public kai;
    ITreasury public treasury;

    mapping(address => Boardseat) public directors;
    BoardSnapshot[] public boardHistory;

    uint256 public withdrawLockupRounds;
    uint256 public rewardLockupRounds;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier directorExists {
        require(balanceOf(msg.sender) > 0, "Boardroom: The director does not exist");
        _;
    }

    modifier updateReward(address director) {
        if (director != address(0)) {
            Boardseat memory seat = directors[director];
            seat.rewardEarned = earned(director);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            directors[director] = seat;
        }
        _;
    }

    /* ========== GOVERNANCE ========== */
    constructor () public {
        BoardSnapshot memory genesisSnapshot = BoardSnapshot({time : block.number, rewardReceived : 0, rewardPerSKAI : 0});
        boardHistory.push(genesisSnapshot);

        withdrawLockupRounds = 4; // Lock for 4 rounds (32h) before release withdraw
        rewardLockupRounds = 2; // Lock for 2 rounds (16h) before release claimReward
    }

    function initialize(
        IERC20 _kai,
        IERC20 _skai,
        ITreasury _treasury
    ) public onlyOperator {
        require(initialized == false, "already initiallized");

        kai = _kai;
        skai = _skai;
        treasury = _treasury;

        initialized = true;

        emit Initialized(msg.sender, block.number);
    }

    function setLockUp(uint256 _withdrawLockupRounds, uint256 _rewardLockupRounds) external onlyOperator {
        require(_withdrawLockupRounds >= _rewardLockupRounds && _withdrawLockupRounds <= 42, "_withdrawLockupRounds: out of range"); // <= 2 week
        withdrawLockupRounds = _withdrawLockupRounds;
        rewardLockupRounds = _rewardLockupRounds;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
        return boardHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address director) public view returns (uint256) {
        return directors[director].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address director) internal view returns (BoardSnapshot memory) {
        return boardHistory[getLastSnapshotIndexOf(director)];
    }

    function canWithdraw(address director) external view returns (bool) {
        return directors[director].roundTimerStart.add(withdrawLockupRounds) <= treasury.round();
    }

    function canClaimReward(address director) external view returns (bool) {
        return directors[director].roundTimerStart.add(rewardLockupRounds) <= treasury.round();
    }

    function round() external view returns (uint256) {
        return treasury.round();
    }

    function nextRoundPoint() external view returns (uint256) {
        return treasury.nextRoundPoint();
    }

    function getKAIPrice() external view returns (uint256) {
        return treasury.getKAIPrice();
    }

    // =========== Director getters

    function rewardPerSKAI() public view returns (uint256) {
        return getLatestSnapshot().rewardPerSKAI;
    }

    function earned(address director) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerSKAI;
        uint256 storedRPS = getLastSnapshotOf(director).rewardPerSKAI;

        return balanceOf(director).mul(latestRPS.sub(storedRPS)).div(1e18).add(directors[director].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) public onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot stake 0");
        sKAIWrapper.stake(amount);
        directors[msg.sender].roundTimerStart = treasury.round(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public onlyOneBlock directorExists updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(directors[msg.sender].roundTimerStart.add(withdrawLockupRounds) <= treasury.round(), "Boardroom: still in withdraw lockup");
        claimReward();
        sKAIWrapper.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = directors[msg.sender].rewardEarned;
        if (reward > 0) {
            require(directors[msg.sender].roundTimerStart.add(rewardLockupRounds) <= treasury.round(), "Boardroom: still in reward lockup");
            directors[msg.sender].roundTimerStart = treasury.round(); // reset timer
            directors[msg.sender].rewardEarned = 0;
            kai.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(totalSupply() > 0, "Boardroom: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerSKAI;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardSnapshot memory newSnapshot = BoardSnapshot({
            time: block.number,
            rewardReceived: amount,
            rewardPerSKAI: nextRPS
        });
        boardHistory.push(newSnapshot);

        kai.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(kai), "KAI");
        require(address(_token) != address(skai), "sKAI");
        _token.safeTransfer(_to, _amount);
    }
}
