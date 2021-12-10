pragma solidity ^0.5.16;

import "synthetix-2.50.4-ovm/contracts/Pausable.sol";
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "synthetix-2.50.4-ovm/contracts/interfaces/IERC20.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/Math.sol";
import "synthetix-2.50.4-ovm/contracts/SafeDecimalMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IPriceFeed.sol";
import "../interfaces/IBinaryOptionMarket.sol";
import "../interfaces/IBinaryOptionMarketManager.sol";
import "../interfaces/IBinaryOption.sol";
import "./DeciMath.sol";

contract ThalesAMM is Owned, Pausable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeDecimalMath for uint;

    DeciMath public deciMath;

    uint private constant ONE = 1e18;

    IPriceFeed public priceFeed;
    IERC20 public sUSD;
    address public manager;

    uint public capPerMarket = 1000 * 1e18;
    uint public impliedVolatility = 120 * 1e18;
    uint public min_spread = 1e16; //1%
    uint public max_spread = 5e16; //5%

    uint public minimalTimeLeftToMaturity = 2 hours;

    struct MarketSkew {
        uint longs;
        uint shorts;
    }

    enum Position {Long, Short}

    mapping(address => uint) public spentOnMarket;

    constructor(
        address _owner,
        IPriceFeed _priceFeed,
        IERC20 _sUSD,
        uint _capPerMarket,
        DeciMath _deciMath
    ) public Owned(_owner) {
        priceFeed = _priceFeed;
        sUSD = _sUSD;
        capPerMarket = _capPerMarket;
        deciMath = _deciMath;
    }

    function availableToBuyFromAMM(address market, Position position) public view returns (uint) {
        if (isMarketInAMMTrading(market)) {
            uint basePrice = price(market, position);
            // ignore extremes
            if (basePrice >= ONE.sub(1e16) || basePrice <= 1e16) {
                return 0;
            }
            uint balance = _balanceOfPositionOnMarket(market, position);
            uint buy_max_price = basePrice.mul(ONE.add(max_spread)).div(1e18);
            // ignore extremes
            if (buy_max_price >= ONE.sub(1e16) || buy_max_price <= 1e16) {
                return 0;
            }
            uint divider_max_price = ONE.sub(buy_max_price);
            uint additionalBufferFromSelling = balance.mul(buy_max_price).div(1e18);
            uint availableUntilCapSUSD = capPerMarket.sub(spentOnMarket[market]).add(additionalBufferFromSelling);

            return balance.add(availableUntilCapSUSD.div(divider_max_price).mul(1e18));
        } else {
            return 0;
        }
    }

    function buyFromAmmQuote(
        address market,
        Position position,
        uint amount
    ) public view returns (uint) {
        if (amount > availableToBuyFromAMM(market, position)) {
            return 0;
        }
        uint basePrice = price(market, position);
        return amount.mul(basePrice.mul(ONE.add(buyPriceImpact(market, position, amount))).div(1e18)).div(1e18);
    }

    function buyPriceImpact(
        address market,
        Position position,
        uint amount
    ) public view returns (uint) {
        if (amount > availableToBuyFromAMM(market, position)) {
            return 0;
        }
        (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
        uint balancePosition = position == Position.Long ? long.balanceOf(address(this)) : short.balanceOf(address(this));
        uint balanceOtherSide = position == Position.Long ? short.balanceOf(address(this)) : long.balanceOf(address(this));
        uint balancePositionAfter = balancePosition > amount ? balancePosition.sub(amount) : 0;
        uint balanceOtherSideAfter =
            balancePosition > amount ? balanceOtherSide : balanceOtherSide.add(amount.sub(balancePosition));
        uint pricePaid = _minimalBuyPrice(market, position).mul(amount).div(1e18);
        if (balancePositionAfter >= balanceOtherSideAfter) {
            //minimal price impact as it will balance the AMM exposure
            return min_spread;
        } else {
            uint basePriceOtherSide = price(market, position == Position.Long ? Position.Short : Position.Long);
            uint skew = balanceOtherSideAfter.sub(balancePositionAfter);
            uint maxPossibleSkew = capPerMarket.mul(1e18).div(basePriceOtherSide);
            return min_spread.add(max_spread.sub(min_spread).mul(skew.mul(1e18).div(maxPossibleSkew)).div(1e18));
        }
    }

    function availableToSellToAMM(address market, Position position) public view returns (uint) {
        if (isMarketInAMMTrading(market)) {
            uint basePrice = price(market, position);
            // ignore extremes
            if (basePrice >= ONE.sub(1e16) || basePrice <= 1e16) {
                return 0;
            }
            uint sell_max_price = basePrice.mul(ONE.sub(max_spread)).div(1e18);
            (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
            uint balanceOfTheOtherSide =
                position == Position.Long ? short.balanceOf(address(this)) : long.balanceOf(address(this));

            // can burn straight away balanceOfTheOtherSide
            uint willPay = balanceOfTheOtherSide.mul(sell_max_price).div(1e18);
            uint usdAvailable = capPerMarket.add(balanceOfTheOtherSide).sub(spentOnMarket[market]).sub(willPay);
            return usdAvailable.div(sell_max_price).mul(1e18).add(balanceOfTheOtherSide);
        } else return 0;
    }

    function sellToAmmQuote(
        address market,
        Position position,
        uint amount
    ) public view returns (uint) {
        if (amount > availableToSellToAMM(market, position)) {
            return 0;
        }
        uint basePrice = price(market, position);
        return amount.mul(basePrice.mul(ONE.sub(sellPriceImpact(market, position, amount))).div(1e18)).div(1e18);
    }

    function sellPriceImpact(
        address market,
        Position position,
        uint amount
    ) public view returns (uint) {
        if (amount > availableToSellToAMM(market, position)) {
            return 0;
        }
        (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
        uint balancePosition = position == Position.Long ? long.balanceOf(address(this)) : short.balanceOf(address(this));
        uint balanceOtherSide = position == Position.Long ? short.balanceOf(address(this)) : long.balanceOf(address(this));
        uint balancePositionAfter = balancePosition.add(amount);
        uint pricePaid = _minimalSellPrice(market, position).mul(amount).div(1e18);
        if (balancePositionAfter < balanceOtherSide) {
            //minimal price impact as it will balance the AMM exposure
            return min_spread;
        } else {
            uint basePrice = price(market, position);
            uint skew = balancePositionAfter.sub(balanceOtherSide);
            uint maxPossibleSkew = capPerMarket.mul(1e18).div(basePrice);
            return min_spread.add(max_spread.sub(min_spread).mul(skew.mul(1e18).div(maxPossibleSkew)).div(1e18));
        }
    }

    function price(address market, Position position) public view returns (uint) {
        if (isMarketInAMMTrading(market)) {
            // add price calculation
            IBinaryOptionMarket marketContract = IBinaryOptionMarket(market);
            (uint maturity, uint destructino) = marketContract.times();

            uint timeLeftToMaturity = maturity - block.timestamp;
            uint timeLeftToMaturityInDays = timeLeftToMaturity.mul(1e18).div(86400);
            uint oraclePrice = marketContract.oraclePrice();

            (bytes32 key, uint strikePrice, uint finalPrice) = marketContract.oracleDetails();

            if (position == Position.Long) {
                return calculateOdds(oraclePrice, strikePrice, timeLeftToMaturityInDays, impliedVolatility).div(1e2);
            } else {
                return
                    ONE.sub(calculateOdds(oraclePrice, strikePrice, timeLeftToMaturityInDays, impliedVolatility).div(1e2));
            }
        } else return 0;
    }

    function calculateOdds(
        uint price,
        uint strike,
        uint timeLeftInDays,
        uint volatility
    ) public view returns (uint) {
        uint vt = volatility.div(100).mul(sqrt(timeLeftInDays.div(365))).div(1e9);
        uint d1 = deciMath.ln(strike.mul(1e18).div(price), 99).mul(1e18).div(vt);
        uint y = ONE.mul(1e18).div(ONE.add(d1.mul(2316419).div(1e7)));
        uint d2 = d1.mul(d1).div(2).div(1e18);
        uint z = _expneg(d2).mul(3989423).div(1e7);

        uint y5 = deciMath.pow(y, 5 * 1e18).mul(1330274).div(1e6);
        uint y4 = deciMath.pow(y, 4 * 1e18).mul(1821256).div(1e6);
        uint y3 = deciMath.pow(y, 3 * 1e18).mul(1781478).div(1e6);
        uint y2 = deciMath.pow(y, 2 * 1e18).mul(356538).div(1e6);
        uint y1 = y.mul(3193815).div(1e7);
        uint x1 = y5.add(y3).add(y1).sub(y4).sub(y2);
        uint x = ONE.sub(z.mul(x1).div(1e18));
        uint result = ONE.mul(1e2).sub(x.mul(1e2));

        return result;
    }

    function isMarketInAMMTrading(address market) public view returns (bool) {
        if (IBinaryOptionMarketManager(manager).isActiveMarket(market)) {
            // add price calculation
            IBinaryOptionMarket marketContract = IBinaryOptionMarket(market);
            (uint maturity, uint destructino) = marketContract.times();

            uint timeLeftToMaturity = maturity - block.timestamp;
            return timeLeftToMaturity > minimalTimeLeftToMaturity;
        } else {
            return false;
        }
    }

    function canExerciseMaturedMarket(address market) public view returns (bool) {
        if (
            IBinaryOptionMarketManager(manager).isKnownMarket(market) &&
            (IBinaryOptionMarket(market).phase() == IBinaryOptionMarket.Phase.Maturity)
        ) {
            (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
            if ((long.balanceOf(address(this)) > 0) || (short.balanceOf(address(this)) > 0)) {
                return true;
            }
        }
        return false;
    }

    // write methods

    function buyFromAMM(
        address market,
        Position position,
        uint amount
    ) public nonReentrant notPaused {
        require(isMarketInAMMTrading(market), "Market is not in Trading phase");

        require(amount <= availableToBuyFromAMM(market, position), "Not enough liquidity.");

        uint sUSDPaid = buyFromAmmQuote(market, position, amount);
        require(sUSD.balanceOf(msg.sender) >= sUSDPaid, "You dont have enough sUSD.");
        require(sUSD.allowance(msg.sender, address(this)) >= sUSDPaid, "No allowance.");

        sUSD.transferFrom(msg.sender, address(this), sUSDPaid);

        uint availableInContract = _balanceOfPositionOnMarket(market, position);

        uint toMint = 0;
        if (availableInContract < amount) {
            toMint = amount.sub(availableInContract);
            require(sUSD.balanceOf(address(this)) >= toMint, "Not enough sUSD in contract.");
            IBinaryOptionMarket(market).mint(toMint);
        }

        (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
        IBinaryOption target = position == Position.Long ? long : short;

        IERC20(address(target)).transfer(msg.sender, amount);

        spentOnMarket[market] = spentOnMarket[market].add(toMint);

        if (spentOnMarket[market] <= sUSDPaid) {
            spentOnMarket[market] = 0;
        } else {
            spentOnMarket[market] = spentOnMarket[market].sub(sUSDPaid);
        }

        emit BoughtFromAmm(msg.sender, market, position, amount);
    }

    function sellToAMM(
        address market,
        Position position,
        uint amount
    ) public nonReentrant notPaused {
        require(isMarketInAMMTrading(market), "Market is not in Trading phase");

        require(amount <= availableToSellToAMM(market, position), "Cant buy that much");

        (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
        IBinaryOption target = position == Position.Long ? long : short;

        require(target.balanceOf(msg.sender) >= amount, "You dont have enough options.");
        require(IERC20(address(target)).allowance(msg.sender, address(this)) >= amount, "No allowance.");

        //transfer options first to have max burn available
        IERC20(address(target)).transferFrom(msg.sender, address(this), amount);
        uint sUSDFromBurning = IBinaryOptionMarket(market).getMaximumBurnable(address(this));
        if (sUSDFromBurning > 0) {
            IBinaryOptionMarket(market).burnOptionsMaximum();
        }

        uint pricePaid = sellToAmmQuote(market, position, amount);
        require(sUSD.balanceOf(address(this)) >= pricePaid, "Not enough sUSD in contract.");

        sUSD.transfer(msg.sender, pricePaid);

        spentOnMarket[market] = spentOnMarket[market].add(pricePaid);
        if (spentOnMarket[market] < sUSDFromBurning) {
            spentOnMarket[market] = 0;
        } else {
            spentOnMarket[market] = spentOnMarket[market].sub(sUSDFromBurning);
        }

        emit SoldToAMM(msg.sender, market, position, amount);
    }

    function exerciseMaturedMarket(address market) external {
        require(
            IBinaryOptionMarket(market).phase() == IBinaryOptionMarket.Phase.Maturity,
            "Market is not in Maturity phase"
        );
        require(IBinaryOptionMarketManager(manager).isKnownMarket(market), "Unknown market");
        require(canExerciseMaturedMarket(market), "No options to exercise");
        IBinaryOptionMarket(market).exerciseOptions();
    }

    // setters
    function setMinimalTimeLeftToMaturity(uint _minimalTimeLeftToMaturity) public onlyOwner {
        minimalTimeLeftToMaturity = _minimalTimeLeftToMaturity;
    }

    function setMinSpread(uint _spread) public onlyOwner {
        min_spread = _spread;
    }

    function setMaxSpread(uint _spread) public onlyOwner {
        max_spread = _spread;
    }

    function setImpliedVolatility(uint _impliedVolatility) public onlyOwner {
        impliedVolatility = _impliedVolatility;
    }

    function setCapPerMarket(uint _capPerMarket) public onlyOwner {
        capPerMarket = _capPerMarket;
    }

    function setPriceFeed(IPriceFeed _priceFeed) public onlyOwner {
        priceFeed = _priceFeed;
    }

    function setSUSD(IERC20 _sUSD) public onlyOwner {
        sUSD = _sUSD;
    }

    function setBinaryOptionsMarketManager(address _manager) public onlyOwner {
        if (address(_manager) != address(0)) {
            sUSD.approve(address(_manager), 0);
        }
        manager = _manager;
        sUSD.approve(manager, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
    }

    // Internal functions

    function _minimalBuyPrice(address market, Position position) internal view returns (uint) {
        return price(market, position).mul(ONE.add(min_spread)).div(1e18);
    }

    function _minimalSellPrice(address market, Position position) internal view returns (uint) {
        return price(market, position).mul(ONE.sub(min_spread)).div(1e18);
    }

    function _balanceOfPositionOnMarket(address market, Position position) internal view returns (uint) {
        (IBinaryOption long, IBinaryOption short) = IBinaryOptionMarket(market).options();
        uint balance = position == Position.Long ? long.balanceOf(address(this)) : short.balanceOf(address(this));
        return balance;
    }

    function _expneg(uint x) private view returns (uint result) {
        result = (1e18 * 1e18) / _expnegpow(x);
    }

    function _expnegpow(uint x) internal view returns (uint result) {
        uint e = 2718280000000000000;
        result = deciMath.pow(e, x);
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    //selfdestruct
    function selfDestruct(address payable account) external onlyOwner {
        sUSD.transfer(account, sUSD.balanceOf(address(this)));
        selfdestruct(account);
    }

    // events
    event SoldToAMM(address seller, address market, Position position, uint amount);
    event BoughtFromAmm(address buyer, address market, Position position, uint amount);
}
