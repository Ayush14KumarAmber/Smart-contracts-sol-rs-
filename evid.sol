// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title EvidenceNotary
 * @dev Stores evidence hashes to prove existence and integrity at a specific time.
 */
contract EvidenceNotary {
    struct Evidence {
        bytes32 evidenceHash;
        address submitter;
        uint256 blockTimestamp;
    }

    // Mapping from hash to Evidence record
    mapping(bytes32 => Evidence) public evidenceRegistry;

    // Event emitted when new evidence is registered
    event EvidenceRegistered(bytes32 indexed evidenceHash, address indexed submitter, uint256 timestamp);

    /**
     * @dev Registers a new evidence hash. Reverts if already exists.
     * @param _evidenceHash The SHA-256 (or Keccak-256) hash of the evidence.
     */
    function registerEvidence(bytes32 _evidenceHash) public {
        // Prevent duplicate registration
        require(evidenceRegistry[_evidenceHash].blockTimestamp == 0, "Evidence already registered.");

        evidenceRegistry[_evidenceHash] = Evidence({
            evidenceHash: _evidenceHash,
            submitter: msg.sender,
            blockTimestamp: block.timestamp
        });

        emit EvidenceRegistered(_evidenceHash, msg.sender, block.timestamp);
    }

    /**
     * @dev Verifies if a hash exists and returns its metadata.
     * @param _evidenceHash The hash to verify.
     * @return exists Boolean indicating existence.
     * @return submitter Address of the submitter.
     * @return timestamp Block timestamp of registration.
     */
    function verifyEvidence(bytes32 _evidenceHash) public view returns (bool exists, address submitter, uint256 timestamp) {
        if (evidenceRegistry[_evidenceHash].blockTimestamp == 0) {
            return (false, address(0), 0);
        }
        Evidence memory e = evidenceRegistry[_evidenceHash];
        return (true, e.submitter, e.blockTimestamp);
    }
}
**contract EvidenceNotary {
  **  struct Evidence {
  **      bytes32 evidenceHash;
    **    address submitter;
      **  uint256 blockTimestamp;
   ** }
