// This is the main NFT contract, these NFTs generate rewards through the foodtruck

// @dev Fellow developper, i'm too lazy to comment my code, figure it out yourself, eventually with the help of the cryptic comments i added to help me remember what i was doing while getting this to work, if they make it into prod.  
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./deps/Ownable.sol";
import "./deps/ERC721Pausable.sol";
import "./deps/VRFConsumerBase.sol";
import "./deps/VRFRequestIDBase.sol";
import "./deps/interfaces/LinkTokenInterface.sol";

contract Chef is Ownable, ERC721Pausable {
    // Tokens 1 => 9100 are humans, 9101 to 10000 are tikis TODO No. 
    uint256 public currentSupply;
    uint256 public immutable MAX_SUPPLY = 10000;
    uint256 public mintPrice = 3 ether;
    bytes32 keyHash;
    uint256 fee;
    uint256 maxTokens = 20;
    mapping(address => uint96) userMinted;
    mapping (uint => bool) private _isTiki;
    uint256 private _numTikis;
    uint256 public immutable MAX_TIKIS = 900;
    struct Params {
        address user;
        uint96 mintQty;
    }
    uint256[] private tikiIndex;
    uint256[] private humanIndex;
    bool revealed;
    string notRevealedURI;
    // How tho? 
    string tikiURI;
    string humanURI;
    
    mapping(bytes32 => Params) mintParams;

    constructor() ERC721("Chef", "CHEF") {}

    function totalSupply() external view returns (uint256) {
        return currentSupply;
    }




    function setMintPrice(uint256 price) external onlyOwner {
        mintPrice = price;
    }

    // Temp: for local tests. Will be removed in prod 
    bool chainlinkImplemented;
    function weakRandomness(uint seed) internal view returns(uint256) {
        return uint256(keccak256(abi.encode(seed, block.timestamp, currentSupply)));
    }
    
    function mint(uint qty) external payable {
        require(mintPrice * qty <= msg.value, "!value");
        require(qty < 5, "!mintLimit");
        require(userMinted[msg.sender] + qty <= maxTokens, '!maxTokens');
        userMinted[msg.sender] += qty;
        // For tests only
        if (chainlinkImplemented == false) {
            uint seed = weakRandomness(uint(uint160(msg.sender)));
            internalMint(qty, seed, msg.sender);
        }
        else {
            bytes32 requestId = requestRandomness(keyHash, fee);
            mintParams[requestId] = Params(msg.sender, uint96(mintQty));
        }

    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        (address user, uint qty) = retrieveRequest(requestId);
        internalMint(qty, randomness, user);
    }

    function retrieveRequest(bytes32 requestId) internal view returns(address user, uint qty) {
        user = mintParams[requestId].user;
        qty = mintParams[requestId].qty;
    }

    // Mints an arbitrary amount of tokens to an address provided a 32 bytes random number and a quantity. 
    function internalMint(uint qty, uint rng, address to) internal {
        uint minted;
        // Main mint loop
        do {
            uint mintedThisGo = 0;
            // We only use one specific seed 16 times before randomizing it again
            for(uint i; i < 16; i++) {
                uint16 seed = uint16(rng);
                rng >>= 16;
                uint256 tokenId = (seed % MAX_SUPPLY) + 1;
                if(!_exists(tokenId)) {
                    // Statistically ensures that all the tikis will be minted by making the actual percentage more than 9%
                    if(rng % 100 < 11 && _numTikis <= MAX_TIKIS) {
                        _isTiki[tokenId] = true;
                        tikiIndex.push(tokenId);
                    }
                    else {
                        humanIndex.push(tokenId);
                    }
                    _safeMint(to, tokenId);
                    ++currentSupply;
                    ++minted;
                    if(minted == qty) {
                        break;
                    }
                }
            }
            if(minted < qty) {
            rng = uint256(keccak256(bytes32(rng)));
            }
        }while(minted < qty);
    }



// NOTE TEST FOR EXEC WITH 10k TOKENS. POTENTIALLY NEED A PRIVATE NODE W UNLIMITED GAS FOR VIEW FUNCTIONS (can you do that on avalanche?)

    // View
    function isTiki(uint tokenId) public pure returns(bool) {
        require(revealed, "!reveal");
        return(_isTiki[tokenId]);
    }
    function numTikis() public view returns(uint256) {
        require(revealed, "!reveal");
        return _numTikis;
    }
    
    // NOTE: Will always  work with 10k tokens. Don't rely on it  for any kind of execution though
    function getMyChefs(address who) external view returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](balanceOf(who));
        uint cnt;
        for(uint256 i = 0; i < currentSupply; i++) {
            if (ownerOf(i) == who) {
                toks[cnt++] = i;
            }
        }
    }
    
    // Costs a huge lot of gas
    function tokenURI(uint256 tokenId) public view override returns(string memory) {
        if(!revealed) {
            return notRevealedURI;
        }
        else if(isTiki) {
            uint index;
            for(uint i; i < MAX_TIKIS; i++) {
                if(tikiIndex[i] == tokenId) {
                    index = i;
                    break;
                }
            }
            return(string(abi.encodePacked(tikiURI, index.toString())));
        }
        else {
            uint index;
            for(uint i; i < (MAX_SUPPLY - MAX_TIKIS); i++) {
                if(humanIndex[i] == tokenId) {
                    index = i;
                    break;
                }
            }
            return(string(abi.encodePacked(humanURI, index.toString())));
        }
    }


}


