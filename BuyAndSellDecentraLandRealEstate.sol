pragma solidity ^0.8.6;

import "./IBuyAndSellDecentraLandRealEstate.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract BuyAndSellDecentraLandRealEstate is IBuyAndSellDecentraLandRealEstate, AccessControl {
    // For managing the listings in the contract
    bytes32 public constant LISTING_MANAGER = keccak256("LISTING_MANAGER");

    // For changing any of the global configuration and defaults, as well as access to sensitive functions
    bytes32 public constant CONFIG_MANAGER = keccak256("CONFIG_MANAGER");
}