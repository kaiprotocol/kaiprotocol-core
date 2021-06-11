// SPDX-License-Identifier: MIT
pragma solidity 0.5.6;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./interfaces/IKAIAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IBoardroom.sol";

import "./TreasuryStorage.sol";
import "./TreasuryUni.sol";
import "./interfaces/ITreasury.sol";

/**
 * @title KAI Protocol Treasury contract
 * @notice Monetary policy logic to adjust supplies of KAI
 */
contract TreasuryImpl is TreasuryStorage {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event RedeemedBKAI(address indexed from, uint256 kaiAmount, uint256 bkaiAmount);
    event BoughtBKAI(address indexed from, uint256 kaiAmount, uint256 bkaiAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event TeamFundFunded(uint256 timestamp, uint256 seigniorage);

    /* =================== Admin Functions =================== */
    function _become(TreasuryUni uni) public {
        require(msg.sender == uni.admin(), "only uni admin can change brains");
        uni._acceptImplementation();
    }

    /* =================== Modifier =================== */
    function checkSameOriginReentranted() internal view returns (bool) {
        return _status[block.number][tx.origin];
    }

    function checkSameSenderReentranted() internal view returns (bool) {
        return _status[block.number][msg.sender];
    }

    modifier onlyOneBlock() {
        require(!checkSameOriginReentranted(), "ContractGuard: one block, one function");
        require(!checkSameSenderReentranted(), "ContractGuard: one block, one function");

        _;

        _status[block.number][tx.origin] = true;
        _status[block.number][msg.sender] = true;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Treasury: only admin can");
        _;
    }
    modifier checkCondition {
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch {
        require(now >= nextRoundPoint(), "Treasury: not opened yet");

        _;

        round = round.add(1);
        roundSupplyContractionLeft = (getKAIPrice() >= kaiPriceOne) ? 0 : IERC20(kai).totalSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator {
        require(
            Operator(kai).operator() == address(this) &&
                Operator(bkai).operator() == address(this) &&
                Operator(skai).operator() == address(this) &&
                Operator(boardroom).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getStartTime() public view returns (uint256) {
        return startTime;
    }

    // round
    function nextRoundPoint() public view returns (uint256) {
        return startTime.add(round.mul(PERIOD));
    }

    // oracle
    function getKAIPrice() public view returns (uint256) {
        return IOracle(kaiOracle).consult(kai, 1e18);
    }

    function getKAIUpdatedPrice() public view returns (uint256) {
        return IOracle(kaiOracle).twap(kai, 1e18);
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableKAILeft() public view returns (uint256 _burnableLeft) {
        uint256  _kaiPrice = getKAIPrice();
        if (_kaiPrice < kaiPriceOne) {
            uint256 _kaiSupply = IERC20(kai).totalSupply();
            uint256 _bkaiMaxSupply = _kaiSupply.mul(maxDeptRatioPercent).div(10000);
            uint256 _bkaiSupply = IERC20(bkai).totalSupply();
            if (_bkaiMaxSupply > _bkaiSupply) {
                uint256 _maxMintableBKAI = _bkaiMaxSupply.sub(_bkaiSupply);
                uint256 _maxBurnableKAI = _maxMintableBKAI.mul(_kaiPrice).div(1e18);
                _burnableLeft = Math.min(roundSupplyContractionLeft, _maxBurnableKAI);
            }
        }
    }

    function getRedeemableBKAI() public view returns (uint256 _redeemableBKAI) {
        uint256  _kaiPrice = getKAIPrice();
        if (_kaiPrice > kaiPriceOne) {
            uint256 _totalKAI = IERC20(kai).balanceOf(address(this));
            uint256 _rate = getBKAIPremiumRate();
            if (_rate > 0) {
                _redeemableBKAI = _totalKAI.mul(1e18).div(_rate);
            }
        }
    }

    function getBKAIDiscountRate() public view returns (uint256 _rate) {
        uint256 _kaiPrice = getKAIPrice();
        if (_kaiPrice < kaiPriceOne) {
             _rate = kaiPriceOne;
        }
    }

    function getBKAIPremiumRate() public view returns (uint256 _rate) {
        uint256 _kaiPrice = getKAIPrice();
        if (_kaiPrice >= kaiPriceOne) {
            _rate = kaiPriceOne;
        }
    }

    /* ========== GOVERNANCE ========== */
    constructor() public {
        admin = msg.sender;
    }

    function initialize (
        address _kai,
        address _bkai,
        address _skai,
        uint256 _startTime
    ) external onlyAdmin {
        kai = _kai;
        bkai = _bkai;
        skai = _skai;
        startTime = _startTime;

        kaiPriceOne = 10**18;

        bootstrapRounds = 21; // 1 weeks (8 * 21 / 24)
        bootstrapSupplyExpansionPercent = 300; // 3%
        maxSupplyExpansionPercent = 300; // Upto 3% supply for expansion
        maxSupplyExpansionPercentInDebtPhase = 300; // Upto 3% supply for expansion in debt phase (to pay debt faster)
        bkaiDepletionFloorPercent = 10000; // 100% of BKAI supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for boardroom
        seigniorageExpansionRate = 3000; // (TWAP - 1) * 100% * 30%
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn KAI and mint bKAI)
        maxDeptRatioPercent = 3500; // Upto 35% supply of bKAI to purchase

        allocateSeigniorageSalary = 50 ether;
        redeemPenaltyRate = 0.9 ether; // 0.9, 10% penalty
        mintingFactorForPayingDebt = 10000; // 100%

        teamFund = msg.sender;
        teamFundSharedPercent = 1000; // 10%

        buyBackFund = msg.sender;
        buyBackFundExpansionRate = 1000; // 10%
        maxBuyBackFundExpansion = 300; // 3%

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(kai).balanceOf(address(this));

        emit Initialized(msg.sender, block.number);
    }

    function setBoardroom(address _boardroom) external onlyAdmin {
        boardroom = _boardroom;
    }

    function setKAIOracle(address _oracle) external onlyAdmin {
        kaiOracle = _oracle;
    }

    function setRound(uint256 _round) external onlyAdmin {
        round = _round;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent, uint256 _maxSupplyExpansionPercentInDebtPhase) external onlyAdmin {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        require(_maxSupplyExpansionPercentInDebtPhase >= 10 && _maxSupplyExpansionPercentInDebtPhase <= 1500, "_maxSupplyExpansionPercentInDebtPhase: out of range"); // [0.1%, 15%]
        require(_maxSupplyExpansionPercent <= _maxSupplyExpansionPercentInDebtPhase, "_maxSupplyExpansionPercent is over _maxSupplyExpansionPercentInDebtPhase");
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
        maxSupplyExpansionPercentInDebtPhase = _maxSupplyExpansionPercentInDebtPhase;
    }

    function setSeigniorageExpansionRate(uint256 _seigniorageExpansionRate) external onlyAdmin {
        require(_seigniorageExpansionRate >= 0 && _seigniorageExpansionRate <= 20000, "out of range"); // [0%, 200%]
        seigniorageExpansionRate = _seigniorageExpansionRate;
    }

    function setBKAIDepletionFloorPercent(uint256 _bkaiDepletionFloorPercent) external onlyAdmin {
        require(_bkaiDepletionFloorPercent >= 500 && _bkaiDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bkaiDepletionFloorPercent = _bkaiDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyAdmin {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDeptRatioPercent(uint256 _maxDeptRatioPercent) external onlyAdmin {
        require(_maxDeptRatioPercent >= 1000 && _maxDeptRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDeptRatioPercent = _maxDeptRatioPercent;
    }

    function setTeamFund(address _teamFund) external onlyAdmin {
        require(_teamFund != address(0), "zero");
        teamFund = _teamFund;
    }

    function setTeamFundSharedPercent(uint256 _teamFundSharedPercent) external onlyAdmin {
        require(_teamFundSharedPercent <= 3000, "out of range"); // <= 30%
        teamFundSharedPercent = _teamFundSharedPercent;
    }

    function setBuyBackFund(address _buyBackFund) external onlyAdmin {
        require(_buyBackFund != address(0), "zero");
        buyBackFund = _buyBackFund;
    }

    function setBuyBackFundExpansionRate(uint256 _buyBackFundExpansionRate) external onlyAdmin {
        require(_buyBackFundExpansionRate <= 10000 && _buyBackFundExpansionRate >= 0, "out of range"); // under 100%
        buyBackFundExpansionRate = _buyBackFundExpansionRate;
    }

    function setMaxBuyBackFundExpansionRate(uint256 _maxBuyBackFundExpansion) external onlyAdmin {
        require(_maxBuyBackFundExpansion <= 1000 && _maxBuyBackFundExpansion >= 0, "out of range"); // under 10%
        maxBuyBackFundExpansion = _maxBuyBackFundExpansion;
    }

    function setAllocateSeigniorageSalary(uint256 _allocateSeigniorageSalary) external onlyAdmin {
        require(_allocateSeigniorageSalary <= 100 ether, "Treasury: dont pay too much");
        allocateSeigniorageSalary = _allocateSeigniorageSalary;
    }

    function setRedeemPenaltyRate(uint256 _redeemPenaltyRate) external onlyAdmin {
        require(_redeemPenaltyRate <= 1 ether && _redeemPenaltyRate >= 0.9 ether, "out of range");
        redeemPenaltyRate = _redeemPenaltyRate;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyAdmin {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateKAIPrice() internal {
        IOracle(kaiOracle).update();
    }

    function buyBKAI(uint256 _kaiAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_kaiAmount > 0, "Treasury: cannot purchase bkais with zero amount");

        uint256 kaiPrice = getKAIPrice();
        require(kaiPrice == targetPrice, "Treasury: kai price moved");
        require(
            kaiPrice < kaiPriceOne, // price < $1
            "Treasury: kaiPrice not eligible for bkai purchase"
        );

        require(_kaiAmount <= roundSupplyContractionLeft, "Treasury: not enough bkai left to purchase");

        uint256 _rate = getBKAIDiscountRate();
        require(_rate > 0, "Treasury: invalid bkai rate");

        uint256 _bkaiAmount = _kaiAmount.mul(_rate).div(1e18);
        uint256 kaiSupply = IERC20(kai).totalSupply();
        uint256 newBKAISupply = IERC20(bkai).totalSupply().add(_bkaiAmount);
        require(newBKAISupply <= kaiSupply.mul(maxDeptRatioPercent).div(10000), "over max debt ratio");

        IKAIAsset(kai).burnFrom(msg.sender, _kaiAmount);
        IKAIAsset(bkai).mint(msg.sender, _bkaiAmount);

        roundSupplyContractionLeft = roundSupplyContractionLeft.sub(_kaiAmount);

        emit BoughtBKAI(msg.sender, _kaiAmount, _bkaiAmount);
    }

    function redeemBKAI(uint256 _bkaiAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bkaiAmount > 0, "Treasury: cannot redeem bkais with zero amount");

        uint256 kaiPrice = getKAIPrice();
        require(kaiPrice == targetPrice, "Treasury: kai price moved");
        
        uint256 _kaiAmount;
        uint256 _rate;

        if (kaiPrice >= kaiPriceOne) {
            _rate = getBKAIPremiumRate();
            require(_rate > 0, "Treasury: invalid bkai rate");
            
            _kaiAmount = _bkaiAmount.mul(_rate).div(1e18);
            
            require(IERC20(kai).balanceOf(address(this)) >= _kaiAmount, "Treasury: treasury has no more budget");

            seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _kaiAmount));
            IKAIAsset(bkai).burnFrom(msg.sender, _bkaiAmount);
            IERC20(kai).safeTransfer(msg.sender, _kaiAmount);
        }
        else {
            require(redeemPenaltyRate > 0, "Treasury: not allow");
            _kaiAmount = _bkaiAmount.mul(redeemPenaltyRate).div(1e18);
            IKAIAsset(bkai).burnFrom(msg.sender, _bkaiAmount);
            IKAIAsset(kai).mint(msg.sender, _kaiAmount);
        }

        emit RedeemedBKAI(msg.sender, _kaiAmount, _bkaiAmount);
    }

    function _sendToBoardRoom(uint256 _amount) internal {
        IKAIAsset(kai).mint(address(this), _amount);
        if (teamFundSharedPercent > 0) {
            uint256 _teamFundSharedAmount = _amount.mul(teamFundSharedPercent).div(10000);
            IERC20(kai).transfer(teamFund, _teamFundSharedAmount);
            emit TeamFundFunded(now, _teamFundSharedAmount);
            _amount = _amount.sub(_teamFundSharedAmount);
        }
        IERC20(kai).safeApprove(boardroom, 0);
        IERC20(kai).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(now, _amount);
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateKAIPrice();
        previousRoundKAIPrice = getKAIPrice();
        uint256 kaiSupply = IERC20(kai).totalSupply().sub(seigniorageSaved);
        if (round < bootstrapRounds) {
            _sendToBoardRoom(kaiSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousRoundKAIPrice > kaiPriceOne) {
                // Expansion (KAI Price > 1$): there is some seigniorage to be allocated
                uint256 bkaiSupply = IERC20(bkai).totalSupply();
                uint256 _percentage = previousRoundKAIPrice.sub(kaiPriceOne).mul(seigniorageExpansionRate).div(10000);
                uint256 _savedForBKAI;
                uint256 _savedForBoardRoom;
                if (seigniorageSaved >= bkaiSupply.mul(bkaiDepletionFloorPercent).div(10000)) {// saved enough to pay dept, mint as usual rate
                    uint256 _mse = maxSupplyExpansionPercent.mul(1e14);
                    if (_percentage > _mse) {
                        _percentage = _mse;
                    }
                    _savedForBoardRoom = kaiSupply.mul(_percentage).div(1e18);
                } else {// have not saved enough to pay dept, mint more
                    uint256 _mse = maxSupplyExpansionPercentInDebtPhase.mul(1e14);
                    if (_percentage > _mse) {
                        _percentage = _mse;
                    }
                    uint256 _seigniorage = kaiSupply.mul(_percentage).div(1e18);
                    _savedForBoardRoom = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBKAI = _seigniorage.sub(_savedForBoardRoom);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBKAI = _savedForBKAI.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForBoardRoom > 0) {
                    _sendToBoardRoom(_savedForBoardRoom);
                }
                if (_savedForBKAI > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBKAI);
                    IKAIAsset(kai).mint(address(this), _savedForBKAI);
                    emit TreasuryFunded(now, _savedForBKAI);
                }
            }
        }
        // buy-back fund mint
        if (previousRoundKAIPrice > kaiPriceOne) {
            uint256 _buyBackRate = previousRoundKAIPrice.sub(kaiPriceOne).mul(buyBackFundExpansionRate).div(10000);
            uint256 _maxBuyBackRate = maxBuyBackFundExpansion.mul(1e14);
            if (_buyBackRate > _maxBuyBackRate) {
                _buyBackRate = _maxBuyBackRate;
            }
            uint256 _savedForBuyBackFund = kaiSupply.mul(_buyBackRate).div(1e18);
            if (_savedForBuyBackFund > 0) {
                IKAIAsset(kai).mint(address(buyBackFund), _savedForBuyBackFund);
            }
        }
        if (allocateSeigniorageSalary > 0) {
            IKAIAsset(kai).mint(address(msg.sender), allocateSeigniorageSalary);
        }
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 _amount, address _to) external onlyAdmin {
        // do not allow to drain core tokens
        require(address(_token) != address(kai), "kai");
        require(address(_token) != address(bkai), "bkai");
        require(address(_token) != address(skai), "skai");
        _token.safeTransfer(_to, _amount);
    }

    function burnKAIFromBuyBackFund(uint256 _amount) external onlyAdmin {
        require(_amount > 0, "Treasury: cannot burn kai with zero amount");
        IKAIAsset(kai).burnFrom(address(buyBackFund), _amount);
        burnKAIAmount = burnKAIAmount.add(_amount);
    }

     /* ========== BOARDROOM CONTROLLING FUNCTIONS ========== */

    function boardroomSetLockUp(uint256 _withdrawLockupRounds, uint256 _rewardLockupRounds) external onlyAdmin {
        IBoardroom(boardroom).setLockUp(_withdrawLockupRounds, _rewardLockupRounds);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyAdmin {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(address _token, uint256 _amount, address _to) external onlyAdmin {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }
}
