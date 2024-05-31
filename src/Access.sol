// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "openzeppelin-contracts/contracts/access/AccessControl.sol";

abstract contract Access is AccessControl {
    ///@dev roles for calling keeper functions
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    constructor(address admin_, address keeper_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(KEEPER_ROLE, keeper_);
    }
}
