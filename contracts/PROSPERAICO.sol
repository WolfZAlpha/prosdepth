// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";

/// @title IPROSPERAICO
/// @notice Interface for the PROSPERA contract's ICO-related functionality
/// @dev This interface defines the functions that the PROSPERAICO contract calls on the PROSPERA contract
/// @custom:security-contact security@prosperadefi.com
interface IPROSPERAICO {
    /// @notice Records the completion of the ICO in the PROSPERA contract
    /// @dev This function is called by the PROSPERAICO contract when the ICO ends
    /// @param totalSold The total number of tokens sold during the ICO
    function recordIcoCompletion(uint256 totalSold) external;

    /// @notice Transfers ICO tokens to a buyer
    /// @param to The address of the token buyer
    /// @param amount The number of tokens to transfer
    /// @return success True if the transfer was successful
    function transferICOTokens(address to, uint256 amount) external returns (bool);
}

/// @title Chainlink Price Feed Interface
/// @notice Interface for the Chainlink price feed
/// @custom:security-contact security@prosperadefi.com
interface AggregatorV3Interface {
    /// @notice Get the latest round data
    /// @return roundId The round ID
    /// @return answer The price answer
    /// @return startedAt Timestamp of when the round started
    /// @return updatedAt Timestamp of when the round was updated
    /// @return answeredInRound The round ID of the round in which the answer was computed
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @title PROSPERA ICO Contract
/// @notice This contract handles ICO functionality for the PROSPERA token
/// @dev This contract manages the ICO process, including token purchases, tier management, and ETH/USD price feeds
/// @custom:security-contact security@prosperadefi.com
contract PROSPERAICO is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using Address for address payable;

    // State Variables
    /// @notice Address of the main PROSPERA contract
    address public prosperaContract;

    /// @notice Enum representing the different tiers of the ICO
    enum IcoTier { Tier1, Tier2, Tier3 }

    /// @notice Minimum buy amount in ETH (0.05 ETH)
    uint256 public constant MIN_BUY_ETH = 50000000000000000; // 0.05 ETH in wei

    /// @notice Maximum buy amount in ETH (170 ETH)
    uint256 public constant MAX_BUY_ETH = 170000000000000000000; // 170 ETH in wei

    /// @notice Total supply of tokens allocated for the ICO (15.375% of total supply)
    function ICO_SUPPLY() public pure virtual returns (uint256) {
        return 1e9 * 15375 / 100000; // 15.375% of total supply
    }

    /// @notice Number of tokens allocated for Tier 1 of the ICO
    function TIER1_TOKENS() public pure virtual returns (uint256) {
        return 8500000;
    }

    /// @notice Number of tokens allocated for Tier 2 of the ICO
    function TIER2_TOKENS() public pure virtual returns (uint256) {
        return 34500000;
    }

    /// @notice Number of tokens allocated for Tier 3 of the ICO
    function TIER3_TOKENS() public pure virtual returns (uint256) {
        return 110750000;
    }

    /// @notice Price per token in Tier 1 of the ICO (0.02 USD)
    uint256 public constant TIER1_PRICE_USD = 2; // $0.02 USD
    
    /// @notice Price per token in Tier 2 of the ICO (0.08 USD)
    uint256 public constant TIER2_PRICE_USD = 8; // $0.08 USD

    /// @notice Price per token in Tier 3 of the ICO (0.16 USD)
    uint256 public constant TIER3_PRICE_USD = 16; // $0.16 USD

    /// @notice Number of tokens sold in Tier 1 of the ICO
    uint256 public tier1Sold;

    /// @notice Number of tokens sold in Tier 2 of the ICO
    uint256 public tier2Sold;

    /// @notice Number of tokens sold in Tier 3 of the ICO
    uint256 public tier3Sold;

    /// @notice Flag indicating whether the ICO is currently active
    bool public icoActive;

    /// @notice Flag indicating whether the ICO is paused
    bool public isPaused;

    /// @notice Current tier of the ICO
    IcoTier public currentTier;

    /// @notice Wallet address for collecting ICO funds
    address public icoWallet;

    /// @notice Wallet address for collecting ICO taxes
    address public taxWallet;

    /// @notice Tax rate applied during the ICO (10%) - this is necessary due to IRS laws
    uint256 public constant ICO_TAX_RATE = 10;

