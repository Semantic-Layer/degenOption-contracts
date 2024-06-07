// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "openzeppelin-contracts/contracts/access/AccessControl.sol";

abstract contract Access is AccessControl {
    constructor(address admin_) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }
}
