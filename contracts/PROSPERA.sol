// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title Vesting Contract Interface
/// @notice Interface for the vesting contract used by PROSPERA
/// @custom:security-contact security@prosperadefi.com
interface IVestingContract {
    /// @notice Checks if a transfer involves vested tokens
    /// @param account Address to check for vested tokens
    /// @return isVested True if the transfer involves vested tokens, false otherwise
    function isVestedTokenTransfer(address account) external view returns (bool isVested);

    /// @notice Adds an account to the vesting schedule
    /// @param account The address to be added to the vesting schedule
    /// @param amount The amount of tokens to be vested
    /// @param vestingType The type of vesting schedule (0 for marketing team, 1 for PROSPERA team)
    /// @return success True if the address was successfully added to the vesting schedule
    function addToVesting(address account, uint256 amount, uint8 vestingType) external returns (bool success);

    /// @notice Releases vested tokens for a given account
    /// @param account The address for which to release tokens
    /// @return amount The amount of tokens released
    function releaseVestedTokens(address account) external returns (uint256 amount);

    /// @notice Checks if an account can transfer a specific amount of tokens
    /// @param account The address to check
    /// @param amount The amount of tokens to check for transfer ability
    /// @return True if the account can transfer the specified amount, false otherwise
    function canTransfer(address account, uint256 amount) external view returns (bool);
}

/// @title PROSPERAICO Interface
/// @notice Interface for the PROSPERAICO contract
/// @custom:security-contact security@prosperadefi.com
interface IPROSPERAICO {
    /// @notice Checks if the ICO is active and not paused
    /// @return bool True if the ICO is active and not paused, false otherwise
    function isIcoActiveAndNotPaused() external view returns (bool);

    /// @notice Records the completion of the ICO in the PROSPERA contract
    /// @dev This function is called by the PROSPERAICO contract when the ICO ends
    /// @param totalSold The total number of tokens sold during the ICO
    function recordIcoCompletion(uint256 totalSold) external;
}

