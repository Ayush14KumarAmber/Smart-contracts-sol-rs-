x// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Crowdfunding is ReentrancyGuard {
    // Struct to represent a campaign
    struct Campaign {
        address creator;          // Address of the campaign creator
        uint256 goal;             // Funding goal in wei
        uint256 raised;           // Total funds raised in wei
        uint256 deadline;         // Timestamp when the campaign ends
        bool withdrawn;           // Flag to track if funds have been withdrawn
    }

    // Array to store all campaigns
    Campaign[] public campaigns;

    // Mapping to track individual contributions: campaignId => contributor => amount
    mapping(uint256 => mapping(address => uint256)) public contributions;

    // Events
    event CampaignCreated(uint256 indexed campaignId, address creator, uint256 goal, uint256 deadline);
    event ContributionMade(uint256 indexed campaignId, address contributor, uint256 amount);
    event FundsWithdrawn(uint256 indexed campaignId, address creator, uint256 amount);
    event RefundIssued(uint256 indexed campaignId, address contributor, uint256 amount);

    // Function to create a new campaign
    // Anyone can call this. Duration is in seconds.
    function createCampaign(uint256 _goal, uint256 _duration) external {
        require(_goal > 0, "Goal must be greater than 0");
        require(_duration > 0, "Duration must be greater than 0");

        uint256 deadline = block.timestamp + _duration;
        campaigns.push(Campaign({
            creator: msg.sender,
            goal: _goal,
            raised: 0,
            deadline: deadline,
            withdrawn: false
        }));

        emit CampaignCreated(campaigns.length - 1, msg.sender, _goal, deadline);
    }

    // Function to contribute ETH to a campaign
    // Only before deadline, and creator cannot contribute to own campaign.
    function contribute(uint256 _campaignId) external payable nonReentrant {
        require(_campaignId < campaigns.length, "Invalid campaign ID");
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp < campaign.deadline, "Campaign has ended");
        require(msg.sender != campaign.creator, "Creator cannot contribute to own campaign");
        require(msg.value > 0, "Contribution must be greater than 0");

        campaign.raised += msg.value;
        contributions[_campaignId][msg.sender] += msg.value;

        emit ContributionMade(_campaignId, msg.sender, msg.value);
    }

    // Function for creator to withdraw funds
    // Only if goal reached, deadline passed, and not already withdrawn.
    function withdraw(uint256 _campaignId) external nonReentrant {
        require(_campaignId < campaigns.length, "Invalid campaign ID");
        Campaign storage campaign = campaigns[_campaignId];
        require(msg.sender == campaign.creator, "Only creator can withdraw");
        require(block.timestamp >= campaign.deadline, "Campaign is still active");
        require(campaign.raised >= campaign.goal, "Goal not reached");
        require(!campaign.withdrawn, "Funds already withdrawn");

        campaign.withdrawn = true;
        uint256 amount = campaign.raised;
        payable(msg.sender).transfer(amount);

        emit FundsWithdrawn(_campaignId, msg.sender, amount);
    }

    // Function for contributors to refund
    // Only if goal not reached after deadline.
    function refund(uint256 _campaignId) external nonReentrant {
        require(_campaignId < campaigns.length, "Invalid campaign ID");
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp >= campaign.deadline, "Campaign is still active");
        require(campaign.raised < campaign.goal, "Goal was reached, no refunds");

        uint256 contributed = contributions[_campaignId][msg.sender];
        require(contributed > 0, "No contributions to refund");

        contributions[_campaignId][msg.sender] = 0;
        payable(msg.sender).transfer(contributed);

        emit RefundIssued(_campaignId, msg.sender, contributed);
    }

    // Helper function to get campaign count
    function getCampaignCount() external view returns (uint256) {
        return campaigns.length;
    }
}
