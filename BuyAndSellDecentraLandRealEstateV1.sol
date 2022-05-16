pragma solidity ^0.8.6;

import "./BuyAndSellDecentraLandRealEstate.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BuyAndSellDecentraLandRealEstateV1 is BuyAndSellDecentraLandRealEstate {
    using SafeMath for uint256;
    using Address for address;

    using Counters for Counters.Counter;
    Counters.Counter private _listingIds;

    uint256 private _maxSaleDuration;
    address payable private _royaltyReceiver;

    mapping(uint256 => uint256) private _tokenIdToListing;
    mapping(uint256 => Listing) private listingsMap;

    IERC721 public LAND;
    address public WETH;

    function initialize() public {
        _maxSaleDuration = 7 days;
        _setupRole(CONFIG_MANAGER, msg.sender);
        _setRoleAdmin(CONFIG_MANAGER, CONFIG_MANAGER);
        _setupRole(LISTING_MANAGER, msg.sender);
        _setRoleAdmin(LISTING_MANAGER, CONFIG_MANAGER);
    }

    //Helper function safetransferfrom ERC20
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FROM_FAILED"
        );
    }

    function createListing(
        uint256 publicDate,
        uint256 endTime,
        uint256 buyItNowPrice,
        uint256 idFromNft,
        uint256 royaltyPercentage,
        uint256 floorPrice,
        address paymentCurrency
    ) external override onlyRole(LISTING_MANAGER) returns (uint256 listingId) {
        address owner = LAND.ownerOf(idFromNft);
        require(
            owner == address(this) ||
            LAND.getApproved(idFromNft) == address(this) ||
            LAND.isApprovedForAll(owner, address(this)),
            "Not approved for token"
        );
        require(
            publicDate >= block.timestamp,
            "public date cannot be in the past"
        );
        require(
            endTime > block.timestamp && endTime > publicDate,
            "Invalid endtime"
        );
        require(royaltyPercentage < 10000, "Invalid royalties");

        require(
            buyItNowPrice == 0 || floorPrice < buyItNowPrice,
            "Invalid price"
        );

        Listing memory existingSale = listingsMap[_tokenIdToListing[idFromNft]];

        require(
            existingSale.id == 0 || //Has no sale for nft ever
            existingSale.end < block.timestamp, //Listing expired
            "Already active listing for this NFT"
        );

        _listingIds.increment();
        listingId = _listingIds.current();
        require(listingsMap[listingId].id == 0, "Invalid Listing id");

        uint256 _maxEndTime = block.timestamp.add(_maxSaleDuration);
        uint256 _endTime = endTime > _maxEndTime ? _maxEndTime : endTime;

        Listing memory _listing = Listing({
        status: ListingStatus.OPEN_FOR_SALE,
        id: listingId,
        publicDate: block.timestamp,
        end: _endTime,
        buyItNowPrice: buyItNowPrice,
        royaltyPercentage: royaltyPercentage,
        floorPrice: floorPrice,
        idFromNft: idFromNft,
        owner: payable(owner),
        paymentCurrency: paymentCurrency
        });

        listingsMap[listingId] = _listing;
        _tokenIdToListing[idFromNft] = listingId;

        emit ListingCreated(
            _listing.id,
            _listing.publicDate,
            _listing.end,
            _listing.buyItNowPrice,
            _listing.royaltyPercentage,
            _listing.floorPrice,
            _listing.owner,
            _listing.idFromNft,
            _listing.paymentCurrency
        );

        return _listing.id;
    }

    function buyListing(uint256 listingId) external payable override {
        Listing memory _listing = listingsMap[listingId];
        uint256 price = _listing.buyItNowPrice;

        require(
            _listing.id != 0 && _listing.status == ListingStatus.OPEN_FOR_SALE,
            "Invalid Listing"
        );
        require(price != 0, "Cannot instant buy listing");
        require(
            _listing.publicDate <= block.timestamp,
            "Listing has not started"
        );
        require(_listing.end >= block.timestamp, "Listing is over");

        address paymentToken = _listing.paymentCurrency;
        uint256 buyFee = price.mul(_listing.royaltyPercentage).div(10000);

        if (paymentToken == address(0)) {
            require(msg.value == price, "Invalid value sent");

            //takeFee and send money to seller
            (bool sentA, ) = _listing.owner.call{value: msg.value.sub(buyFee)}(
                ""
            );
            (bool sentR, ) = _royaltyReceiver.call{value: buyFee}("");

            require(sentA && sentR, "Failed to transfer share");
        } else {
            require(msg.value == 0, "Cannot buy with ETH");

            safeTransferFrom(
                paymentToken,
                msg.sender,
                _listing.owner,
                price.sub(buyFee)
            );
            safeTransferFrom(
                paymentToken,
                msg.sender,
                _royaltyReceiver,
                buyFee
            );
        }

        LAND.safeTransferFrom(_listing.owner, msg.sender, _listing.idFromNft);

        listingsMap[listingId].status = ListingStatus.SOLD;
        _tokenIdToListing[_listing.idFromNft] = 0;

        emit NFTsold(
            _listing.id,
            _listing.owner,
            msg.sender,
            _listing.idFromNft,
            _listing.buyItNowPrice,
            _listing.paymentCurrency
        );
    }

    function fullfillAuction(
        uint256 listingId,
        address buyer,
        uint256 price
    ) external override onlyRole(LISTING_MANAGER) {
        Listing memory _listing = listingsMap[listingId];

        require(
            _listing.id != 0 && _listing.status == ListingStatus.OPEN_FOR_SALE,
            "Invalid Listing"
        );
        require(price >= _listing.floorPrice, "Invalid price"); //TODO optional check, LISTING_MANAGER should only fulfill with the right price

        address paymentToken = _listing.paymentCurrency == address(0)
        ? WETH
        : _listing.paymentCurrency;

        uint256 buyFee = price.mul(_listing.royaltyPercentage).div(10000);

        safeTransferFrom(
            paymentToken,
            buyer,
            _listing.owner,
            price.sub(buyFee)
        );
        safeTransferFrom(paymentToken, buyer, _royaltyReceiver, buyFee);

        LAND.safeTransferFrom(_listing.owner, buyer, _listing.idFromNft);

        listingsMap[listingId].status = ListingStatus.SOLD;
        _tokenIdToListing[_listing.idFromNft] = 0;

        emit NFTsold(
            _listing.id,
            _listing.owner,
            buyer,
            _listing.idFromNft,
            price,
            _listing.paymentCurrency
        );
    }

    function cancelListing(uint256 listingId)
    external
    override
    onlyRole(LISTING_MANAGER)
    {
        Listing memory _listing = listingsMap[listingId];

        require(
            _listing.id != 0 && _listing.status == ListingStatus.OPEN_FOR_SALE,
            "Invalid Listing"
        );
        require(_listing.end >= block.timestamp, "Listing is over");

        listingsMap[listingId].status = ListingStatus.CLOSED_BY_ADMIN;
        _tokenIdToListing[_listing.idFromNft] = 0;

        emit ListingCancelled(_listing.id, _listing.idFromNft, _listing.owner);
    }

    //################################################
    //Update listing functions - only LISTING_MANAGER
    //################################################
    function updateListing(
        uint256 listingId,
        uint256 publicDate,
        uint256 end,
        uint256 buyItNowPrice,
        uint256 royaltyPercentage,
        uint256 floorPrice,
        uint256 idFromNft,
        address paymentCurrency
    ) external override onlyRole(LISTING_MANAGER) {
        address owner = LAND.ownerOf(idFromNft);
        require(
            owner == address(this) ||
            LAND.getApproved(idFromNft) == address(this) ||
            LAND.isApprovedForAll(owner, address(this)),
            "Not approved for token"
        );

        listingsMap[listingId].publicDate = publicDate;
        listingsMap[listingId].end = end;
        listingsMap[listingId].buyItNowPrice = buyItNowPrice;
        listingsMap[listingId].royaltyPercentage = royaltyPercentage;
        listingsMap[listingId].floorPrice = floorPrice;
        listingsMap[listingId].owner = payable(owner);
        listingsMap[listingId].idFromNft = idFromNft;
        listingsMap[listingId].paymentCurrency = paymentCurrency;

        Listing memory _listing = listingsMap[listingId];

        emit ListingUpdated(
            _listing.id,
            _listing.publicDate,
            _listing.end,
            _listing.buyItNowPrice,
            _listing.royaltyPercentage,
            _listing.floorPrice,
            _listing.owner,
            _listing.idFromNft,
            _listing.paymentCurrency
        );
    }

    function updateListingPublicDate(uint256 listingId, uint32 newPublicDate)
    external
    onlyRole(LISTING_MANAGER)
    returns (uint256)
    {
        listingsMap[listingId].publicDate = newPublicDate;
        emit ListingUpdatedStart(listingId, listingsMap[listingId].publicDate);
        return listingsMap[listingId].publicDate;
    }

    function updateListingEndDate(uint256 listingId, uint32 newEndDate)
    external
    onlyRole(LISTING_MANAGER)
    returns (uint256)
    {
        listingsMap[listingId].end = newEndDate;
        emit ListingUpdatedEnd(listingId, listingsMap[listingId].end);
        return listingsMap[listingId].end;
    }

    function updateListingBuyItNowPrice(
        uint256 listingId,
        uint256 newBuyItNowPrice
    ) external onlyRole(LISTING_MANAGER) returns (uint256) {
        listingsMap[listingId].buyItNowPrice = newBuyItNowPrice;
        emit ListingUpdatedPrice(
            listingId,
            listingsMap[listingId].buyItNowPrice
        );
        return listingsMap[listingId].buyItNowPrice;
    }

    function updateListingRoyaltyPercentage(
        uint256 listingId,
        uint256 newPercentage
    ) external onlyRole(LISTING_MANAGER) returns (uint256) {
        listingsMap[listingId].royaltyPercentage = newPercentage;
        emit ListingUpdatedRoyalty(
            listingId,
            listingsMap[listingId].royaltyPercentage
        );
        return listingsMap[listingId].royaltyPercentage;
    }

    function updateListingFloorPrice(uint256 listingId, uint256 newFloorPrice)
    external
    onlyRole(LISTING_MANAGER)
    returns (uint256)
    {
        listingsMap[listingId].floorPrice = newFloorPrice;
        emit ListingUpdatedFloor(listingId, listingsMap[listingId].floorPrice);
        return listingsMap[listingId].floorPrice;
    }

    function updateListingIdFromNFT(uint256 listingId, uint256 newIDfromNFT)
    external
    onlyRole(LISTING_MANAGER)
    returns (uint256)
    {
        listingsMap[listingId].idFromNft = newIDfromNFT;
        emit ListingUpdatedIdNFT(listingId, listingsMap[listingId].idFromNft);
        return listingsMap[listingId].idFromNft;
    }

    function updateListingPaymentCurrency(uint256 listingId, address newpayment)
    external
    onlyRole(LISTING_MANAGER)
    returns (uint256)
    {
        listingsMap[listingId].paymentCurrency = newpayment;
        emit ListingUpdatedPayment(
            listingId,
            listingsMap[listingId].paymentCurrency
        );
        return listingsMap[listingId].idFromNft;
    }

    function getListing(uint256 listingId)
    external
    view
    override
    returns (Listing memory)
    {
        return listingsMap[listingId];
    }

    function getActiveListingIds(uint256[] memory tokenIds)
    external
    view
    override
    returns (uint256[] memory listingIds)
    {
        listingIds = new uint256[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            Listing memory _listing = listingsMap[
            _tokenIdToListing[tokenIds[i]]
            ];
            if (
                _listing.id != 0 &&
                _listing.status == ListingStatus.OPEN_FOR_SALE &&
                _listing.end > block.timestamp
            ) {
                //TODO if token got transferred beside the sale the contract does not know,
                // might compare sale seller and curretn owner
                listingIds[i] = _listing.id;
            }
        }
    }

    //################################################
    //Update config functions - only CONFIG_MANAGER
    //################################################
    function setMaxSaleDuration(uint256 maxSaleDuration)
    external
    onlyRole(CONFIG_MANAGER)
    {
        _maxSaleDuration = maxSaleDuration;
    }

    function setRoyaltyReceiver(address payable royaltyReceiver)
    external
    onlyRole(CONFIG_MANAGER)
    {
        _royaltyReceiver = royaltyReceiver;
    }

    function setLAND(address LANDAddress) external onlyRole(CONFIG_MANAGER) {
        LAND = IERC721(LANDAddress);
    }

    function setWETH(address weth) external onlyRole(CONFIG_MANAGER) {
        WETH = weth;
    }

    function setLANDandWETH(address LANDAddress, address weth)
    external
    onlyRole(CONFIG_MANAGER)
    {
        LAND = IERC721(LANDAddress);
        WETH = weth;
    }

    function getRoyaltyReceiver() external view returns (address) {
        return _royaltyReceiver;
    }

    function getCurrentListingId() external view returns (uint256) {
        return _listingIds.current();
    }
}