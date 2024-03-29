// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// external
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// internal
import "../utils/proxy/solidity-0.8.0/ProxyOwned.sol";
import "../utils/proxy/solidity-0.8.0/ProxyPausable.sol";

import "../interfaces/IAddressManager.sol";

/// @title An address manager where all common addresses are stored
contract AddressManager is Initializable, ProxyOwned, ProxyPausable {
    address public safeBox;

    address public referrals;

    address public stakingThales;

    address public multiCollateralOnOffRamp;

    address public pyth;

    address public speedMarketsAMM;

    mapping(string => address) public addressBook;

    function initialize(
        address _owner,
        address _safeBox,
        address _referrals,
        address _stakingThales,
        address _multiCollateralOnOffRamp,
        address _pyth,
        address _speedMarketsAMM
    ) external initializer {
        setOwner(_owner);
        safeBox = _safeBox;
        referrals = _referrals;
        stakingThales = _stakingThales;
        multiCollateralOnOffRamp = _multiCollateralOnOffRamp;
        pyth = _pyth;
        speedMarketsAMM = _speedMarketsAMM;
    }

    //////////////////getters/////////////////

    /// @notice get all addresses
    function getAddresses() external view returns (IAddressManager.Addresses memory) {
        IAddressManager.Addresses memory allAddresses;

        allAddresses.safeBox = safeBox;
        allAddresses.referrals = referrals;
        allAddresses.stakingThales = stakingThales;
        allAddresses.multiCollateralOnOffRamp = multiCollateralOnOffRamp;
        allAddresses.pyth = pyth;
        allAddresses.speedMarketsAMM = speedMarketsAMM;

        return allAddresses;
    }

    /// @notice Get all addresses from the address book based on the contract names
    /// @param _contractNames array of contract names
    /// @return contracts array of addresses
    function getAddresses(string[] calldata _contractNames) external view returns (address[] memory contracts) {
        contracts = new address[](_contractNames.length);
        for (uint i = 0; i < _contractNames.length; i++) {
            if (addressBook[_contractNames[i]] == address(0)) revert InvalidAddressForContractName(_contractNames[i]);
            contracts[i] = addressBook[_contractNames[i]];
        }
    }

    /// @notice Get address from the addressBook based on the contract name
    /// @param _contractName name of the contract
    /// @return contract_ the address of the contract
    function getAddress(string calldata _contractName) external view returns (address contract_) {
        if (addressBook[_contractName] == address(0)) revert InvalidAddressForContractName(_contractName);
        contract_ = addressBook[_contractName];
    }

    /// @notice Check if a contract name has been assigned with an address
    /// @param _contractName name of the contract
    /// @return contractExists returns true if the contract exists or false if the address is set to ZERO address
    function checkIfContractExists(string calldata _contractName) external view returns (bool contractExists) {
        contractExists = addressBook[_contractName] != address(0);
    }

    //////////////////setters/////////////////

    /// @notice set corresponding addresses
    function setAddresses(
        address _safeBox,
        address _referrals,
        address _stakingThales,
        address _multiCollateralOnOffRamp,
        address _pyth,
        address _speedMarketsAMM
    ) external onlyOwner {
        safeBox = _safeBox;
        referrals = _referrals;
        stakingThales = _stakingThales;
        multiCollateralOnOffRamp = _multiCollateralOnOffRamp;
        pyth = _pyth;
        speedMarketsAMM = _speedMarketsAMM;
        emit SetAddresses(_safeBox, _referrals, _stakingThales, _multiCollateralOnOffRamp, _pyth, _speedMarketsAMM);
    }

    /// @notice Set contract name and address in the address book
    /// @param _contractName name of the contract
    /// @param _address the address of the contract
    function setAddressInAddressBook(string memory _contractName, address _address) external onlyOwner {
        require(_address != address(0), "InvalidAddress");
        addressBook[_contractName] = _address;
        emit NewContractInAddressBook(_contractName, _address);
    }

    /// @notice Reset a contract name to ZERO address
    /// @param _contractName name of the contract
    function resetAddressForContract(string memory _contractName) external onlyOwner {
        require(addressBook[_contractName] != address(0), "AlreadyReset");
        addressBook[_contractName] = address(0);
        emit NewContractInAddressBook(_contractName, address(0));
    }

    //////////////////events/////////////////

    event NewContractInAddressBook(string _contractName, address _address);
    event SetAddresses(
        address _safeBox,
        address _referrals,
        address _stakingThales,
        address _multiCollateralOnOffRamp,
        address _pyth,
        address _speedMarketsAMM
    );

    error InvalidAddressForContractName(string _contractName);
}
