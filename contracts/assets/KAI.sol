// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "../owner/Operator.sol";
import "./kERC20.sol";

contract KAI is kERC20, Operator {
    uint256 public constant INITIAL_MINT = 50000 ether;
    uint256 public constant INITIAL_DISTRIBUTION = 300000 ether;

    bool public rewardPoolDistributed = false;

    /**
     * @notice Constructs the KAI ERC-20 contract.
     */
    constructor() public kERC20("Kai Token", "KAI") {
        // Mints KAI to contract creator for initial pool setup
        _mint(msg.sender, INITIAL_MINT);
    }

    /**
     * @notice Operator mints KAI to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of KAI to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public onlyOperator {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public onlyOperator {
        super.burnFrom(account, amount);
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _distributionPool) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_distributionPool != address(0), "!_distributionPool");
        rewardPoolDistributed = true;
        _mint(_distributionPool, INITIAL_DISTRIBUTION);
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}
