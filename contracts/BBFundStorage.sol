// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

contract BBFundAdminStorage {
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

contract BBFundStorage is BBFundAdminStorage {
    // const
    uint256 public constant DAY = 86400;

    // flags
    bool public initialized;
    bool public publicAllowed;

    // price
    uint256 public kaiPriceToSell;
    uint256 public kaiPriceToBuy;

    mapping(address => uint256) public maxAmountToTrade;

    // core components
    address public strategist;

    address public kai;
    address public bkai;
    address public skai;
    address public usdt;

    address public oracle;    
    address public klayswapFactory;
    address public treasury;
}
