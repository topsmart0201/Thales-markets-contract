// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Inheritance
import "../../interfaces/IParlayMarketsAMM.sol";
import "../../interfaces/ISportPositionalMarket.sol";
import "../../utils/proxy/solidity-0.8.0/ProxyOwned.sol";
import "../../utils/proxy/solidity-0.8.0/ProxyPausable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../../interfaces/ISportsAMMTiny.sol";
import "../../interfaces/IParlayPolicy.sol";

import "../../interfaces/ITherundownConsumer.sol";
import "../../interfaces/IGamesPlayerProps.sol";
import "../../interfaces/IGamesOddsObtainer.sol";
import "../../interfaces/ISportPositionalMarket.sol";

contract ParlayPolicy is Initializable, ProxyOwned, ProxyPausable {
    IParlayMarketsAMM public parlayMarketsAMM;
    ISportsAMMTiny public sportsAMM;
    address public consumer;
    mapping(uint => uint) public restrictedMarketsCount;
    // toBeRemoved:
    mapping(uint => bool) public isRestrictedToBeCombined;
    mapping(uint => mapping(uint => bool)) public restrictedTagCombination;
    mapping(bytes32 => mapping(uint => uint)) public restrictedTagComboCount;
    mapping(uint => mapping(uint => bool)) public restrictedTag1Combo;
    mapping(uint => uint) public maxPlayerPropsPerSport;
    mapping(uint => bool) public eligibleSportForSamePropsCombination;

    function initialize(address _owner, address _parlayMarketsAMM) external initializer {
        setOwner(_owner);
        parlayMarketsAMM = IParlayMarketsAMM(_parlayMarketsAMM);
        sportsAMM = ISportsAMMTiny(parlayMarketsAMM.sportsAmm());
        consumer = sportsAMM.theRundownConsumer();
    }

    // Check if two player props markets are eligible to be combined
    // If they are not the same player, but same prop
    // Or if they are the same player but different prop
    function areEligiblePropsMarkets(
        address _childMarket1,
        address _childMarket2,
        uint _tag1
    ) external view returns (bool samePlayerDifferentProp) {
        IGamesPlayerProps gamePlayerProps = IGamesPlayerProps(ITherundownConsumer(consumer).playerProps());
        if (
            eligibleSportForSamePropsCombination[_tag1] &&
            gamePlayerProps.playerIdPerChildMarket(_childMarket1) != gamePlayerProps.playerIdPerChildMarket(_childMarket2) &&
            gamePlayerProps.optionIdPerChildMarket(_childMarket1) == gamePlayerProps.optionIdPerChildMarket(_childMarket2)
        ) {
            samePlayerDifferentProp = true;
        }
    }

    function getSgpFeePerCombination(IParlayPolicy.SGPData memory params) external view returns (uint sgpFee) {
        sgpFee = parlayMarketsAMM.getSgpFeePerCombination(
            params.tag1,
            params.tag2_1,
            params.tag2_2,
            params.position1,
            params.position2
        );
    }

    function getMarketDefaultOdds(address _sportMarket, uint _position) external view returns (uint odd) {
        odd = sportsAMM.getMarketDefaultOdds(_sportMarket, false)[_position];
    }

    function getChildMarketTotalLine(address _sportMarket) external view returns (uint childTotalsLine) {
        if (ISportPositionalMarket(_sportMarket).isChild()) {
            childTotalsLine = ISportPositionalMarket(_sportMarket).parentMarket().optionsCount();
            if (childTotalsLine > 2) {
                childTotalsLine = uint(
                    IGamesOddsObtainer(ITherundownConsumer(consumer).oddsObtainer()).childMarketTotal(_sportMarket)
                );
            }
        }
    }

    function isTags1ComboRestricted(uint tag1, uint tag2) external view returns (bool isRestricted) {
        isRestricted = restrictedTag1Combo[tag1][tag2];
    }

    function isRestrictedComboEligible(
        uint tag1,
        uint tag2,
        uint tag1Count,
        uint tag2Count
    ) external view returns (bool eligible) {
        bytes32 tagHash = keccak256(abi.encode(tag1, tag2));
        eligible = true;
        uint restrictTag1 = restrictedTagComboCount[tagHash][tag1];
        uint restrictTag2 = restrictedTagComboCount[tagHash][tag2];
        if (restrictTag1 > 0 && restrictTag1 < tag1Count) {
            eligible = false;
        } else if (restrictTag2 > 0 && restrictTag2 < tag2Count) {
            eligible = false;
        }
    }

    function setMaxPlayerPropsPerSport(uint tag1, uint maxPlayerPropsGames) external onlyOwner {
        maxPlayerPropsPerSport[tag1] = maxPlayerPropsGames;
    }

    function setEligibleSportForSamePropsCombination(uint _tag1, bool _eligible) external onlyOwner {
        eligibleSportForSamePropsCombination[_tag1] = _eligible;
    }

    function setRestrictedTagCombos(
        uint tag1,
        uint tag2,
        uint tag1Count,
        uint tag2Count
    ) external onlyOwner {
        if (tag1Count > 0 || tag2Count > 0) {
            bytes32 tagHash = keccak256(abi.encode(tag1, tag2));
            restrictedTagCombination[tag1][tag2] = true;
            restrictedTagComboCount[tagHash][tag1] = tag1Count;
            restrictedTagComboCount[tagHash][tag2] = tag2Count;
            tagHash = keccak256(abi.encode(tag2, tag1));
            restrictedTagCombination[tag2][tag1] = true;
            restrictedTagComboCount[tagHash][tag1] = tag1Count;
            restrictedTagComboCount[tagHash][tag2] = tag2Count;
        }
    }

    function setRestrictedMarketsCountPerTag(uint tag, uint count) external onlyOwner {
        if (tag > 0) {
            restrictedMarketsCount[tag] = count;
        }
    }

    // function setRestrictedTagToBeCombined(uint tag, bool restricted) external onlyOwner {
    //     if (tag > 0) {
    //         isRestrictedToBeCombined[tag] = restricted;
    //     }
    // }

    function setRestrictedTag1Combo(
        uint _tag1,
        uint _tag2,
        bool _restricted
    ) external onlyOwner {
        restrictedTag1Combo[_tag1][_tag2] = _restricted;
        restrictedTag1Combo[_tag2][_tag1] = _restricted;
    }

    function setParlayMarketsAMM(address _parlayMarketsAMM) external onlyOwner {
        parlayMarketsAMM = IParlayMarketsAMM(_parlayMarketsAMM);
        sportsAMM = ISportsAMMTiny(parlayMarketsAMM.sportsAmm());
        consumer = sportsAMM.theRundownConsumer();
        emit SetParlayMarketsAMM(_parlayMarketsAMM);
    }

    modifier onlyParlayAMM() {
        _onlyParlayAMM();
        _;
    }

    function _onlyParlayAMM() internal view {
        require(msg.sender == address(parlayMarketsAMM), "Not ParlayAMM");
    }

    event SetParlayMarketsAMM(address _parlayMarketsAMM);
}
