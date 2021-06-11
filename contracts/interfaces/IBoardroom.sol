// SPDX-License-Identifier: MIT
pragma solidity >= 0.5.0;

interface IBoardroom {
    function balanceOf(address _director) external view returns (uint256);

    function earned(address _director) external view returns (uint256);

    function canWithdraw(address _director) external view returns (bool);

    function canClaimReward(address _director) external view returns (bool);

    function round() external view returns (uint256);

    function nextRoundPoint() external view returns (uint256);

    function getKAIPrice() external view returns (uint256);

    function setLockUp(uint256 _withdrawLockupRounds, uint256 _rewardLockupRounds) external;

    function stake(uint256 _amount) external;

    function withdraw(uint256 _amount) external;

    function exit() external;

    function claimReward() external;

    function allocateSeigniorage(uint256 _amount) external;

    function governanceRecoverUnsupported(address _token, uint256 _amount, address _to) external;
}
