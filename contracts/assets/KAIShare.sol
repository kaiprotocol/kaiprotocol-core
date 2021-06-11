// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../owner/Operator.sol";
import "./kERC20.sol";

contract KAIShare is kERC20, Operator {
    using SafeMath for uint256;

    uint256 public constant TOTAL_SUPPLY = 3000000 ether;
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 2400000 ether;
    uint256 public constant INITIAL_MINT = 2000 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = TOTAL_SUPPLY - FARMING_POOL_REWARD_ALLOCATION - INITIAL_MINT; // 20%

    uint256 public constant VESTING_DURATION = 730 days; // 2 years
    uint256 public startTime = 1623222000; // 2021 06 09 07:00 UTC
    uint256 public endTime = startTime + VESTING_DURATION; // 2023 06 09 07:00 UTC

    uint256 public devFundRewardRate = DEV_FUND_POOL_ALLOCATION / VESTING_DURATION;
    address public devFund;
    uint256 public devFundLastClaimed = startTime;

    bool public rewardPoolDistributed = false;

    constructor(uint256 _startTime) public kERC20("Kai Share Token", "sKAI") {
        startTime = _startTime;
        devFundLastClaimed = startTime;
        endTime = startTime + VESTING_DURATION;
        _mint(msg.sender, INITIAL_MINT); // mint sKAI for initial pools deployment
        devFund = msg.sender;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public onlyOperator {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOperator {
        super.burnFrom(account, amount);
    }
}
