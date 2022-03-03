pragma solidity ^0.8.0;

import "@openzeppelin/contracts-4.4.1/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-4.4.1/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import "../utils/proxy/solidity-0.8.0/ProxyReentrancyGuard.sol";
import "../utils/proxy/solidity-0.8.0/ProxyOwned.sol";
import "../interfaces/IExoticPositionalMarket.sol";
import "../interfaces/IExoticPositionalMarketManager.sol";
import "../interfaces/IThalesBonds.sol";

contract ThalesOracleCouncil is Initializable, ProxyOwned, PausableUpgradeable, ProxyReentrancyGuard {
    using SafeMath for uint;
    uint private constant COUNCIL_MAX_MEMBERS = 5;
    uint private constant VOTING_OPTIONS = 7;

    uint private constant ACCEPT_SLASH = 1;
    uint private constant ACCEPT_NO_SLASH = 2;
    uint private constant REFUSE_ON_POSITIONING = 3;
    uint private constant ACCEPT_RESULT = 4;
    uint private constant ACCEPT_RESET = 5;
    uint private constant REFUSE_MATURE = 6;

    uint private constant TEN_SUSD = 10 * 1e18;

    mapping(uint => address) public councilMemberAddress;
    mapping(address => uint) public councilMemberIndex;
    uint public councilMemberCount;
    IERC20 public paymentToken;
    IExoticPositionalMarketManager public marketManager;
    IThalesBonds public thalesBonds;
    uint public disputePrice;

    struct Dispute {
        address disputorAddress;
        string disputeString;
        uint disputeCode;
        uint disputeTimestamp;
        bool disputeInPositioningPhase;
    }

    mapping(address => mapping(uint => Dispute)) public dispute;
    mapping(address => uint) public marketTotalDisputes;
    mapping(address => uint) public marketLastClosedDispute;
    mapping(address => bool) public marketClosedForDisputes;

    mapping(address => mapping(uint => uint[])) public disputeVote;
    mapping(address => mapping(uint => uint[VOTING_OPTIONS])) public disputeVotesCount;
    mapping(address => mapping(uint => uint)) public disputeWinningPositionChoosen;
    mapping(address => address) public firstMemberThatChoseWinningPosition;

    function initialize(
        address _owner,
        uint _disputePrice,
        address _paymentToken,
        address _marketManager,
        address _thalesBonds
    ) public initializer {
        setOwner(_owner);
        initNonReentrant();
        disputePrice = _disputePrice;
        paymentToken = IERC20(_paymentToken);
        marketManager = IExoticPositionalMarketManager(_marketManager);
        thalesBonds = IThalesBonds(_thalesBonds);
    }

    /* ========== VIEWS ========== */

    function canMarketBeDisputed(address _market) public view returns (bool) {
        return !marketClosedForDisputes[_market] && IExoticPositionalMarket(_market).isMarketCreated();
    }

    function getMarketOpenDisputes(address _market) public view returns (uint) {
        return marketTotalDisputes[_market].sub(marketLastClosedDispute[_market]);
    }

    function getNextOpenDisputeIndex(address _market) public view returns (uint) {
        if (getMarketOpenDisputes(_market) > 0) {
            return (marketLastClosedDispute[_market].add(1));
        } else {
            return 0;
        }
    }

    function getMarketClosedDisputes(address _market) external view returns (uint) {
        return marketLastClosedDispute[_market];
    }

    function getNumberOfCouncilMembersForMarketDispute(address _market, uint _index) external view returns (uint) {
        // zero index does not count
        return disputeVote[_market][_index].length.sub(1);
    }

    function getVotesCountForMarketDispute(address _market, uint _index) public view returns (uint) {
        uint count = 0;
        // council members index starts from 1
        for (uint i = 1; i < disputeVote[_market][_index].length; i++) {
            count += disputeVote[_market][_index][i] > 0 ? 1 : 0;
        }
        return count;
    }

    function getVotesMissingForMarketDispute(address _market, uint _index) external view returns (uint) {
        return disputeVote[_market][_index].length.sub(1).sub(getVotesCountForMarketDispute(_market, _index));
    }

    function getDistpute(address _market, uint _index) external view returns (Dispute memory) {
        return dispute[_market][_index];
    }

    function getDistputeTimestamp(address _market, uint _index) external view returns (uint) {
        return dispute[_market][_index].disputeTimestamp;
    }

    function getDistputeAddressOfDisputor(address _market, uint _index) external view returns (address) {
        return dispute[_market][_index].disputorAddress;
    }

    function getDistputeString(address _market, uint _index) external view returns (string memory) {
        return dispute[_market][_index].disputeString;
    }

    function getDistputeCode(address _market, uint _index) external view returns (uint) {
        return dispute[_market][_index].disputeCode;
    }

    function getDistputeVotes(address _market, uint _index) external view returns (uint[] memory) {
        return disputeVote[_market][_index];
    }

    function isOracleCouncilMember(address _councilMember) public view returns (bool) {
        return (councilMemberIndex[_councilMember] > 0);
    }

    function setMarketManager(address _marketManager) external onlyOwner {
        require(_marketManager != address(0), "Invalid manager address");
        marketManager = IExoticPositionalMarketManager(_marketManager);
        emit NewMarketManager(_marketManager);
    }

    function addOracleCouncilMember(address _councilMember) external onlyOwner {
        require(_councilMember != address(0), "Invalid address. Add valid address");
        require(councilMemberCount < COUNCIL_MAX_MEMBERS, "Invalid address. Add valid address");
        require(!isOracleCouncilMember(_councilMember), "Already Oracle Council member");
        councilMemberCount = councilMemberCount.add(1);
        councilMemberAddress[councilMemberCount] = _councilMember;
        councilMemberIndex[_councilMember] = councilMemberCount;
        emit NewOracleCouncilMember(_councilMember, councilMemberCount);
    }

    function removeOracleCouncilMember(address _councilMember) external onlyOwner {
        require(isOracleCouncilMember(_councilMember), "Not an Oracle Council member");
        councilMemberAddress[councilMemberIndex[_councilMember]] = councilMemberAddress[councilMemberCount];
        councilMemberIndex[councilMemberAddress[councilMemberCount]] = councilMemberIndex[_councilMember];
        councilMemberCount = councilMemberCount.sub(1);
        emit OracleCouncilMemberRemoved(_councilMember, councilMemberCount);
    }

    function openDispute(address _market, string memory _disputeString) external whenNotPaused {
        require(IExoticPositionalMarket(_market).isMarketCreated(), "Market not created");
        require(!marketClosedForDisputes[_market], "Market is closed for disputes");
        require(
            paymentToken.balanceOf(msg.sender) >= marketManager.fixedBondAmount(),
            "Low token amount for disputing market"
        );
        require(
            paymentToken.allowance(msg.sender, address(thalesBonds)) >= disputePrice,
            "No allowance. Please approve ticket price allowance"
        );
        require(
            keccak256(abi.encode(_disputeString)) != keccak256(abi.encode("")),
            "Invalid market question (empty string)"
        );
        marketTotalDisputes[_market] = marketTotalDisputes[_market].add(1);
        dispute[_market][marketTotalDisputes[_market]].disputorAddress = msg.sender;
        dispute[_market][marketTotalDisputes[_market]].disputeString = _disputeString;
        dispute[_market][marketTotalDisputes[_market]].disputeTimestamp = block.timestamp;
        disputeVote[_market][marketTotalDisputes[_market]] = new uint[](councilMemberCount + 1);
        if (IExoticPositionalMarket(_market).canUsersPlacePosition()) {
            dispute[_market][marketTotalDisputes[_market]].disputeInPositioningPhase = true;
        }
        marketManager.disputeMarket(_market, msg.sender);
        emit NewDispute(_market, _disputeString, msg.sender);
    }

    function voteForDispute(
        address _market,
        uint _disputeIndex,
        uint _disputeCodeVote,
        uint _winningPosition
    ) external onlyCouncilMembers {
        require(!marketClosedForDisputes[_market], "Market is closed for disputes. No reason for voting");
        require(
            _disputeIndex > 0 && _disputeIndex > marketLastClosedDispute[_market],
            "Dispute non existent or already closed"
        );
        require(_disputeCodeVote <= VOTING_OPTIONS && _disputeCodeVote > 0, "Invalid dispute code");
        if (dispute[_market][marketTotalDisputes[_market]].disputeInPositioningPhase) {
            require(_disputeCodeVote < ACCEPT_RESULT, "Invalid voting code for dispute in positioning");
        } else {
            require(_disputeCodeVote >= ACCEPT_RESULT, "Invalid voting code for dispute in positioning");
        }
        if (_winningPosition > 0 && _disputeCodeVote == ACCEPT_RESULT) {
            if (disputeWinningPositionChoosen[_market][_disputeIndex] == 0) {
                disputeWinningPositionChoosen[_market][_disputeIndex] = _winningPosition;
                firstMemberThatChoseWinningPosition[_market] = msg.sender;
            } else if (
                disputeWinningPositionChoosen[_market][_disputeIndex] != 0 &&
                firstMemberThatChoseWinningPosition[_market] == msg.sender
            ) {
                disputeWinningPositionChoosen[_market][_disputeIndex] = _winningPosition;
            } else {
                require(
                    disputeWinningPositionChoosen[_market][_disputeIndex] == _winningPosition,
                    "Winning position mismatch. Use the initial winning position or vote for reset."
                );
            }
        }

        // check if already has voted for another option, and revert the vote
        if (
            disputeVote[_market][_disputeIndex][councilMemberIndex[msg.sender]] > 0 &&
            disputeVote[_market][_disputeIndex][councilMemberIndex[msg.sender]] != _disputeCodeVote
        ) {
            disputeVotesCount[_market][_disputeIndex][_disputeCodeVote] = disputeVotesCount[_market][_disputeIndex][
                _disputeCodeVote
            ]
                .sub(1);
        }

        // record the voting option
        disputeVote[_market][_disputeIndex][councilMemberIndex[msg.sender]] = _disputeCodeVote;
        disputeVotesCount[_market][_disputeIndex][_disputeCodeVote] = disputeVotesCount[_market][_disputeIndex][
            _disputeCodeVote
        ]
            .add(1);

        emit VotedAddedForDispute(_market, _disputeIndex, _disputeCodeVote);

        if (disputeVotesCount[_market][_disputeIndex][_disputeCodeVote] > (councilMemberCount.div(2))) {
            closeDispute(_market, _disputeIndex, _disputeCodeVote);
        }
    }

    function closeDispute(
        address _market,
        uint _disputeIndex,
        uint _decidedOption
    ) internal nonReentrant {
        if (_decidedOption == REFUSE_ON_POSITIONING || _decidedOption == REFUSE_MATURE) {
            // set dispute to false
            // send disputor BOND to SafeBox
            // marketManager.getMarketBondAmount(_market);
            thalesBonds.sendBondFromMarketToUser(_market, marketManager.safeBoxAddress(), marketManager.fixedBondAmount());
            marketLastClosedDispute[_market] = _disputeIndex;
            //if it is the last dispute
            if (_decidedOption == REFUSE_MATURE) {
                marketManager.setBackstopTimeout(_market);
            }
            if (marketLastClosedDispute[_market] == marketTotalDisputes[_market]) {
                marketManager.closeDispute(_market);
            }
            emit DisputeClosed(_market, _disputeIndex, _decidedOption);
        } else if (_decidedOption == ACCEPT_SLASH) {
            // 4 hours
            marketManager.setBackstopTimeout(_market);
            // close dispute flag
            marketManager.closeDispute(_market);
            // cancel market
            marketManager.cancelMarket(_market);
            marketClosedForDisputes[_market] = true;
            // send bond to disputor and safeBox
            thalesBonds.sendBondFromMarketToUser(_market, marketManager.safeBoxAddress(), TEN_SUSD);
            thalesBonds.sendBondFromMarketToUser(
                _market,
                dispute[_market][_disputeIndex].disputorAddress,
                (marketManager.fixedBondAmount().mul(2)).sub(TEN_SUSD)
            );

            marketLastClosedDispute[_market] = _disputeIndex;
            emit DisputeClosed(_market, _disputeIndex, _decidedOption);
        } else if (_decidedOption == ACCEPT_NO_SLASH) {
            // 4 hours
            marketManager.setBackstopTimeout(_market);
            // close dispute flag
            marketManager.closeDispute(_market);
            // close market(cancel market)
            marketManager.cancelMarket(_market);
            marketClosedForDisputes[_market] = true;
            // send bond to disputor and safeBox
            // thalesBonds.sendBondFromMarketToUser(_market, marketManager.safeBoxAddress(), TEN_SUSD);
            thalesBonds.sendBondFromMarketToUser(
                _market,
                IExoticPositionalMarket(_market).creatorAddress(),
                marketManager.fixedBondAmount()
            );
            thalesBonds.sendBondFromMarketToUser(
                _market,
                dispute[_market][_disputeIndex].disputorAddress,
                marketManager.fixedBondAmount().sub(TEN_SUSD)
            );
            // marketManager.sendRewardToDisputor(_market, dispute[_market][_disputeIndex].disputorAddress);

            marketLastClosedDispute[_market] = _disputeIndex;
            emit DisputeClosed(_market, _disputeIndex, _decidedOption);
        } else if (_decidedOption == ACCEPT_RESULT) {
            // close market
            // timer backstop
            marketManager.setBackstopTimeout(_market);
            // close dispute flag
            marketManager.closeDispute(_market);
            // set result
            marketManager.resolveMarket(_market, disputeWinningPositionChoosen[_market][_disputeIndex]);
            thalesBonds.sendBondFromMarketToUser(_market, marketManager.safeBoxAddress(), marketManager.fixedBondAmount());
            thalesBonds.sendBondFromMarketToUser(
                _market,
                dispute[_market][_disputeIndex].disputorAddress,
                marketManager.fixedBondAmount()
            );

            marketClosedForDisputes[_market] = true;
            marketLastClosedDispute[_market] = _disputeIndex;
            emit DisputeClosed(_market, _disputeIndex, _decidedOption);
        } else if (_decidedOption == ACCEPT_RESET) {
            // close dispute flag
            marketManager.closeDispute(_market);
            // reset result
            marketManager.resetMarket(_market);
            thalesBonds.sendBondFromMarketToUser(_market, marketManager.safeBoxAddress(), TEN_SUSD);
            thalesBonds.sendBondFromMarketToUser(
                _market,
                dispute[_market][_disputeIndex].disputorAddress,
                marketManager.fixedBondAmount().mul(2).sub(TEN_SUSD)
            );

            marketLastClosedDispute[_market] = _disputeIndex;
            emit DisputeClosed(_market, _disputeIndex, _decidedOption);
        } else {
            // (CANCEL)
            //4 hours backstop
            // marketManager.setBackstopTimeout(_market);
            // close market disputes
            // marketClosedForDisputes[_market] = true;
            // close market(cancel market)
            // marketManager.cancelMarket(_market);
        }
    }

    function closeMarketForDisputes(address _market) external onlyOwner {
        require(!marketClosedForDisputes[_market], "Market already closed for disputes");
        marketClosedForDisputes[_market] = true;
        emit MarketClosedForDisputes(_market, 0);
    }

    function reopenMarketForDisputes(address _market) external onlyOwner {
        require(marketClosedForDisputes[_market], "Market already open for disputes");
        marketClosedForDisputes[_market] = false;
        emit MarketReopenedForDisputes(_market);
    }

    modifier onlyCouncilMembers() {
        require(isOracleCouncilMember(msg.sender), "Issuer not a council member");
        _;
    }
    event NewOracleCouncilMember(address councilMember, uint councilMemberCount);
    event OracleCouncilMemberRemoved(address councilMember, uint councilMemberCount);
    event NewMarketManager(address marketManager);
    event NewDispute(address market, string disputeString, address disputorAccount);
    event VotedAddedForDispute(address market, uint disputeIndex, uint disputeCodeVote);
    event MarketClosedForDisputes(address market, uint disputeFinalCode);
    event MarketReopenedForDisputes(address market);
    event DisputeClosed(address market, uint disputeIndex, uint decidedOption);
}
