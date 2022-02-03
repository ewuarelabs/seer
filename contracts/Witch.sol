// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.2/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.2/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.2/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import "@chainlink/contracts/src/v0.8/Denominations.sol";
import "./ILendingPool.sol";


contract Witch is Ownable {

    FeedRegistryInterface internal registry;
    /**
    @dev Stores a witch's prediction
    @param option long or short the token. 1 - Long and 0 - Short
    @param start When the prediction was made
    @param end 
    @param token The token whose price is being predicted
    @param price The predicted price of the token
    @param amount The predicted amount of the token
    **/
    struct prediction {
        uint256 option;
        uint start;
        uint end;
        address payable token;
        int256 price;
        uint256 amount;
    }
    /**
    @dev Stores a witch and a list of her predictions
    **/
    mapping(uint256 => prediction[]) public witchPredictions;
    /** 
    @dev Stores details about each follower and their stake
    @param _witch The witch a follower is following.
    @param ending The 
    @param contribution The amount contributed by a follower
    @param _stake percentage staked by a follower with respect to a witch
    @param profit How much profit has been made by a follower
    **/
    struct following {
        uint256 _witch;
        uint256 ending;
        uint256 contribution;
        uint80 _stake;
        uint256 profit;
    }
    mapping(address => following) public followers;

    address payable coven;

    struct witch {
        uint256 followerContribution;
        uint256 amountStaked;
        uint80 _stake;
        uint256 profit;
    }
    mapping(uint256 => witch) witches;
    uint256 public totalAmountStaked;
    uint256 public totalAmountContributed;

    struct predictionData {
        uint end;
        uint80 stake;
    }

    predictionData[] private activePredictions;

    constructor(address _registry){
        registry = FeedRegistryInterface(_registry);
        coven = payable(0x5180db8F5c931aaE63c74266b211F580155ecac8);
        pool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    }

    ILendingPool pool;

    /**
   * @dev Stakes an amount of underlying asset into a LendingPool
   * @param asset The address of the underlying asset to stake
   * @param amount The amount to be staked
   * @param onBehalfOf The address that will own the stake
   * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
   *   0 if the action is executed directly by the user, without any middle-man
   **/

    function stakePool(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) private {
        // pool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        pool.deposit(asset, amount, onBehalfOf, referralCode);
    }

    function predict(uint256 _witch, uint256 _option, uint _duration, address payable token, int256 price, uint256 amount) public returns (uint256){
        IERC721 witchContract = IERC721(coven);
        require(witchContract.ownerOf(_witch) == msg.sender, "Only owner can predict");
        require(_option == 1 | 0, "Invalid option");
        require(amount >= witches[_witch].followerContribution);

        prediction memory _prediction = prediction(_option, block.timestamp, block.timestamp + (_duration * 3600), token, price, amount);
        witchPredictions[_witch].push(_prediction);
        witches[_witch].amountStaked += amount;
        totalAmountStaked += amount;

        stakePool(token, amount, Ownable.owner(), 0);
        uint80 activeStake = stake(witches[_witch].amountStaked, totalAmountStaked);
        witches[_witch]._stake = activeStake;

        predictionData memory _active = predictionData (
            block.timestamp + (_duration * 3600), 
            activeStake
            );

        activePredictions.push(_active);
        return witchPredictions[_witch].length - 1;
    }

    function stake(uint256 _amount, uint256 _total) public pure returns(uint80) {
        uint80 _stake = uint80(100 * _amount/_total);
        return _stake;
    }

    function follow(uint256 _witch, uint256 _duration, uint256 _amount) public payable {
        require(_duration >= 7, "Follow duration must be up to 7 days");
        require(_amount == msg.value | followers[msg.sender].contribution);
        require(_amount > 0);
        require(followers[msg.sender]._witch == 0, "Can only follow 1 witch at a time");

        witches[_witch].followerContribution += _amount;
        uint256 _witchContribution = witches[_witch].followerContribution;

        following memory followDetails = following (
            _witch,
            block.timestamp + (_duration * 3600), 
            _amount,
            stake(_amount, _witchContribution),
            followers[msg.sender].profit
            );

        followers[msg.sender] = followDetails;
        
        totalAmountContributed += _amount;
    }

    function changeLeader(uint256 _witch, uint256 _duration) public {
        if (followers[msg.sender].ending < block.timestamp) {
            followers[msg.sender].profit = 0;
        } 
        
        uint256 previousLeader = followers[msg.sender]._witch;
        
        uint256 _amount = followers[msg.sender].contribution;

        witches[previousLeader].followerContribution -= _amount;

        totalAmountContributed -= _amount;

        follow(_witch, _duration, _amount);

    }
    
    function increaseStake(uint256 _duration, uint256 _amount) public payable {
        require(_duration >= 7, "Follow duration must be up to 7 days");
        require(followers[msg.sender]._witch != 0, "Can only increase stake on existing followership");

        uint256 _witch = followers[msg.sender]._witch;

        witches[_witch].followerContribution += _amount;
        uint256 _witchContribution = witches[_witch].followerContribution;
        
        followers[msg.sender].ending += (_duration * 3600);
        followers[msg.sender].contribution += _amount;
        followers[msg.sender]._stake += stake(followers[msg.sender].contribution, _witchContribution);

        totalAmountContributed += _amount;
    }

    function getLatestRoundData(address base, address quote) private view returns (uint80, uint) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = registry.latestRoundData(base, quote);

        return (roundID, timeStamp);
    }

    function getHistoricalPrice(address base, address quote, uint80 roundId) private view returns (int, uint) {
        (
            uint80 roundID, 
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = registry.getRoundData(base, quote, roundId);

        return (price, timeStamp);
    }

    function getPrice(uint predictTime, uint latestTime, uint80 latestRoundId, address base, address quote) private view returns(int) {
        require (latestTime > predictTime, "Can't take profit until deadline");

        uint time;
        int price;
        uint80 timeInterval = uint80(latestTime - predictTime);
        uint80 rounds = timeInterval/1300;
        uint80 predictedRoundId = latestRoundId - rounds;
        if (predictedRoundId < latestRoundId) {
            while (time < predictTime) {
                (
                    int _price,
                    uint _time
                ) = getHistoricalPrice(base, quote, predictedRoundId);
                
                if (_time > predictTime) {
                    price = (price + _price)/2;
                } else {
                    price = _price;
                    time = _time;
                }
                
                predictedRoundId += 1;
            }
        } else {
            (
                int _price,
                uint _time
            ) = getHistoricalPrice(base, quote, predictedRoundId);
            price = _price;
        }
        return price;
    }

    function takeProfit(uint256[] memory _index, uint80 _witch) public payable{
        IERC721 witchContract = IERC721(coven);
        require(witchContract.ownerOf(_witch) == msg.sender, "Only owner can take profit");

        prediction[] memory predictions = witchPredictions[_witch];
        uint256 _totalProfit;
        for (uint i=0; i< _index.length; i++) {
            (
                uint80 roundId,
                uint timeStamp
            ) = getLatestRoundData(predictions[i].token, Denominations.USD); 

            int price = getPrice(predictions[i].end, timeStamp, roundId, predictions[i].token, Denominations.USD);

            uint _option = predictions[i].option;

            if (_option == 1 && price > predictions[i].price) {

            } else if (_option == 0 && price < predictions[i].price) {

            }
        }
    }

    function expiredStake() internal returns(uint256) {
        uint256 _expiredStake;

        uint count;
        uint _length = activePredictions.length;

        while (count < _length) {
            if (activePredictions[count].end <= block.timestamp) {
                _expiredStake += activePredictions[count].stake;
                delete activePredictions[count];
                _length -= 1;
            } else {
                count += 1;
            }
        }

        return _expiredStake;
    }

    function releaseExpiredStake(address asset, address to) public onlyOwner returns (uint256) {
        // ILendingPool pool = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
        address _owner = Ownable.owner();
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(_owner);

        uint256 available = totalCollateralETH - totalDebtETH;
        uint256 expired = expiredStake();
        uint256 removeAmount = expired * available/100;

        return pool.withdraw(asset, removeAmount, to);
    }
    
}