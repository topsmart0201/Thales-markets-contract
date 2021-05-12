pragma solidity >=0.4.24;

import "../interfaces/IBinaryOptionMarket.sol";

// https://docs.synthetix.io/contracts/source/interfaces/ibinaryoptionmarketmanager
interface IBinaryOptionMarketManager {
    /* ========== VIEWS / VARIABLES ========== */

    function fees() external view returns (uint poolFee, uint creatorFee);

    function durations()
        external
        view
        returns (
            uint maxOraclePriceAge,
            uint expiryDuration,
            uint maxTimeToMaturity
        );

    function creatorLimits() external view returns (uint capitalRequirement);

    function marketCreationEnabled() external view returns (bool);

    function totalDeposited() external view returns (uint);

    function numActiveMarkets() external view returns (uint);

    function activeMarkets(uint index, uint pageSize) external view returns (address[] memory);

    function numMaturedMarkets() external view returns (uint);

    function maturedMarkets(uint index, uint pageSize) external view returns (address[] memory);

    /* ========== MUTATIVE FUNCTIONS ========== */

    function createMarket(
        bytes32 oracleKey,
        uint strikePrice,
        uint calldata maturity,
        uint calldata initialMint // initial sUSD to mint options for
    ) external returns (IBinaryOptionMarket);

    function resolveMarket(address market) external;

    function expireMarkets(address[] calldata market) external;
}
