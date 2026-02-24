// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MusicRoyalty {
    address public owner;
    address public artist;
    address public label;
    uint public artistShare = 70; // e.g., 70%
    uint public labelShare = 30;  // e.g., 30%
    
    event PaymentReceived(address payer, uint amount);
    event RoyaltiesDistributed(address indexed recipient, uint amount);
    
    constructor(address _artist, address _label) {
        owner = msg.sender;
        artist = _artist;
        label = _label;
    }
    
    // Receive payments (e.g., stream revenue)
    receive() external payable {
        distributeRoyalties();
        emit PaymentReceived(msg.sender, msg.value);
    }
    
    // Distribute to artist and label based on shares
    function distributeRoyalties() private {
        uint artistAmount = (msg.value * artistShare) / 100;
        uint labelAmount = (msg.value * labelShare) / 100;
        
        payable(artist).transfer(artistAmount);
        payable(label).transfer(labelAmount);
        
        emit RoyaltiesDistributed(artist, artistAmount);
        emit RoyaltiesDistributed(label, labelAmount);
    }
    
    // Owner can update shares or addresses
    function updateShares(uint _artistShare, uint _labelShare) external {
        require(msg.sender == owner, "Only owner");
        require(_artistShare + _labelShare == 100, "Shares must sum to 100");
        artistShare = _artistShare;
        labelShare = _labelShare;
    }
    
    // Owner withdraws any dust
    function withdraw() external {
        require(msg.sender == owner, "Only owner");
        payable(owner).transfer(address(this).balance);
    }
}
