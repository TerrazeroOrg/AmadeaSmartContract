pragma solidity ^0.8.7;

// SPDX-License-Identifier: Apache-2.0

interface IBuyAndSellDecentraLandRealEstate {
    enum ListingStatus {
        OPEN_FOR_SALE,
        SOLD,
        CLOSED_BY_ADMIN
    }

    event ListingCreated(
        uint256 listingId,
        uint256 publicDate,
        uint256 end,
        uint256 buyItNowPrice,
        uint256 royaltyPercentage,
        uint256 floorPrice,
        address owner,
        uint256 idFromNft,
        address paymentCurrency
    );

    event ListingUpdated(
        uint256 listingId,
        uint256 publicDate,
        uint256 end,
        uint256 buyItNowPrice,
        uint256 royaltyPercentage,
        uint256 floorPrice,
        address owner,
        uint256 idFromNft,
        address paymentCurrency
    );

    event ListingUpdatedStart(uint256 listingId, uint256 publicDate);
    event ListingUpdatedEnd(uint256 listingId, uint256 end);
    event ListingUpdatedPrice(uint256 listingId, uint256 buyItNowPrice);
    event ListingUpdatedRoyalty(uint256 listingId, uint256 royaltyPercentage);
    event ListingUpdatedFloor(uint256 listingId, uint256 floorPrice);
    event ListingUpdatedIdNFT(uint256 listingId, uint256 idFromNft);
    event ListingUpdatedPayment(uint256 listingId, address paymentCurrency);

    event ListingCancelled(uint256 id, uint256 idFromNft, address owner);

    event NFTsold(
        uint256 listingId,
        address from,
        address to,
        uint256 idFromNft,
        uint256 buyItNowPrice,
        address paymentCurrency
    );

    struct Listing {
        ListingStatus status; // representing the managed state of a listing
        uint256 id;
        uint256 publicDate; // date when the listing will be made public, bidding/buying before this date will be impossible
        uint256 end; // date in which a listing is no longer valid
        uint256 buyItNowPrice; // price of the buy-it-now, if 0, no buy-it-now
        uint256 royaltyPercentage; // basepoints percentage - the amount to be paid to the royaltyReceiver. This is set on a per-listing basis
        uint256 floorPrice; // the value that must be bid to buy the property
        address payable owner;
        uint256 idFromNft;
        address paymentCurrency; //The payment token, address(0) for ETH
    }

    /**
     * @dev submits the initial metadata for a listing. This will not make anything public, but will allow the calling
     * of submitRealEstate afterwards.
     */
    function createListing(
        uint256 publicDate,
        uint256 endTime,
        uint256 buyItNowPrice,
        uint256 idFromNft,
        uint256 royaltyPercentage,
        uint256 floorPrice,
        address paymentCurrency
    ) external returns (uint256);

    /**
     * @dev this is to only be called by the user who is holding the realEstate. This will approve the contract to
     * transfer their NFT on the seller's behalf. This may not be needed in final implementation, as we could just use
     * approve on ERC721
     */

    /**
     * @dev sets the cancelled bool in Listing to true. This will prevent the listing from being shown on the frontend.
     */
    function cancelListing(uint256 listingId) external;

    /**
     * @dev will get the listing, intended to be called on the frontend. Should still be able to get cancelled listings
     */
    function getListing(uint256 listingId)
        external
        view
        returns (Listing memory);

    /**
     * @dev Get all active listings for NFT Ids
     * @param tokenIds array of NFT ids
     * @return listingIds array of active liting ids
     */
    function getActiveListingIds(uint256[] memory tokenIds)
        external
        view
        returns (uint256[] memory listingIds);

    /**
     * @dev will allow adjusting of details on the listing, this will not be callable after the public date.
     *
     */
    function updateListing(
        uint256 listingId,
        uint256 publicDate,
        uint256 end,
        uint256 buyItNowPrice,
        uint256 royaltyPercentage,
        uint256 floorPrice,
        uint256 idFromNft,
        address paymentCurrency
    ) external;

    /**
     * @dev public buy function for instant buy listing for buyItNowPrice
     * Expects msg.value == buyItNowPrice and buyItNowPrice != 0 (= instant buy enabled)
     */
    function buyListing(uint256 listingId) external payable;

    /**
     * @dev function for LISTIN_MANAGER to fulfill an aution type listing
     * Expects buyer to already have approved the contract for WETH price - should happen on bidding in dApp
     */
    function fullfillAuction(
        uint256 listingId,
        address buyer,
        uint256 price
    ) external;
}