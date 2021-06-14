// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

contract TreasuryAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of treasury
    */
    address public implementation;

    /**
    * @notice Pending brains of treasury
    */
    address public pendingImplementation;
}

contract TreasuryStorage is TreasuryAdminStorage {
    /* ========= CONTRACT GUARD VARIABLES ======== */
    
    mapping(uint256 => mapping(address => bool)) internal _status;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 8 hours;

    /* ========== STATE VARIABLES ========== */
    bool public initialized;

    // round
    uint256 public startTime;
    uint256 public round = 0;
    uint256 public roundSupplyContractionLeft = 0;

    // core components
    address public kai;
    address public bkai;
    address public skai;

    address public boardroom;
    address public kaiOracle;

    // price
    uint256 public kaiPriceOne;
    uint256 public previousRoundKAIPrice;

    uint256 public seigniorageSaved;

    // protocol parameters
    uint256 public bootstrapRounds;
    uint256 public bootstrapSupplyExpansionPercent;
    uint256 public maxSupplyExpansionPercent;
    uint256 public maxSupplyExpansionPercentInDebtPhase;
    uint256 public bkaiDepletionFloorPercent;
    uint256 public seigniorageExpansionRate;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDeptRatioPercent;

    uint256 public allocateSeigniorageSalary;
    uint256 public redeemPenaltyRate;
    uint256 public mintingFactorForPayingDebt;
    address public teamFund;
    uint256 public teamFundSharedPercent;
    address public buyBackFund;
    uint256 public buyBackFundExpansionRate;
    uint256 public maxBuyBackFundExpansion;

    uint256 public burnKAIAmount;
}