    /// @notice Chainlink ETH/USD Price Feed interface
    AggregatorV3Interface public ethUsdPriceFeed;

    /// @notice Mapping to track the amount of ETH spent by each buyer in the ICO
    mapping(address buyer => uint256 amount) internal _icoBuys;

    // Events
    /// @notice Emitted when tokens are purchased during the ICO
    /// @param buyer The address of the token buyer
    /// @param amount The number of tokens purchased
    /// @param price The price paid for the tokens in ETH
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);

    /// @notice Emitted when the ICO is ended
    event IcoEnded();

    /// @notice Emitted when the ICO tier changes
    /// @param newTier The new ICO tier
    event IcoTierChanged(IcoTier indexed newTier);

    /// @notice Emitted when a buyer's total ICO purchase amount is updated
    /// @param buyer The address of the buyer
    /// @param newBuyAmount The new total purchase amount for the buyer
    event IcoBuyUpdated(address indexed buyer, uint256 newBuyAmount);

    /// @notice Emitted when the number of tokens sold in a tier is updated
    /// @param tier The ICO tier that was updated
    /// @param soldAmount The new total amount of tokens sold in the tier
    event TierSoldUpdated(IcoTier indexed tier, uint256 soldAmount);

    /// @notice Emitted when the current ICO tier is updated
    /// @param newTier The new current ICO tier
    event CurrentTierUpdated(IcoTier indexed newTier);

    /// @notice Emitted when the ICO contract is initialized
    /// @param prosperaContract The address of the main PROSPERA contract
    /// @param icoWallet The address of the ICO funds wallet
    /// @param taxWallet The address of the tax collection wallet
    event IcoInitialized(address indexed prosperaContract, address indexed icoWallet, address indexed taxWallet);

    /// @notice Emitted when the PROSPERA contract address is updated
    /// @param oldProsperaContract The old address of the PROSPERA contract
    /// @param newProsperaContract The new address of the PROSPERA contract
    event ProsperaContractUpdated(address indexed oldProsperaContract, address indexed newProsperaContract);

    /// @notice Emitted when ICO tokens are transferred to a buyer
    /// @param buyer The address of the token buyer
    /// @param amount The number of tokens transferred
    event IcoTokensTransferred(address indexed buyer, uint256 amount);

    /// @notice Emitted when the price feed address is updated
    /// @param newPriceFeed The address of the new price feed contract
    event PriceFeedUpdated(address indexed newPriceFeed);

    /// @notice Emitted when the ICO state is updated
    /// @param isActive Whether the ICO is active or not
    /// @param currentTier The current tier of the ICO
    event IcoStateUpdated(bool indexed isActive, IcoTier indexed currentTier);

    /// @notice Emitted when the PROSPERA contract is set
    /// @param prosperaContract The address of the PROSPERA contract
    event ProsperaContractSet(address indexed prosperaContract);

    /// @notice Emitted when the ICO wallet is set
    /// @param icoWallet The address of the ICO wallet
    event IcoWalletSet(address indexed icoWallet);

    /// @notice Emitted when the tax wallet is set
    /// @param taxWallet The address of the tax wallet
    event TaxWalletSet(address indexed taxWallet);

    /// @notice Emitted when the ETH/USD price feed is set
    /// @param ethUsdPriceFeed The address of the ETH/USD price feed
    event EthUsdPriceFeedSet(address indexed ethUsdPriceFeed);

    /// @notice Emitted when excess ETH is refunded to a buyer
    /// @param buyer The address of the buyer receiving the refund
    /// @param amount The amount of ETH refunded
    event ExcessEthRefunded(address indexed buyer, uint256 amount);

    // Custom Errors
    /// @notice Error thrown when trying to perform an action while the ICO is not active
    error IcoNotActive();

    /// @notice Error thrown when the purchase amount is below the minimum ICO buy limit
    error BelowMinIcoBuyLimit();

    /// @notice Error thrown when the purchase amount exceeds the maximum ICO buy limit
    error ExceedsMaxIcoBuyLimit();

    /// @notice Error thrown when an invalid ICO tier is referenced
    error InvalidIcoTier();

    /// @notice Error thrown when the amount of ETH sent does not match the expected amount
    error IncorrectETHAmountSent();

    /// @notice Error thrown when there are insufficient funds for the requested purchase
    /// @param required The amount of ETH required for the purchase
    /// @param provided The amount of ETH provided
    error InsufficientFundsForPurchase(uint256 required, uint256 provided);

    /// @notice Error thrown when an invalid address is provided
    error InvalidAddress();

    /// @notice Error thrown when an ETH transfer fails
    error EthTransferFailed();

    /// @notice Error thrown when a token transfer fails
    error TokenTransferFailed();

    /// @notice Error thrown when trying to perform a post-ICO action while the ICO is still active
    error IcoStillActive();

    /// @notice Error thrown when trying to withdraw ETH when there is no ETH to withdraw
    error NoEthToWithdraw();

    /// @notice Error thrown when trying to withdraw tokens when there are no tokens to withdraw
    error NoTokensToWithdraw();

    /// @notice Error thrown when an invalid amount is provided
    error InvalidAmount();

    /// @notice Error thrown when there is insufficient ICO supply
    error InsufficientICOSupply();

    /// @notice Error thrown when the new address is the same as the current address
    error SameAddress();

    /// @notice Error thrown when attempting to end an ICO that is not active
    error IcoNotActiveError();

    /// @notice Error thrown when attempting to end the ICO before all tokens are sold
    error NotAllTokensSold();

    /// @notice Error thrown when the attempt to record ICO completion in the PROSPERA contract fails
    error FailedToRecordIcoCompletion();

    /// @notice Error thrown when trying to set a value that has already been set
    error AlreadySet();

    /// @notice Error thrown when an invalid contract address is provided
    /// @param contractName The name of the contract with the invalid address
    error InvalidContractAddress(string contractName);

    /// @notice Error thrown when an unauthorized address tries to call a restricted function
    error UnauthorizedCaller();

    /// @notice Error thrown when trying to perform an action while the PROSPERA contract is not set
    error ProsperaContractNotSet();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @dev This function is called once by the deployer to set up the contract
    /// @param _icoWallet Address of the ICO wallet
    /// @param _taxWallet Address of the tax wallet
    function initialize(address _icoWallet, address _taxWallet) external initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _initialize(_icoWallet, _taxWallet);
    }

    /// @notice Internal function to initialize the contract
    /// @dev This function replicates the initialization logic
    /// @param _icoWallet Address of the ICO wallet
    /// @param _taxWallet Address of the tax wallet
    function _initialize(address _icoWallet, address _taxWallet) internal {
        if (_icoWallet == address(0) || _taxWallet == address(0)) revert InvalidAddress();
        icoWallet = _icoWallet;
        taxWallet = _taxWallet;
        icoActive = true;
        isPaused = false;
        currentTier = IcoTier.Tier1;

        // Initialize Chainlink ETH/USD Price Feed for Arbitrum
        ethUsdPriceFeed = AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612);

        emit IcoWalletSet(_icoWallet);
        emit TaxWalletSet(_taxWallet);
        emit EthUsdPriceFeedSet(address(ethUsdPriceFeed));
        emit IcoInitialized(address(0), _icoWallet, _taxWallet);
        emit IcoStateUpdated(true, IcoTier.Tier1);
    }

    /// @notice Sets the address of the PROSPERA contract
    /// @dev This function can only be called by the contract owner and only once
    /// @param _prosperaContract The address of the PROSPERA contract
    function setProsperaContract(address _prosperaContract) external onlyOwner {
        if (_prosperaContract == address(0)) revert InvalidAddress();
        if (prosperaContract != address(0)) revert AlreadySet();
        prosperaContract = _prosperaContract;
        emit ProsperaContractSet(_prosperaContract);
    }

    /// @notice Updates the address of the PROSPERA contract
    /// @dev This function can only be called by the contract owner
    /// @param _newProsperaContract The new address of the PROSPERA contract
    function updateProsperaContract(address _newProsperaContract) external onlyOwner {
        if (_newProsperaContract == address(0)) revert InvalidAddress();
        if (_newProsperaContract == prosperaContract) revert SameAddress();

        address oldProsperaContract = prosperaContract;
        prosperaContract = _newProsperaContract;

        emit ProsperaContractUpdated(oldProsperaContract, _newProsperaContract);
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev This function is required by the UUPSUpgradeable contract
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Checks if the ICO is active and not paused
    /// @dev This function is called by the PROSPERA contract to verify ICO status
    /// @return bool True if the ICO is active and not paused, false otherwise
    function isIcoActiveAndNotPaused() external view returns (bool) {
        return icoActive && !isPaused;
    }

    /// @notice Gets the current ETH/USD price from Chainlink
    /// @return price The current ETH price in USD (18 decimals)
    function getEthUsdPrice() public view returns (uint256 price) {
        (, int256 answer,,,) = ethUsdPriceFeed.latestRoundData();
        price = uint256(answer) * 1e10; // Convert to wei (18 decimals)
    }

    /// @notice Gets the minimum ICO buy in ETH
    /// @return The minimum ICO buy in ETH
    function getMinIcoBuy() public pure returns (uint256) {
        return MIN_BUY_ETH;
    }

    /// @notice Gets the maximum ICO buy in ETH
    /// @return The maximum ICO buy in ETH
    function getMaxIcoBuy() public pure returns (uint256) {
        return MAX_BUY_ETH;
    }

    /// @notice Purchases tokens during the ICO
    /// @dev This function handles the token purchase process, including tier management and ETH distribution
    /// @param tokenAmount The number of tokens to purchase
    /// @return tokensBought The number of tokens bought
    /// @return totalCost The total cost in ETH
    function buyTokens(uint256 tokenAmount) external payable nonReentrant virtual returns (uint256 tokensBought, uint256 totalCost) {
        if (prosperaContract == address(0)) revert ProsperaContractNotSet();
        if (!icoActive || isPaused || ERC20PausableUpgradeable(prosperaContract).paused()) revert IcoNotActive();
        if (tokenAmount == 0) revert InvalidAmount();

        uint256 ethValue = msg.value;
        uint256 currentBuyerAmount = getBuyerPurchaseAmount(msg.sender);

        if (ethValue < MIN_BUY_ETH) revert BelowMinIcoBuyLimit();
        if (currentBuyerAmount + ethValue > MAX_BUY_ETH) revert ExceedsMaxIcoBuyLimit();

        uint256 icoTaxAmount = ethValue * ICO_TAX_RATE / 100;
        uint256 remainingEth = ethValue - icoTaxAmount;

        uint256 currentTierPrice = getCurrentTierPriceETH();
        uint256 maxTokensPossible = (remainingEth * 1e18) / currentTierPrice;
        uint256 tokensToBuy = (tokenAmount < maxTokensPossible) ? tokenAmount : maxTokensPossible;

        (tokensBought, totalCost) = buyFromCurrentTier(tokensToBuy, remainingEth);
        if (tokensBought == 0) revert InsufficientFundsForPurchase({required: currentTierPrice, provided: remainingEth});

        _icoBuys[msg.sender] += ethValue;  // Update the total ETH spent, including tax

        // Transfer tokens to the buyer
        _transferICOTokens(msg.sender, tokensBought);

        // Transfer tax to tax wallet
        (bool success, ) = payable(taxWallet).call{value: icoTaxAmount}("");
        if (!success) revert EthTransferFailed();

        // Transfer remaining ETH to ICO wallet
        (success, ) = payable(icoWallet).call{value: remainingEth}("");
        if (!success) revert EthTransferFailed();

        emit IcoBuyUpdated(msg.sender, getBuyerPurchaseAmount(msg.sender));
        emit TokensPurchased(msg.sender, tokensBought, totalCost);
    }

    /// @notice Gets the current tier price in ETH
    /// @return The current tier price in ETH
    function getCurrentTierPriceETH() public view returns (uint256) {
        uint256 ethUsdPrice = getEthUsdPrice();
        uint256 tierPriceUSD;

        if (currentTier == IcoTier.Tier1) {
            tierPriceUSD = TIER1_PRICE_USD;
        } else if (currentTier == IcoTier.Tier2) {
            tierPriceUSD = TIER2_PRICE_USD;
        } else if (currentTier == IcoTier.Tier3) {
            tierPriceUSD = TIER3_PRICE_USD;
        } else {
            revert InvalidIcoTier();
        }

        // ethUsdPrice is in 8 decimal places, tierPriceUSD is in cents
        // We multiply by 1e8 to match ethUsdPrice precision and divide by 100 to convert cents to dollars
        uint256 priceInEth = (tierPriceUSD * 1e18) / (ethUsdPrice / 100);

        require(priceInEth > 0, "Invalid tier price calculation");

        return priceInEth;
    }

    /// @notice Buys tokens from the current ICO tier and handles transitions between tiers
    /// @dev This function manages the token purchase process across different tiers
    /// @param tokensToBuy The number of tokens attempting to buy
    /// @param availableEth The amount of ETH available for the purchase
    /// @return totalTokensBought The total number of tokens successfully purchased
    /// @return totalTierCost The total cost of the purchased tokens
    function buyFromCurrentTier(uint256 tokensToBuy, uint256 availableEth) internal virtual returns (uint256 totalTokensBought, uint256 totalTierCost) {
        while (tokensToBuy > 0 && availableEth > 0 && icoActive) {
            uint256 tierTokens;
            uint256 tierSold;
            uint256 tierPrice = getCurrentTierPriceETH();

            if (currentTier == IcoTier.Tier1) {
                tierTokens = TIER1_TOKENS();
                tierSold = tier1Sold;
            } else if (currentTier == IcoTier.Tier2) {
                tierTokens = TIER2_TOKENS();
                tierSold = tier2Sold;
            } else if (currentTier == IcoTier.Tier3) {
                tierTokens = TIER3_TOKENS();
                tierSold = tier3Sold;
            } else {
                revert InvalidIcoTier();
            }

            uint256 availableTokens = tierTokens - tierSold;
            uint256 tokensBought = (tokensToBuy < availableTokens) ? tokensToBuy : availableTokens;

            uint256 tierCost = tokensBought * tierPrice;

            if (tierCost > availableEth) {
                tokensBought = availableEth / tierPrice;
                tierCost = tokensBought * tierPrice;
            }

            totalTokensBought += tokensBought;
            totalTierCost += tierCost;
            tokensToBuy -= tokensBought;
            availableEth -= tierCost;

            // Update tier sold amounts and check for tier transitions
            if (currentTier == IcoTier.Tier1) {
                tier1Sold += tokensBought;
                emit TierSoldUpdated(IcoTier.Tier1, tier1Sold);
                if (tier1Sold >= TIER1_TOKENS()) updateIcoTier(IcoTier.Tier2);
            } else if (currentTier == IcoTier.Tier2) {
                tier2Sold += tokensBought;
                emit TierSoldUpdated(IcoTier.Tier2, tier2Sold);
                if (tier2Sold >= TIER2_TOKENS()) updateIcoTier(IcoTier.Tier3);
            } else if (currentTier == IcoTier.Tier3) {
                tier3Sold += tokensBought;
                emit TierSoldUpdated(IcoTier.Tier3, tier3Sold);
                if (tier3Sold >= TIER3_TOKENS()) endIco();
            }
        }

        if (availableEth > 0 && tokensToBuy == 0) {
            // Refund excess ETH
            (bool success, ) = payable(msg.sender).call{value: availableEth}("");
            if (!success) revert EthTransferFailed();
            emit ExcessEthRefunded(msg.sender, availableEth);
        }
    }

    /// @notice Updates the ICO tier
    /// @param newTier The new ICO tier to set
    function updateIcoTier(IcoTier newTier) private {
        currentTier = newTier;
        emit IcoTierChanged(newTier);
        emit CurrentTierUpdated(newTier);
    }

    /// @notice Gets the current ICO state
    /// @return _icoActive Whether the ICO is active
    /// @return _currentTier The current ICO tier
    /// @return _tier1Sold The number of tokens sold in Tier 1
    /// @return _tier2Sold The number of tokens sold in Tier 2
    /// @return _tier3Sold The number of tokens sold in Tier 3
    function getIcoState() external view returns (
        bool _icoActive,
        IcoTier _currentTier,
        uint256 _tier1Sold,
        uint256 _tier2Sold,
        uint256 _tier3Sold
    ) {
        _icoActive = icoActive;
        _currentTier = currentTier;
        _tier1Sold = tier1Sold;
        _tier2Sold = tier2Sold;
        _tier3Sold = tier3Sold;
    }

    /// @notice Gets the total amount of ETH a buyer has spent in the ICO
    /// @param buyer The address of the buyer
    /// @return amount The total amount spent by the buyer
    function getBuyerPurchaseAmount(address buyer) public view returns (uint256 amount) {
        amount = _icoBuys[buyer];
    }

    /// @notice Updates the Chainlink ETH/USD price feed address
    /// @dev Can only be called by the contract owner
    /// @param newPriceFeed The address of the new price feed contract
    function updatePriceFeed(address newPriceFeed) external onlyOwner {
        if (newPriceFeed == address(0)) revert InvalidAddress();
        ethUsdPriceFeed = AggregatorV3Interface(newPriceFeed);
        emit PriceFeedUpdated(newPriceFeed);
        emit EthUsdPriceFeedSet(newPriceFeed);
    }

    /// @notice Allows the owner to withdraw any remaining ETH after the ICO ends
    /// @dev Can only be called by the contract owner
    function withdrawRemainingETH() external onlyOwner {
        if (icoActive) revert IcoStillActive();
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoEthToWithdraw();
        (bool success, ) = payable(owner()).call{value: balance}("");
        if (!success) revert EthTransferFailed();
    }

    /// @notice Allows the owner to withdraw any remaining tokens after the ICO ends
    /// @dev Can only be called by the contract owner
    function withdrawRemainingTokens() external onlyOwner {
        if (icoActive) revert IcoStillActive();
        uint256 remainingTokens = IERC20(prosperaContract).balanceOf(address(this));
        if (remainingTokens == 0) revert NoTokensToWithdraw();
        bool success = IERC20(prosperaContract).transfer(owner(), remainingTokens);
        if (!success) revert TokenTransferFailed();
    }

    /// @notice Transfers ICO tokens to the buyer
    /// @dev This function is called internally during token purchases
    /// @param buyer The address of the token buyer
    /// @param amount The number of tokens to transfer
    function _transferICOTokens(address buyer, uint256 amount) internal virtual nonReentrant {
        if (buyer == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        if (IERC20(prosperaContract).balanceOf(address(this)) < amount) revert InsufficientICOSupply();

        // Call the new function on the PROSPERA contract
        bool success = IPROSPERAICO(prosperaContract).transferICOTokens(buyer, amount);
        if (!success) revert TokenTransferFailed();

        emit IcoTokensTransferred(buyer, amount);
    }

    /// @notice Ends the ICO
    /// @dev Can only be called by the contract owner or internally
    function endIco() public virtual {
        if (!icoActive) revert IcoNotActiveError();
        if (tier1Sold + tier2Sold + tier3Sold != ICO_SUPPLY()) revert NotAllTokensSold();
    
        // Add this check to allow both owner and internal calls
        if (msg.sender != owner() && msg.sender != address(this)) revert UnauthorizedCaller();

        icoActive = false;

        try IPROSPERAICO(prosperaContract).recordIcoCompletion(ICO_SUPPLY()) {
            emit IcoEnded();
            emit IcoStateUpdated(false, currentTier);
        } catch {
            revert FailedToRecordIcoCompletion();
        }
    }

    /// @notice Sets the PROSPERA contract address and transfers ICO tokens
    /// @dev This function should be called after initialization
    /// @param _prosperaContract The address of the PROSPERA contract
    function setProsperaContractAndTransferTokens(address _prosperaContract) external onlyOwner {
        if (_prosperaContract == address(0)) revert InvalidAddress();
        if (prosperaContract != address(0)) revert AlreadySet();
        prosperaContract = _prosperaContract;
        
        // Transfer ICO tokens to this contract
        IERC20(prosperaContract).transferFrom(msg.sender, address(this), ICO_SUPPLY());
        
        emit ProsperaContractSet(_prosperaContract);
    }

    /// @notice Sets the ICO state (active or inactive)
    /// @dev Can only be called by the contract owner
    /// @param _state The new state of the ICO (true for active, false for inactive)
    function setIcoState(bool _state) external onlyOwner {
        icoActive = _state;
        emit IcoStateUpdated(_state, currentTier);
    }

    /// @notice Updates the ICO and tax wallet addresses
    /// @dev Can only be called by the contract owner
    /// @param _newIcoWallet The new address for the ICO wallet
    /// @param _newTaxWallet The new address for the tax wallet
    function updateWallets(address _newIcoWallet, address _newTaxWallet) external onlyOwner {
        if (_newIcoWallet == address(0) || _newTaxWallet == address(0)) revert InvalidAddress();
        
        icoWallet = _newIcoWallet;
        taxWallet = _newTaxWallet;
        
        emit IcoWalletSet(_newIcoWallet);
        emit TaxWalletSet(_newTaxWallet);
    }

    /// @notice This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[50] private __gap;
}