/// @title PROSPERA Token Contract
/// @author Prospera Development Team
/// @notice This contract implements the PROSPERA token with various functionalities
/// @custom:security-contact security@prosperadefi.com
contract PROSPERA is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address payable;

    /// @notice Total supply of tokens
    uint256 private constant TOTAL_SUPPLY = 1e9;

    /// @notice Tokens allocated for staking rewards (10% of total supply)
    uint256 private constant STAKING_SUPPLY = TOTAL_SUPPLY * 10000 / 100000;

    /// @notice Tokens allocated for liquidity (20% of total supply)
    uint256 private constant LIQUIDITY_SUPPLY = TOTAL_SUPPLY * 20000 / 100000;

    /// @notice Tokens allocated for farming (10% of total supply)
    uint256 private constant FARMING_SUPPLY = TOTAL_SUPPLY * 10000 / 100000;

    /// @notice Tokens allocated for listing on exchanges (12% of total supply)
    uint256 private constant LISTING_SUPPLY = TOTAL_SUPPLY * 12000 / 100000;

    /// @notice Tokens allocated for reserves (5.025% of total supply)
    uint256 private constant RESERVE_SUPPLY = TOTAL_SUPPLY * 5025 / 100000;

    /// @notice Tokens allocated for marketing (5% of total supply)
    uint256 private constant MARKETING_SUPPLY = TOTAL_SUPPLY * 5000 / 100000;

    /// @notice Tokens allocated for team wallet (11% of total supply)
    uint256 private constant TEAM_SUPPLY = TOTAL_SUPPLY * 11000 / 100000;

    /// @notice Tokens allocated for dev wallet (11.6% of total supply)
    uint256 private constant DEV_SUPPLY = TOTAL_SUPPLY * 11600 / 100000;

    /// @notice Tokens allocated for the ICO (15.375% of total supply)
    uint256 private constant ICO_SUPPLY = TOTAL_SUPPLY * 15375 / 100000;

    /// @notice Indicates whether the ICO has been completed
    bool public icoCompleted;

    /// @notice Indicates whether the ICO is currently active
    bool public icoActive;

    /// @notice The total number of tokens in circulation
    uint256 public circulatingSupply;

    /// @notice Wallet address for tax collection
    address public taxWallet;

    /// @notice Wallet address for ICO funds
    address public icoWallet;

    /// @notice Wallet address for staking funds
    address public stakingWallet;

    /// @notice Address of the staking contract
    address public stakingContract;

    /// @notice Address of the vesting contract
    address public vestingContract;

    /// @notice Address of the ICO contract
    address public icoContract;

    /// @notice Address of the math contract
    address public mathContract;

    /// @notice Mapping of blacklisted addresses
    mapping(address user => bool isBlacklisted) private _blacklist;

    /// @dev Storage slot for staking wallet
    bytes32 private constant STAKING_WALLET_SLOT = bytes32(uint256(keccak256("stakingWalletSlot")) - 1);
    
    /// @dev Storage slot for liquidity wallet
    bytes32 private constant LIQUIDITY_WALLET_SLOT = bytes32(uint256(keccak256("liquidityWalletSlot")) - 1);
    
    /// @dev Storage slot for farming wallet
    bytes32 private constant FARMING_WALLET_SLOT = bytes32(uint256(keccak256("farmingWalletSlot")) - 1);
    
    /// @dev Storage slot for listing wallet
    bytes32 private constant LISTING_WALLET_SLOT = bytes32(uint256(keccak256("listingWalletSlot")) - 1);
    
    /// @dev Storage slot for reserve wallet
    bytes32 private constant RESERVE_WALLET_SLOT = bytes32(uint256(keccak256("reserveWalletSlot")) - 1);
    
    /// @dev Storage slot for marketing wallet
    bytes32 private constant MARKETING_WALLET_SLOT = bytes32(uint256(keccak256("marketingWalletSlot")) - 1);
    
    /// @dev Storage slot for team wallet
    bytes32 private constant TEAM_WALLET_SLOT = bytes32(uint256(keccak256("teamWalletSlot")) - 1);
    
    /// @dev Storage slot for dev wallet
    bytes32 private constant DEV_WALLET_SLOT = bytes32(uint256(keccak256("devWalletSlot")) - 1);

    /// @notice Emitted when an address is added to or removed from the blacklist
    /// @param user The address that was updated
    /// @param value The new blacklist status (true if blacklisted, false if removed from blacklist)
    event BlacklistUpdated(address indexed user, bool value);

    /// @notice Emitted when the contract is initialized
    /// @param deployer The address of the contract deployer
    event Initialized(address indexed deployer);

    /// @notice Emitted when a contract state is updated
    /// @param variable The name of the variable that was updated
    /// @param account The address associated with the update (if applicable)
    /// @param value The new value of the variable
    event StateUpdated(string variable, address indexed account, bool value);

    /// @notice Emitted when a wallet address is set
    /// @param walletType The type of wallet being set
    /// @param walletAddress The address of the wallet
    event WalletAddressSet(string indexed walletType, address indexed walletAddress);

    /// @notice Emitted when ETH is withdrawn from the contract
    /// @param recipient The address receiving the withdrawn ETH
    /// @param amount The amount of ETH withdrawn
    event EthWithdrawn(address indexed recipient, uint256 amount);

    /// @notice Emitted when the ICO is successfully completed
    /// @param totalSold The total number of tokens sold during the ICO
    event IcoCompleted(uint256 indexed totalSold);

    /// @notice Emitted when tokens are transferred
    /// @param from The address sending the tokens
    /// @param to The address receiving the tokens
    /// @param value The amount of tokens transferred
    event TokensTransferred(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when the ICO state is changed
    /// @param newState The new state of the ICO (true for active, false for inactive)
    event IcoStateChanged(bool indexed newState);

    /// @notice Emitted when the circulating supply is updated
    /// @param newSupply The new circulating supply amount
    event CirculatingSupplyUpdated(uint256 indexed newSupply);

    /// @notice Error thrown when an operation involves a blacklisted address
    /// @param account The address that is blacklisted
    error BlacklistedAddress(address account);

    /// @notice Error thrown when attempting to blacklist the zero address
    error BlacklistZeroAddress();

    /// @notice Error thrown when attempting to remove the zero address from the blacklist
    error RemoveFromBlacklistZeroAddress();

    /// @notice Error thrown when an operation requires more balance than available
    /// @param required The required balance
    /// @param available The available balance
    error InsufficientBalance(uint256 required, uint256 available);

    /// @notice Error thrown when attempting to withdraw ETH from a contract with no ETH balance
    error NoEthToWithdraw();

    /// @notice Error thrown when the fallback function receives data with a non-empty ETH transfer
    error FallbackFunctionOnlyAcceptsETH();

    /// @notice Error thrown when an invalid address is provided for an operation
    error InvalidAddress();

    /// @notice Error thrown when attempting to transfer vested tokens
    error VestedTokensCannotBeTransferred();

    /// @notice Error thrown when an invalid contract address is provided
    /// @param contractType The type of contract (e.g., "staking", "ICO", "vesting")
    error InvalidContractAddress(string contractType);

    /// @notice Error thrown when a function is called by an unauthorized address
    /// @param caller The address of the unauthorized caller
    /// @param requiredRole The role required to call the function
    error UnauthorizedCaller(address caller, string requiredRole);

    /// @notice Error thrown when the ICO completion is recorded incorrectly
    error InvalidIcoCompletion();

    /// @notice Error thrown when an operation is attempted after the ICO has completed
    error IcoAlreadyCompleted();

    /// @notice Error thrown when the contract balance changes unexpectedly after a transfer
    error UnexpectedBalanceChange();

    /// @notice Error thrown when trying to perform an ICO operation while the ICO is not active or is paused
    error IcoNotActive();

    /// @notice failed to add the account to the vesting schedule
    error FailedToAddAccountToVesting();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Struct for wallet initialization parameters
    /// @param deployerWallet Address of the contract deployer
    /// @param taxWallet Address for tax collection
    /// @param stakingWallet Address for staking funds
    /// @param icoWallet Address for ICO funds
    /// @param liquidityWallet Address for liquidity funds
    /// @param farmingWallet Address for farming funds
    /// @param listingWallet Address for listing funds
    /// @param reserveWallet Address for reserve funds
    /// @param marketingWallet Address for marketing funds
    /// @param teamWallet Address for team funds
    /// @param devWallet Address for development funds
    struct WalletParams {
        address deployerWallet;
        address taxWallet;
        address stakingWallet;
        address icoWallet;
        address liquidityWallet;
        address farmingWallet;
        address listingWallet;
        address reserveWallet;
        address marketingWallet;
        address teamWallet;
        address devWallet;
    }

    /// @notice Struct for contract initialization parameters
    /// @param vestingContract Address of the vesting contract
    /// @param icoContract Address of the ICO contract
    struct ContractParams {
        address vestingContract;
        address icoContract;
    }

    /// @notice Initializes the contract with the specified parameters
    /// @dev This function sets up the initial state of the contract, including setting up wallets and minting the total supply
    /// @param walletParams The wallet initialization parameters
    /// @param contractParams The contract initialization parameters
    /// @param _icoActive The initial state of the ICO
    function initialize(WalletParams calldata walletParams, ContractParams calldata contractParams, bool _icoActive) external initializer {
        __ERC20_init("PROSPERA", "PROS");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __Ownable_init(walletParams.deployerWallet);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _initializeWallets(walletParams);
        _initializeContracts(contractParams);
        icoActive = _icoActive;

        _mint(walletParams.stakingWallet, STAKING_SUPPLY);
        _mint(StorageSlot.getAddressSlot(LIQUIDITY_WALLET_SLOT).value, LIQUIDITY_SUPPLY);
        _mint(StorageSlot.getAddressSlot(FARMING_WALLET_SLOT).value, FARMING_SUPPLY);
        _mint(StorageSlot.getAddressSlot(LISTING_WALLET_SLOT).value, LISTING_SUPPLY);
        _mint(StorageSlot.getAddressSlot(RESERVE_WALLET_SLOT).value, RESERVE_SUPPLY);
        _mint(StorageSlot.getAddressSlot(MARKETING_WALLET_SLOT).value, MARKETING_SUPPLY);
        _mint(StorageSlot.getAddressSlot(TEAM_WALLET_SLOT).value, TEAM_SUPPLY);
        _mint(StorageSlot.getAddressSlot(DEV_WALLET_SLOT).value, DEV_SUPPLY);
        _mint(contractParams.icoContract, ICO_SUPPLY);

        emit Initialized(walletParams.deployerWallet);
        emit IcoStateChanged(_icoActive);
    }

    /// @notice Initializes wallet addresses
    /// @param params The wallet initialization parameters
    function _initializeWallets(WalletParams memory params) private {
        taxWallet = params.taxWallet;
        stakingWallet = params.stakingWallet;
        icoWallet = params.icoWallet;

        StorageSlot.getAddressSlot(STAKING_WALLET_SLOT).value = params.stakingWallet;
        StorageSlot.getAddressSlot(LIQUIDITY_WALLET_SLOT).value = params.liquidityWallet;
        StorageSlot.getAddressSlot(FARMING_WALLET_SLOT).value = params.farmingWallet;
        StorageSlot.getAddressSlot(LISTING_WALLET_SLOT).value = params.listingWallet;
        StorageSlot.getAddressSlot(RESERVE_WALLET_SLOT).value = params.reserveWallet;
        StorageSlot.getAddressSlot(MARKETING_WALLET_SLOT).value = params.marketingWallet;
        StorageSlot.getAddressSlot(TEAM_WALLET_SLOT).value = params.teamWallet;
        StorageSlot.getAddressSlot(DEV_WALLET_SLOT).value = params.devWallet;

        emit WalletAddressSet("Tax Wallet", taxWallet);
        emit WalletAddressSet("Staking Wallet", stakingWallet);
        emit WalletAddressSet("ICO Wallet", icoWallet);
        emit WalletAddressSet("Liquidity Wallet", params.liquidityWallet);
        emit WalletAddressSet("Farming Wallet", params.farmingWallet);
        emit WalletAddressSet("Listing Wallet", params.listingWallet);
        emit WalletAddressSet("Reserve Wallet", params.reserveWallet);
        emit WalletAddressSet("Marketing Wallet", params.marketingWallet);
        emit WalletAddressSet("Team Wallet", params.teamWallet);
        emit WalletAddressSet("Dev Wallet", params.devWallet);
    }

    /// @notice Initializes contract addresses
    /// @param params The contract initialization parameters
    function _initializeContracts(ContractParams memory params) private {
        vestingContract = params.vestingContract;
        icoContract = params.icoContract;

        emit WalletAddressSet("Vesting Contract", vestingContract);
        emit WalletAddressSet("ICO Contract", icoContract);
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev This function is required by the UUPSUpgradeable contract and can only be called by the owner
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Checks if the given address is the ICO contract
    function isIcoContract(address account) public view returns (bool isIco) {
        return account == icoContract;
    }

    /// @notice Sets the address of the staking contract
    /// @dev This function can only be called by the owner of the contract
    /// @param _stakingContract The address of the new staking contract
    function setStakingContract(address _stakingContract) external onlyOwner {
        if (_stakingContract == address(0)) revert InvalidContractAddress("staking");
        stakingContract = _stakingContract;
        emit WalletAddressSet("Staking Contract", stakingContract);
    }

    /// @notice Sets the address of the math contract
    /// @dev This function can only be called by the owner of the contract
    /// @param _mathContract The address of the new math contract
    function setMathContract(address _mathContract) external onlyOwner {
        if (_mathContract == address(0)) revert InvalidContractAddress("math");
        mathContract = _mathContract;
        emit WalletAddressSet("Math Contract", mathContract);
    }

    /// @notice Pauses all token transfers
    /// @dev This function can only be called by the owner of the contract
    function pause() external onlyOwner {
        _pause();
        emit StateUpdated("paused", address(0), true);
    }

    /// @notice Unpauses all token transfers
    /// @dev This function can only be called by the owner of the contract
    function unpause() external onlyOwner {
        _unpause();
        emit StateUpdated("paused", address(0), false);
    }

    /// @notice Adds an address to the blacklist
    /// @dev This function can only be called by the owner of the contract
    /// @param account The address to be blacklisted
    function addToBlacklist(address account) external onlyOwner {
        if (account == address(0)) revert BlacklistZeroAddress();
        _blacklist[account] = true;
        emit BlacklistUpdated(account, true);
        emit StateUpdated("blacklist", account, true);
    }

    /// @notice Removes an address from the blacklist
    /// @dev This function can only be called by the owner of the contract
    /// @param account The address to be removed from the blacklist
    function removeFromBlacklist(address account) external onlyOwner {
        if (account == address(0)) revert RemoveFromBlacklistZeroAddress();
        _blacklist[account] = false;
        emit BlacklistUpdated(account, false);
        emit StateUpdated("blacklist", account, false);
    }

    /// @notice Records the final state of the ICO and performs necessary actions
    /// @dev This function can only be called by the ICO contract
    /// @param totalSold The total number of tokens sold in the ICO
    function recordIcoCompletion(uint256 totalSold) external virtual {
        if (msg.sender != icoContract) revert UnauthorizedCaller(msg.sender, "ICO Contract");
        if (totalSold > ICO_SUPPLY) revert InvalidIcoCompletion();
        if (icoCompleted) revert IcoAlreadyCompleted();

        icoCompleted = true;
        icoActive = false;
        circulatingSupply += totalSold;

        // Handle unsold tokens if any
        if (totalSold < ICO_SUPPLY) {
            uint256 unsoldTokens = ICO_SUPPLY - totalSold;
            _burn(icoContract, unsoldTokens);
        }

        emit IcoCompleted(totalSold);
        emit CirculatingSupplyUpdated(circulatingSupply);
        emit IcoStateChanged(false);
    }

    /// @notice Withdraws all ETH from the contract to the owner's address
    /// @dev This function can only be called by the contract owner and is protected against reentrancy attacks
    function withdrawETH() external onlyOwner nonReentrant {
        address payable ownerPayable = payable(owner());
        uint256 balance = address(this).balance;
    
        if (balance == 0) revert NoEthToWithdraw();
    
        _safeTransferETH(ownerPayable, balance);
    
        emit EthWithdrawn(ownerPayable, balance);
    }

    /// @notice Fallback function to receive ETH
    receive() external payable {}

    /// @notice Fallback function to handle unexpected calls
    fallback() external payable {
        if (msg.data.length != 0) revert FallbackFunctionOnlyAcceptsETH();
    }

    /// @notice Safely transfers ETH to an address
    /// @dev Uses OpenZeppelin's Address.sendValue for safer ETH transfers
    /// @param recipientAddress The address to receive the ETH
    /// @param amount The amount of ETH to transfer
    function _safeTransferETH(address recipientAddress, uint256 amount) private nonReentrant {
        if (address(this).balance < amount) revert InsufficientBalance(amount, address(this).balance);

        uint256 previousBalance = address(this).balance;

        payable(recipientAddress).sendValue(amount);

        uint256 expectedMinBalance = previousBalance - amount;
        uint256 tolerance = 1 wei;
        if (address(this).balance < expectedMinBalance || address(this).balance > expectedMinBalance + tolerance) {
            revert UnexpectedBalanceChange();
        }
    }

    /// @notice Updates the internal state during transfers
    /// @dev Overrides the _update function from ERC20Upgradeable and ERC20PausableUpgradeable
    /// @param from The address sending the tokens
    /// @param to The address receiving the tokens
    /// @param value The amount of tokens being transferred
    function _update(address from, address to, uint256 value) internal override(ERC20Upgradeable, ERC20PausableUpgradeable) {
        if (!isIcoContract(from)) {
            if (_blacklist[from]) revert BlacklistedAddress(from);
            if (_blacklist[to]) revert BlacklistedAddress(to);

            if (vestingContract != address(0)) {
                bool isVested = IVestingContract(vestingContract).isVestedTokenTransfer(from);
                if (isVested) {
                    bool canTransfer = IVestingContract(vestingContract).canTransfer(from, value);
                    if (!canTransfer) revert VestedTokensCannotBeTransferred();
                }
            }
        }   

        super._update(from, to, value);
        emit TokensTransferred(from, to, value);
    }

    /// @notice Adds an account to the vesting schedule
    /// @dev This function can only be called by the contract owner
    /// @param account The address to be added to the vesting schedule
    /// @param amount The amount of tokens to be vested
    /// @param vestingType The type of vesting schedule (0 for marketing team, 1 for PROSPERA team)
    /// @return success True if the account was successfully added to the vesting schedule
    function addAccountToVesting(address account, uint256 amount, uint8 vestingType) external onlyOwner returns (bool success) {
        if (vestingContract == address(0)) revert InvalidContractAddress("vesting");
        success = IVestingContract(vestingContract).addToVesting(account, amount, vestingType);
        if (!success) revert FailedToAddAccountToVesting();
        return success;
    }

    /// @notice Releases vested tokens for a given account
    /// @param account The address for which to release tokens
    /// @return amount The amount of tokens released
    function releaseVestedTokensForAccount(address account) external returns (uint256 amount) {
        if (vestingContract == address(0)) revert InvalidContractAddress("vesting");
        amount = IVestingContract(vestingContract).releaseVestedTokens(account);
        _transfer(address(this), account, amount);
        emit TokensTransferred(address(this), account, amount);
        return amount;
    }

    /// @notice Transfers ICO tokens to a buyer
    /// @dev This function can only be called by the ICO contract
    /// @param to The address of the token buyer
    /// @param amount The number of tokens to transfer
    /// @return success True if the transfer was successful
    function transferICOTokens(address to, uint256 amount) external returns (bool success) {
        if (msg.sender != icoContract) revert UnauthorizedCaller(msg.sender, "ICO Contract");
        _transfer(address(this), to, amount);
        return true;
    }

    /// @notice Override the decimals function to return 0
    /// @return The number of decimals for the token (always 0 for PROSPERA)
    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    /// @notice Updates the ICO contract address
    /// @dev This function can only be called by the contract owner
    /// @param _newIcoContract The address of the new ICO contract
    function updateIcoContract(address _newIcoContract) external onlyOwner {
        if (_newIcoContract == address(0)) revert InvalidAddress();
        icoContract = _newIcoContract;
        emit WalletAddressSet("ICO Contract", icoContract);
    }

    /// @notice Sets the ICO state (active or inactive)
    /// @dev This function can only be called by the contract owner
    /// @param _state The new state of the ICO (true for active, false for inactive)
    function setIcoState(bool _state) external onlyOwner {
        icoActive = _state;
        emit IcoStateChanged(_state);
    }
}