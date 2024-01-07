// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

/* solhint-disable no-empty-blocks */

import "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

abstract contract GuardianCompatible {
    address public ownerRecorded;
    mapping(uint256 => mapping (address => bool)) public guardians;

    struct Recovery {
        uint approvalCount;
        uint startTime;
        mapping(address => bool) voted; 
    }

    mapping(uint256 => mapping(address => Recovery)) public recoveries;
    uint256 public recoveryPeriod = 10 minutes;

    uint256 public counter;

    uint8 guardianCount;
    uint8 public threshhold;
    bool public guardianFlag = false;

    modifier onlyGuardian() {
        require(guardians[counter][msg.sender], "only guardian");
        _;
    }

    // -----If your TBA base contract inherits this module, you MUST override these functions-----

    //check if the caller is the owner of the NFT
    function checkCallerIsOwner() internal virtual {}

    //update the ownerRecorded to the owner of the NFT
    function updateOwnerRecorded() internal virtual {}

    //check if the TBA is the operator of the NFT
    function checkIsOperator() internal virtual {}

    //trasfer NFT to the new owner
    function transferOwnership(address _newOwner) internal virtual {}

    //check if the owner stored is consistent with the owner of the NFT
    function checkOwnerConsistency() internal virtual {}

    // -------------------------------------------------------------------------------------------

    function initializeGuardians(address[] memory _guardians, uint8 _threshhold) external {
        checkCallerIsOwner();
        checkIsOperator();
        require(_guardians.length > 0 && _guardians.length < 9, " 0 < Number of guardians < 9");
        require(_threshhold > 0 && _threshhold <= _guardians.length, " 0 < threshhold <= Number of guardians");
        require(!guardianFlag, "guardians already initialized");
        updateOwnerRecorded();
        for (uint256 i = 0; i < _guardians.length; i++) {
            guardians[counter][_guardians[i]] = true;
        }
        guardianCount = uint8(_guardians.length);
        threshhold = _threshhold;
        guardianFlag = true;
    }

    function addGuardian(address _guardian, uint8 _threshhold) external {
        checkCallerIsOwner();
        require(!guardians[counter][_guardian], "guardian already exists");
        guardians[counter][_guardian] = true;
        guardianCount++;
        threshhold = _threshhold;
    }

    function removeGuardian(address _guardian, uint8 _threshhold) external {
        checkCallerIsOwner();
        require(guardians[counter][_guardian], "guardian does not exist");
        guardians[counter][_guardian] = false;
        guardianCount--;
        threshhold = _threshhold;
    }

    function getGuardianCount() public view returns (uint256) {
        return guardianCount;
    }

    function getThreshhold() public view returns (uint8) {
        return threshhold;
    }

    function setThreshhold(uint8 _threshhold) external  {
        checkCallerIsOwner();
        require(_threshhold <= getGuardianCount(), "threshhold must be less than or equal to the number of guardians");
        require(_threshhold > 0, "threshhold must be greater than 0");
        threshhold = _threshhold;
    }

    function validateNewOwner(address _newOwner) internal view returns (uint8) {
        if(_newOwner == address(0)) return 1;
        if(_newOwner == ownerRecorded) return 2;
        if(guardians[counter][_newOwner]) return 3;
        if(_newOwner == address(this)) return 4;
        return 0;
    }

    function proposeChangeOwner(address _newOwner) external onlyGuardian() {
        checkIsOperator();
        checkOwnerConsistency();
        uint8 valid = validateNewOwner(_newOwner);
        Strings.toString(valid);
        if (valid != 0) revert(string(abi.encodePacked("valid = ", Strings.toString(valid))));
        if (recoveries[counter][_newOwner].approvalCount > 0){
            require(block.timestamp > recoveries[counter][_newOwner].startTime + recoveryPeriod, "_newOwner is currently an active proposal");   
        }
        recoveries[counter][_newOwner].startTime = block.timestamp;
        recoveries[counter][_newOwner].approvalCount = 1;
        recoveries[counter][_newOwner].voted[msg.sender] = true;
    }

    function voteChangeOwner(address _newOwner) external onlyGuardian() {
        checkIsOperator();
        checkOwnerConsistency();
        require(recoveries[counter][_newOwner].approvalCount > 0, "no recovery in progress");
        require(!recoveries[counter][_newOwner].voted[msg.sender], "already voted");
        require(block.timestamp < recoveries[counter][_newOwner].startTime + recoveryPeriod, "recovery period expired");
        recoveries[counter][_newOwner].approvalCount++;
        recoveries[counter][_newOwner].voted[msg.sender] = true;
    }

    function executeChangeOwner(address _newOwner) external onlyGuardian() {
        checkIsOperator();
        checkOwnerConsistency();
        require(recoveries[counter][_newOwner].approvalCount > 0, "no recovery in progress");
        require(block.timestamp < recoveries[counter][_newOwner].startTime + recoveryPeriod, "recovery period expired");
        require(recoveries[counter][_newOwner].approvalCount >= threshhold, "not enough votes");
        transferOwnership(_newOwner);
        ownerRecorded = _newOwner;
        threshhold = 0;
        guardianCount = 0;
        guardianFlag = false;
        counter++;
    }
}