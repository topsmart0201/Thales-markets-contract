// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../ParlayMarket.sol";
import "./ParlayAMMLiquidityPool.sol";

contract ParlayAMMLiquidityPoolRound {
    /* ========== LIBRARIES ========== */
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ========== STATE VARIABLES ========== */

    ParlayAMMLiquidityPool public liquidityPool;
    IERC20Upgradeable public sUSD;

    uint public round;
    uint public roundStartTime;
    uint public roundEndTime;

    /* ========== CONSTRUCTOR ========== */

    bool public initialized;

    function initialize(
        address _liquidityPool,
        IERC20Upgradeable _sUSD,
        uint _round,
        uint _roundStartTime,
        uint _roundEndTime
    ) external {
        require(!initialized, "Already initialized");
        initialized = true;
        liquidityPool = ParlayAMMLiquidityPool(_liquidityPool);
        sUSD = _sUSD;
        round = _round;
        roundStartTime = _roundStartTime;
        roundEndTime = _roundEndTime;
        sUSD.approve(_liquidityPool, type(uint256).max);
    }

    function updateRoundTimes(uint _roundStartTime, uint _roundEndTime) external onlyLiquidityPool {
        roundStartTime = _roundStartTime;
        roundEndTime = _roundEndTime;
        emit RoundTimesUpdated(_roundStartTime, _roundEndTime);
    }

    function exerciseMarketReadyToExercised(address market) external onlyLiquidityPool {
        ParlayMarket parlay = ParlayMarket(market);
        (bool exercisable, ) = parlay.isParlayExercisable();
        if (exercisable) {
            // todo: exercise markets
            // IParlayAMM()
        }
    }

    modifier onlyLiquidityPool() {
        require(msg.sender == address(liquidityPool), "only the Pool manager may perform these methods");
        _;
    }

    event RoundTimesUpdated(uint _roundStartTime, uint _roundEndTime);
}
