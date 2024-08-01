// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title PROSPERA Vesting Contract
/// @notice This contract handles vesting functionality for the PROSPERA token
/// @custom:security-contact security@prosperadefi.com
contract PROSPERAVesting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    /// @notice Address of the PROSPERA contract
    address public prosperaContract;

    /// @notice Struct to define the vesting schedule
    /// @param startTime The start time of the vesting period
    /// @param endTime The end time of the vesting period
    /// @param active Whether the vesting schedule is active
    /// @param vestingType The type of vesting schedule (0 for marketing team, 1 for PROSPERA team)
    /// @param totalAmount The total amount of tokens to be vested
    /// @param releasedAmount The amount of tokens already released
    struct Vesting {
        uint256 startTime;
        uint256 endTime;
        bool active;
        uint8 vestingType;
        uint256 totalAmount;
        uint256 releasedAmount;
    }

    /// @notice Mapping of vesting schedules for addresses
    mapping(address user => Vesting vestingInfo) public vestingSchedules;

    // Events
    /// @notice Emitted when a wallet is added to the vesting schedule
    /// @param user The address of the user for whom the vesting schedule is added
    /// @param startTime The start time of the vesting period
    /// @param endTime The end time of the vesting period
    /// @param amount The total amount of tokens to be vested
    /// @param vestingType The type of vesting schedule
    event VestingAdded(address indexed user, uint256 startTime, uint256 endTime, uint256 amount, uint8 vestingType);

    /// @notice Emitted when vested tokens are released
    /// @param user The address of the user for whom tokens are released
    /// @param amount The amount of tokens released
    event VestingReleased(address indexed user, uint256 amount);

    /// @notice Emitted when the contract is initialized
    /// @param prosperaAddress The address of the PROSPERA contract
    event VestingInitialized(address indexed prosperaAddress);

    /// @notice Emitted when a vesting schedule is updated
    /// @param user The address of the user whose vesting schedule is updated
    /// @param active Whether the vesting schedule is active
    /// @param releasedAmount The total amount of tokens released so far
    event VestingUpdated(address indexed user, bool active, uint256 releasedAmount);

    /// @notice Emitted when a new vesting schedule is created for an account
    /// @param account The address of the account for which the vesting schedule is created
    /// @param vestingInfo The complete vesting schedule information
    event VestingScheduleCreated(address indexed account, Vesting vestingInfo);

    /// @notice Emitted when a vesting schedule is updated after releasing tokens
    /// @param account The address of the account whose vesting schedule is updated
    /// @param updatedVesting The updated vesting schedule information
    event VestingScheduleUpdated(address indexed account, Vesting updatedVesting);

    /// @notice Emitted when the PROSPERA contract address is updated
    /// @param oldProsperaContract The old address of the PROSPERA contract
    /// @param newProsperaContract The new address of the PROSPERA contract
    event ProsperaContractUpdated(address indexed oldProsperaContract, address indexed newProsperaContract);

    /// @notice Emitted when the PROSPERA contract is set
    /// @param prosperaContract The address of the PROSPERA contract
    event ProsperaContractSet(address indexed prosperaContract);

    /// @notice Emitted when the contract is initialized
    event VestingInitialized();

    // Errors
    /// @notice Error for vesting not being active
    error VestingNotActive();

    /// @notice Error for invalid vesting type
    error InvalidVestingType();

    /// @notice Error for caller not being the PROSPERA contract
    error CallerNotProsperaContract();

    /// @notice Error thrown when an invalid address is provided
    error InvalidAddress();

    /// @notice Error thrown when attempting to set an address that has already been set
    error AlreadySet();

    /// @notice Error thrown when the new address is the same as the current address
    error SameAddress();

    /// @notice Error for no tokens to release
    error NoTokensToRelease();

    /// @notice Error for invalid amount
    error InvalidAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @dev This function is called once by the deployer to set up the contract
    /// @custom:security-contact security@prosperadefi.com
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        emit VestingInitialized();
    }

    /// @notice Sets the address of the PROSPERA contract
    /// @dev This function can only be called by the contract owner and only once
    /// @param _prosperaContract The address of the PROSPERA contract
    /// @custom:throws InvalidAddress if the provided address is zero
    /// @custom:throws AlreadySet if the PROSPERA contract address has already been set
    function setProsperaContract(address _prosperaContract) external onlyOwner {
        if (_prosperaContract == address(0)) revert InvalidAddress();
        if (prosperaContract != address(0)) revert AlreadySet();
        prosperaContract = _prosperaContract;
        emit ProsperaContractSet(_prosperaContract);
    }

    /// @notice Updates the address of the PROSPERA contract
    /// @dev This function can only be called by the contract owner
    /// @param _newProsperaContract The new address of the PROSPERA contract
    /// @custom:throws InvalidAddress if the provided address is zero
    /// @custom:throws SameAddress if the new address is the same as the current address
    function updateProsperaContract(address _newProsperaContract) external onlyOwner {
        if (_newProsperaContract == address(0)) revert InvalidAddress();
        if (_newProsperaContract == prosperaContract) revert SameAddress();

        address oldProsperaContract = prosperaContract;
        prosperaContract = _newProsperaContract;
        emit ProsperaContractUpdated(oldProsperaContract, _newProsperaContract);
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @dev This function is left empty but is required by the UUPSUpgradeable contract
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Adds an address to the vesting schedule
    /// @dev Can only be called by the PROSPERA contract
    /// @param account The address to be added to the vesting schedule
    /// @param amount The amount of tokens to be vested
    /// @param vestingType The type of vesting schedule (0 for marketing team, 1 for PROSPERA team)
    /// @return True if the address was successfully added to the vesting schedule
    function addToVesting(address account, uint256 amount, uint8 vestingType) external onlyOwner nonReentrant returns (bool) {
        if (account == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();  

        uint256 startTime = block.timestamp;
        uint256 endTime;

        if (vestingType == 0) {
            endTime = startTime + 120 days; // 4 months for marketing team
        } else if (vestingType == 1) {
            endTime = startTime + 90 days; // 3 months for PROSPERA team
        } else {
            revert InvalidVestingType();
        }

        Vesting memory newVesting = Vesting({
            startTime: startTime,
            endTime: endTime,
            active: true,
            vestingType: vestingType,
            totalAmount: amount,
            releasedAmount: 0
        });

        vestingSchedules[account] = newVesting;

        emit VestingScheduleCreated(account, newVesting);
        emit VestingAdded(account, startTime, endTime, amount, vestingType);
        emit VestingUpdated(account, true, 0);

        return true;
    }

    /// @notice Calculates the vested amount for a given account
    /// @dev This is an internal function used by other functions in the contract
    /// @param account The address for which to calculate the vested amount
    /// @return The amount of tokens that have vested for the given account
    function _vestedAmount(address account) private view returns (uint256) {
        Vesting memory vesting = vestingSchedules[account];
        if (!vesting.active || block.timestamp < vesting.startTime) {
            return 0;
        } else if (block.timestamp >= vesting.endTime) {
            return vesting.totalAmount - vesting.releasedAmount;
        } else {
            return (vesting.totalAmount * (block.timestamp - vesting.startTime)) / (vesting.endTime - vesting.startTime) - vesting.releasedAmount;
        }
    }

    /// @notice Releases vested tokens for the given account
    /// @dev Can only be called by the PROSPERA contract
    /// @param account The address for which to release tokens
    /// @return The amount of tokens released
    function _releaseVestedTokens(address account) private returns (uint256) {
        if (account == address(0)) revert InvalidAddress();
        Vesting storage vesting = vestingSchedules[account];
        if (!vesting.active) revert VestingNotActive();

        uint256 amountToRelease = _vestedAmount(account);
        if (amountToRelease == 0) revert NoTokensToRelease();

        vesting.releasedAmount += amountToRelease;
        vesting.active = vesting.releasedAmount < vesting.totalAmount;

        emit VestingReleased(account, amountToRelease);
        emit VestingUpdated(account, vesting.active, vesting.releasedAmount);
        emit VestingScheduleUpdated(account, vesting);

        return amountToRelease;
    }

    /// @notice Public function to release vested tokens, can only be called by PROSPERA contract
    /// @param account The address for which to release tokens
    /// @return The amount of tokens released
    function releaseVestedTokens(address account) external returns (uint256) {
        if (msg.sender != prosperaContract) revert CallerNotProsperaContract();
        if (account == address(0)) revert InvalidAddress();
        return _releaseVestedTokens(account);
    }

    /// @notice Checks if a token transfer is allowed based on vesting schedule
    /// @param account The address to check
    /// @return True if the tokens are still vesting and cannot be transferred, false otherwise
    function isVestedTokenTransfer(address account) external view returns (bool) {
        Vesting memory vesting = vestingSchedules[account];
        return vesting.active && block.timestamp < vesting.endTime;
    }

    /// @notice Gets the vesting schedule for a given account
    /// @param account The address to check
    /// @return The vesting schedule details
    function getVestingSchedule(address account) external view returns (
        uint256,
        uint256,
        bool,
        uint8,
        uint256,
        uint256
    ) {
        Vesting memory vesting = vestingSchedules[account];
        return (
            vesting.startTime,
            vesting.endTime,
            vesting.active,
            vesting.vestingType,
            vesting.totalAmount,
            vesting.releasedAmount
        );
    }

    /// @notice Calculates the current vested amount for a given account
    /// @param account The address to check
    /// @return The current vested amount
    function getCurrentVestedAmount(address account) external view returns (uint256) {
        return _vestedAmount(account);
    }

    /// @notice Gets the current vesting status for a given account
    /// @param account The address to check
    /// @return isVesting True if the account has an active vesting schedule
    /// @return vestedAmount The amount of tokens currently vested
    /// @return totalAmount The total amount of tokens in the vesting schedule
    function getVestingStatus(address account) external view returns (bool isVesting, uint256 vestedAmount, uint256 totalAmount) {
        Vesting memory vesting = vestingSchedules[account];
        isVesting = vesting.active && block.timestamp < vesting.endTime;
        vestedAmount = _vestedAmount(account);
        totalAmount = vesting.totalAmount;
    }

    // Add a new function to check if a transfer is allowed
    function canTransfer(address account, uint256 amount) external view returns (bool) {
        Vesting memory vesting = vestingSchedules[account];
        if (!vesting.active) return true; // If no active vesting, transfer is allowed
        uint256 vestedAmount = _vestedAmount(account);
        return vesting.releasedAmount + amount <= vestedAmount;
    }
}