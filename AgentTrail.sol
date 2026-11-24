// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal read interface of the official Agent ID registry
///         (SPACE ID Agent ID on BNB Chain, ERC-721, non-transferable).
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentTrail — daily on-chain stamps for AI agents
/// @notice Only wallets holding an Agent ID can stamp, once per UTC day.
///         Stamps are soulbound ERC-721 tokens with fully on-chain SVG art.
///         Cumulative stamp counts of 3 / 7 / 14 unlock milestone badges.
///         The contract never accepts or holds funds (stamp is non-payable).
///         Owner powers are limited to a single pause switch (setStampOpen),
///         disclosed here and in the project README. No owner mint, no withdraw.
contract AgentTrail {
    // ------------------------------------------------------------------
    // ERC-721 metadata
    // ------------------------------------------------------------------
    string public constant name = "AgentTrail";
    string public constant symbol = "TRAIL";

    /// Official Agent ID registry on BNB Chain.
    address public constant AGENT_ID_REGISTRY = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    // ------------------------------------------------------------------
    // Ownership (minimal): deployer, pause switch only
    // ------------------------------------------------------------------
    address public owner;
    bool public stampOpen = true;

    // ------------------------------------------------------------------
    // Token state
    // ------------------------------------------------------------------
    uint256 public nextTokenId = 1;
    mapping(uint256 => address) private _tokenOwner;
    mapping(address => uint256) private _balance;
    /// 0 = daily stamp, 1..3 = milestone badge tier
    mapping(uint256 => uint8) public tokenKind;
    /// UTC day index (days since epoch) when a stamp was made
    mapping(uint256 => uint256) public tokenDay;
    /// Streak value recorded on a stamp token
    mapping(uint256 => uint256) public tokenStreak;

    // ------------------------------------------------------------------
    // Agent activity state
    // ------------------------------------------------------------------
    mapping(address => uint256) public lastStampDay;
    mapping(address => uint256) public currentStreak;
    mapping(address => uint256) public totalStampsOf;
    /// Bitmask of claimed milestone tiers (bit 0 = 3 stamps, bit 1 = 7, bit 2 = 14)
    mapping(address => uint256) public milestoneClaimedMask;
    uint256 public totalAgents;
    uint256 public totalStampsAll;
    mapping(uint256 => uint256) public stampsOnDay;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Stamp(address indexed agent, uint256 indexed tokenId, uint256 day, uint256 streak);
    event Milestone(address indexed agent, uint256 indexed tokenId, uint256 tier, uint256 threshold);
    event StampOpenChanged(bool open);

    constructor() {
        owner = msg.sender;
    }

    // ------------------------------------------------------------------
    // Core: daily stamp
    // ------------------------------------------------------------------
    function todayIndex() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    function hasAgentId(address account) public view returns (bool) {
        return IAgentIdRegistry(AGENT_ID_REGISTRY).balanceOf(account) > 0;
    }

    function canStampToday(address account) public view returns (bool) {
        return stampOpen && hasAgentId(account) && lastStampDay[account] < todayIndex();
    }

    /// @notice Mint today's stamp. Free. One per Agent ID address per UTC day.
    function stamp() external returns (uint256 tokenId) {
        require(stampOpen, "AgentTrail: stamping paused");
        require(hasAgentId(msg.sender), "AgentTrail: Agent ID required");
        uint256 today = todayIndex();
        require(lastStampDay[msg.sender] < today, "AgentTrail: already stamped today");

        uint256 streak;
        if (lastStampDay[msg.sender] == today - 1) {
            streak = currentStreak[msg.sender] + 1;
        } else {
            streak = 1;
        }
        if (totalStampsOf[msg.sender] == 0) {
            totalAgents += 1;
        }
        lastStampDay[msg.sender] = today;
        currentStreak[msg.sender] = streak;
        totalStampsOf[msg.sender] += 1;
        totalStampsAll += 1;
        stampsOnDay[today] += 1;

        tokenId = _mint(msg.sender, 0);
        tokenDay[tokenId] = today;
        tokenStreak[tokenId] = streak;
        emit Stamp(msg.sender, tokenId, today, streak);
    }

    // ------------------------------------------------------------------
    // Core: milestone badges at 3 / 7 / 14 cumulative stamps
    // ------------------------------------------------------------------
    function milestoneThreshold(uint256 tier) public pure returns (uint256) {
        if (tier == 0) return 3;
        if (tier == 1) return 7;
        if (tier == 2) return 14;
        revert("AgentTrail: bad tier");
    }

    function milestoneClaimable(address account, uint256 tier) public view returns (bool) {
        if (tier > 2) return false;
        return totalStampsOf[account] >= milestoneThreshold(tier)
            && (milestoneClaimedMask[account] & (1 << tier)) == 0;
    }

    /// @notice Claim a milestone badge once cumulative stamps reach 3 / 7 / 14.
    function claimMilestone(uint256 tier) external returns (uint256 tokenId) {
        require(tier <= 2, "AgentTrail: bad tier");
        require(hasAgentId(msg.sender), "AgentTrail: Agent ID required");
        uint256 threshold = milestoneThreshold(tier);
        require(totalStampsOf[msg.sender] >= threshold, "AgentTrail: not enough stamps");
        require((milestoneClaimedMask[msg.sender] & (1 << tier)) == 0, "AgentTrail: already claimed");
        milestoneClaimedMask[msg.sender] |= (1 << tier);
        tokenId = _mint(msg.sender, uint8(tier + 1));
        emit Milestone(msg.sender, tokenId, tier, threshold);
    }

    // ------------------------------------------------------------------
    // Owner: pause switch only
    // ------------------------------------------------------------------
    function setStampOpen(bool open) external {
        require(msg.sender == owner, "AgentTrail: not owner");
        stampOpen = open;
        emit StampOpenChanged(open);
    }

    // ------------------------------------------------------------------
    // ERC-721 (soulbound: transfers and approvals always revert)
    // ------------------------------------------------------------------
    function balanceOf(address account) external view returns (uint256) {
        require(account != address(0), "AgentTrail: zero address");
        return _balance[account];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _tokenOwner[tokenId];
        require(tokenOwner != address(0), "AgentTrail: nonexistent token");
        return tokenOwner;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    function transferFrom(address, address, uint256) external pure {
        revert("AgentTrail: soulbound");
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert("AgentTrail: soulbound");
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert("AgentTrail: soulbound");
    }

    function approve(address, uint256) external pure {
        revert("AgentTrail: soulbound");
    }

    function setApprovalForAll(address, bool) external pure {
        revert("AgentTrail: soulbound");
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        require(_tokenOwner[tokenId] != address(0), "AgentTrail: nonexistent token");
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function _mint(address to, uint8 kind) internal returns (uint256 tokenId) {
        tokenId = nextTokenId++;
        _tokenOwner[tokenId] = to;
        _balance[to] += 1;
        tokenKind[tokenId] = kind;
        emit Transfer(address(0), to, tokenId);
    }

    // ------------------------------------------------------------------
    // On-chain metadata: JSON + SVG data URIs
    // ------------------------------------------------------------------
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_tokenOwner[tokenId] != address(0), "AgentTrail: nonexistent token");
        uint8 kind = tokenKind[tokenId];
        string memory title;
        string memory line1;
        string memory line2;
        string memory bg;
        if (kind == 0) {
            title = "AgentTrail Stamp";
            line1 = string(abi.encodePacked("Day ", _toString(tokenDay[tokenId])));
            line2 = string(abi.encodePacked("Streak ", _toString(tokenStreak[tokenId])));
            bg = "#1b2a4a";
        } else {
            uint256 threshold = milestoneThreshold(kind - 1);
            title = "AgentTrail Milestone";
            line1 = string(abi.encodePacked(_toString(threshold), " Stamps"));
            line2 = string(abi.encodePacked("Tier ", _toString(kind)));
            bg = "#4a2a1b";
        }
        string memory svg = string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400' viewBox='0 0 400 400'>",
                "<rect width='400' height='400' fill='", bg, "'/>",
                "<circle cx='200' cy='150' r='70' fill='none' stroke='#f0b90b' stroke-width='6'/>",
                "<text x='200' y='165' font-family='monospace' font-size='34' fill='#f0b90b' text-anchor='middle'>AT</text>",
                "<text x='200' y='275' font-family='monospace' font-size='26' fill='#ffffff' text-anchor='middle'>", line1, "</text>",
                "<text x='200' y='315' font-family='monospace' font-size='22' fill='#9fb3c8' text-anchor='middle'>", line2, "</text>",
                "<text x='200' y='365' font-family='monospace' font-size='16' fill='#5f7a99' text-anchor='middle'>#", _toString(tokenId), "</text>",
                "</svg>"
            )
        );
        string memory json = string(
            abi.encodePacked(
                '{"name":"', title, " #", _toString(tokenId),
                '","description":"AgentTrail: daily on-chain stamps for Agent ID holders on BNB Chain. Soulbound, free, one per agent per day.",',
                '"image":"data:image/svg+xml;base64,', _base64(bytes(svg)),
                '","attributes":[{"trait_type":"Kind","value":"', kind == 0 ? "Stamp" : "Milestone", '"}]}'
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(json))));
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    bytes internal constant _B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function _base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        uint256 i;
        uint256 j;
        while (i < data.length) {
            uint256 a = uint8(data[i]);
            uint256 b = i + 1 < data.length ? uint8(data[i + 1]) : 0;
            uint256 c = i + 2 < data.length ? uint8(data[i + 2]) : 0;
            result[j++] = _B64[a >> 2];
            result[j++] = _B64[((a & 3) << 4) | (b >> 4)];
            result[j++] = i + 1 < data.length ? _B64[((b & 15) << 2) | (c >> 6)] : bytes1("=");
            result[j++] = i + 2 < data.length ? _B64[c & 63] : bytes1("=");
            i += 3;
        }
        return string(result);
    }
}
