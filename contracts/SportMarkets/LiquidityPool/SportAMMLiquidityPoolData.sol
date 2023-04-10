// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Inheritance
import "./SportAMMLiquidityPool.sol";
import "../../utils/proxy/solidity-0.8.0/ProxyOwned.sol";
import "../../utils/proxy/solidity-0.8.0/ProxyPausable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SportAMMLiquidityPoolData is Initializable, ProxyOwned, ProxyPausable {
    struct LiquidityPoolData {
        bool started;
        uint maxAllowedDeposit;
        uint round;
        uint totalDeposited;
        uint minDepositAmount;
        uint maxAllowedUsers;
        uint usersCurrentlyInPool;
        bool canCloseCurrentRound;
        bool paused;
        uint roundLength;
        uint stakedThalesMultiplier;
        uint allocationCurrentRound;
        uint lifetimePnl;
        uint roundEndTime;
    }

    struct UserLiquidityPoolData {
        uint balanceCurrentRound;
        uint balanceNextRound;
        bool withdrawalRequested;
        uint maxDeposit;
        uint availableToDeposit;
        uint stakedThales;
        uint neededStakedThalesToWithdraw;
    }

    function initialize(address _owner) external initializer {
        setOwner(_owner);
    }

    /// @notice getLiquidityPoolData returns liquidity pool data
    /// @param liquidityPool SportAMMLiquidityPool
    /// @return LiquidityPoolData
    function getLiquidityPoolData(SportAMMLiquidityPool liquidityPool) external view returns (LiquidityPoolData memory) {
        uint round = liquidityPool.round();

        return
            LiquidityPoolData(
                liquidityPool.started(),
                liquidityPool.maxAllowedDeposit(),
                round,
                liquidityPool.totalDeposited(),
                liquidityPool.minDepositAmount(),
                liquidityPool.maxAllowedUsers(),
                liquidityPool.usersCurrentlyInPool(),
                liquidityPool.canCloseCurrentRound(),
                liquidityPool.paused(),
                liquidityPool.roundLength(),
                liquidityPool.stakedThalesMultiplier(),
                liquidityPool.allocationPerRound(round),
                liquidityPool.cumulativeProfitAndLoss(round > 0 ? round - 1 : 0),
                liquidityPool.getRoundEndTime(round)
            );
    }

    /// @notice getUserLiquidityPoolData returns user liquidity pool data
    /// @param liquidityPool SportAMMLiquidityPool
    /// @param user address of the user
    /// @return UserLiquidityPoolData
    function getUserLiquidityPoolData(SportAMMLiquidityPool liquidityPool, address user)
        external
        view
        returns (UserLiquidityPoolData memory)
    {
        uint round = liquidityPool.round();
        (uint maxDepositForUser, uint availableToDepositForUser, uint stakedThalesForUser) = liquidityPool
            .getMaxAvailableDepositForUser(user);

        return
            UserLiquidityPoolData(
                liquidityPool.balancesPerRound(round, user),
                liquidityPool.balancesPerRound(round + 1, user),
                liquidityPool.withdrawalRequested(user),
                maxDepositForUser,
                availableToDepositForUser,
                stakedThalesForUser,
                liquidityPool.getNeededStakedThalesToWithdrawForUser(user)
            );
    }
}
