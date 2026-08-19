// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title AdvancedVoting
 * @notice Production-oriented on-chain voting system with:
 *
 * - Multiple proposals
 * - Registration phase
 * - Time-boxed voting
 * - Delegation with transitive voting power
 * - Delegation cycle prevention
 * - Quadratic voting
 * - Quorum
 * - Participation tracking
 * - Vote receipts
 * - Emergency pause
 * - Permissionless finalization
 * - Cancellation
 * - Batch voter registration
 * - Custom errors
 *
 * Delegation model:
 *
 * A voter has a base voting power of 1.
 *
 * If:
 *
 * Alice -> Bob
 * Bob   -> Charlie
 *
 * Charlie receives Alice + Bob's voting power.
 *
 * A voter who has delegated cannot vote directly.
 *
 * Voting power is maintained as subtree weight, avoiding
 * an O(n) scan through every registered voter when voting.
 */
contract AdvancedVoting is Ownable, ReentrancyGuard, Pausable {
    using Math for uint256;

    // =============================================================
    //                            TYPES
    // =============================================================

    struct Proposal {
        string description;
        uint256 votes;
        uint256 quadraticVotes;
        address proposer;
        bool active;
    }

    enum Phase {
        Created,
        Registration,
        Voting,
        Ended,
        Cancelled
    }

    struct VoteReceipt {
        bool hasVoted;
        uint256 proposalId;
        uint256 rawWeight;
        uint256 appliedWeight;
        uint256 timestamp;
    }

    // =============================================================
    //                            ERRORS
    // =============================================================

    error InvalidPhase();
    error InvalidProposal();
    error InvalidTimes();
    error InsufficientProposals();
    error NoRegisteredVoters();
    error NotRegistered();
    error AlreadyRegistered();
    error AlreadyVoted();
    error DelegatedVoterCannotVote();
    error InvalidDelegate();
    error SelfDelegation();
    error DelegationCycle();
    error NoDelegation();
    error VotingClosed();
    error VotingNotStarted();
    error QuorumNotMet();
    error PollAlreadyFinalized();
    error PollCancelled();
    error InvalidQuorum();
    error InvalidBatchSize();
    error ZeroAddress();
    error EmptyDescription();

    // =============================================================
    //                            EVENTS
    // =============================================================

    event VoterRegistered(address indexed voter);

    event VotersRegistered(
        uint256 indexed count
    );

    event Delegated(
        address indexed from,
        address indexed to,
        uint256 votingPower
    );

    event Undelegated(
        address indexed from,
        address indexed previousDelegate,
        uint256 votingPower
    );

    event Voted(
        address indexed voter,
        uint256 indexed proposalId,
        uint256 rawWeight,
        uint256 appliedWeight,
        bool quadratic
    );

    event ProposalAdded(
        uint256 indexed proposalId,
        string description,
        address indexed proposer
    );

    event PhaseChanged(
        Phase indexed previousPhase,
        Phase indexed newPhase
    );

    event PollFinalized(
        uint256 indexed winningProposal,
        uint256 winningVotes,
        bool quorumReached
    );

    event PollCancelled();

    event QuorumUpdated(
        uint256 previousQuorumBps,
        uint256 newQuorumBps
    );

    // =============================================================
    //                         GOVERNANCE
    // =============================================================

    Phase public phase;

    bool public immutable quadratic;

    uint256 public immutable startTime;
    uint256 public immutable endTime;

    /**
     * @notice Quorum expressed in basis points.
     *
     * 5000 = 50%
     * 2500 = 25%
     * 10000 = 100%
     */
    uint256 public quorumBps;

    // =============================================================
    //                           PROPOSALS
    // =============================================================

    Proposal[] public proposals;

    // =============================================================
    //                            VOTERS
    // =============================================================

    mapping(address => bool) public isRegistered;

    /**
     * @notice Base voting power.
     *
     * Currently every registered voter receives 1.
     *
     * Kept as a mapping so future versions can support
     * token-based or reputation-based voting power.
     */
    mapping(address => uint256) public baseVotingPower;

    /**
     * @notice Total voting power controlled by a voter
     * and all voters delegating to them.
     *
     * Example:
     *
     * Alice -> Bob
     * Bob   -> Charlie
     *
     * Charlie's subtreeWeight contains Alice + Bob + Charlie.
     */
    mapping(address => uint256) public subtreeWeight;

    /**
     * @notice voter => delegate.
     *
     * address(0) means the voter currently controls their
     * own voting power.
     */
    mapping(address => address) public delegateOf;

    uint256 public registeredCount;

    // =============================================================
    //                         VOTING STATE
    // =============================================================

    mapping(address => VoteReceipt) public voteReceipt;

    uint256 public votersParticipated;

    /**
     * @notice Sum of raw voting weight that participated.
     *
     * This is used for quorum.
     */
    uint256 public participatingWeight;

    bool public finalized;

    uint256 public winningProposal;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        string[] memory _descriptions,
        bool _quadratic,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _quorumBps,
        address _owner
    ) Ownable(_owner) {
        if (_owner == address(0)) {
            revert ZeroAddress();
        }

        if (_descriptions.length < 2) {
            revert InsufficientProposals();
        }

        if (
            _endTime <= _startTime ||
            _endTime <= block.timestamp
        ) {
            revert InvalidTimes();
        }

        if (_quorumBps > 10_000) {
            revert InvalidQuorum();
        }

        quadratic = _quadratic;
        startTime = _startTime;
        endTime = _endTime;
        quorumBps = _quorumBps;

        phase = Phase.Created;

        for (uint256 i = 0; i < _descriptions.length; i++) {
            if (bytes(_descriptions[i]).length == 0) {
                revert EmptyDescription();
            }

            proposals.push(
                Proposal({
                    description: _descriptions[i],
                    votes: 0,
                    quadraticVotes: 0,
                    proposer: _owner,
                    active: true
                })
            );

            emit ProposalAdded(
                i,
                _descriptions[i],
                _owner
            );
        }
    }

    // =============================================================
    //                       ADMIN CONTROLS
    // =============================================================

    /**
     * @notice Begin voter registration.
     */
    function startRegistration()
        external
        onlyOwner
        whenNotPaused
    {
        if (phase != Phase.Created) {
            revert InvalidPhase();
        }

        Phase previous = phase;

        phase = Phase.Registration;

        emit PhaseChanged(previous, phase);
    }

    /**
     * @notice Start the voting phase.
     */
    function startVoting()
        external
        onlyOwner
        whenNotPaused
    {
        if (phase != Phase.Registration) {
            revert InvalidPhase();
        }

        if (block.timestamp < startTime) {
            revert VotingNotStarted();
        }

        if (registeredCount == 0) {
            revert NoRegisteredVoters();
        }

        Phase previous = phase;

        phase = Phase.Voting;

        emit PhaseChanged(previous, phase);
    }

    /**
     * @notice Finalize after the voting deadline.
     *
     * Anyone can call this.
     */
    function finalize()
        external
        whenNotPaused
    {
        if (phase != Phase.Voting) {
            revert InvalidPhase();
        }

        if (block.timestamp < endTime) {
            revert VotingNotStarted();
        }

        _finalize();
    }

    /**
     * @notice Owner emergency cancellation.
     */
    function cancelPoll()
        external
        onlyOwner
    {
        if (
            phase == Phase.Ended ||
            phase == Phase.Cancelled
        ) {
            revert PollAlreadyFinalized();
        }

        Phase previous = phase;

        phase = Phase.Cancelled;

        emit PhaseChanged(previous, phase);
        emit PollCancelled();
    }

    /**
     * @notice Emergency pause.
     */
    function pause()
        external
        onlyOwner
    {
        _pause();
    }

    /**
     * @notice Resume normal operation.
     */
    function unpause()
        external
        onlyOwner
    {
        _unpause();
    }

    /**
     * @notice Update quorum before voting starts.
     */
    function setQuorum(uint256 newQuorumBps)
        external
        onlyOwner
    {
        if (phase != Phase.Created && phase != Phase.Registration) {
            revert InvalidPhase();
        }

        if (newQuorumBps > 10_000) {
            revert InvalidQuorum();
        }

        uint256 previous = quorumBps;

        quorumBps = newQuorumBps;

        emit QuorumUpdated(
            previous,
            newQuorumBps
        );
    }

    // =============================================================
    //                        REGISTRATION
    // =============================================================

    /**
     * @notice Register one voter.
     */
    function registerVoter(address voter)
        external
        onlyOwner
        whenNotPaused
    {
        if (phase != Phase.Registration) {
            revert InvalidPhase();
        }

        if (voter == address(0)) {
            revert ZeroAddress();
        }

        if (isRegistered[voter]) {
            revert AlreadyRegistered();
        }

        _register(voter);
    }

    /**
     * @notice Register many voters in one transaction.
     */
    function registerVoters(address[] calldata voters)
        external
        onlyOwner
        whenNotPaused
    {
        if (phase != Phase.Registration) {
            revert InvalidPhase();
        }

        if (voters.length == 0) {
            revert InvalidBatchSize();
        }

        uint256 registered;

        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];

            if (voter == address(0)) {
                continue;
            }

            if (isRegistered[voter]) {
                continue;
            }

            _register(voter);

            registered++;
        }

        emit VotersRegistered(registered);
    }

    function _register(address voter) internal {
        isRegistered[voter] = true;

        baseVotingPower[voter] = 1;

        subtreeWeight[voter] = 1;

        registeredCount++;

        emit VoterRegistered(voter);
    }

    // =============================================================
    //                         DELEGATION
    // =============================================================

    /**
     * @notice Delegate all voting power controlled by msg.sender.
     *
     * Delegation is transitive.
     *
     * Example:
     *
     * Alice -> Bob
     * Bob -> Charlie
     *
     * Charlie ultimately controls Alice + Bob + Charlie.
     */
    function delegate(address to)
        external
        whenNotPaused
    {
        if (phase != Phase.Voting) {
            revert InvalidPhase();
        }

        if (
            block.timestamp < startTime ||
            block.timestamp > endTime
        ) {
            revert VotingClosed();
        }

        if (!isRegistered[msg.sender]) {
            revert NotRegistered();
        }

        if (!isRegistered[to]) {
            revert InvalidDelegate();
        }

        if (to == msg.sender) {
            revert SelfDelegation();
        }

        address previous = delegateOf[msg.sender];

        if (previous == to) {
            return;
        }

        /**
         * Prevent:
         *
         * A -> B -> C -> A
         */
        address cursor = to;

        while (cursor != address(0)) {
            if (cursor == msg.sender) {
                revert DelegationCycle();
            }

            cursor = delegateOf[cursor];
        }

        uint256 weight = subtreeWeight[msg.sender];

        /**
         * Remove the subtree from the old ancestor chain.
         */
        if (previous != address(0)) {
            _updateAncestors(
                previous,
                weight,
                false
            );
        }

        delegateOf[msg.sender] = to;

        /**
         * Add the subtree to the new ancestor chain.
         */
        _updateAncestors(
            to,
            weight,
            true
        );

        emit Delegated(
            msg.sender,
            to,
            weight
        );
    }

    /**
     * @notice Remove an existing delegation.
     */
    function undelegate()
        external
        whenNotPaused
    {
        if (phase != Phase.Voting) {
            revert InvalidPhase();
        }

        address previous = delegateOf[msg.sender];

        if (previous == address(0)) {
            revert NoDelegation();
        }

        uint256 weight = subtreeWeight[msg.sender];

        _updateAncestors(
            previous,
            weight,
            false
        );

        delegateOf[msg.sender] = address(0);

        emit Undelegated(
            msg.sender,
            previous,
            weight
        );
    }

    /**
     * @dev Add/remove an entire subtree's voting power
     * from the ancestor chain.
     */
    function _updateAncestors(
        address start,
        uint256 amount,
        bool add
    ) internal {
        address cursor = start;

        while (cursor != address(0)) {
            if (add) {
                subtreeWeight[cursor] += amount;
            } else {
                subtreeWeight[cursor] -= amount;
            }

            cursor = delegateOf[cursor];
        }
    }

    // =============================================================
    //                            VOTING
    // =============================================================

    /**
     * @notice Vote for one proposal.
     *
     * A delegated voter cannot vote directly.
     *
     * Their voting power is controlled by their final delegate.
     */
    function vote(uint256 proposalId)
        external
        nonReentrant
        whenNotPaused
    {
        if (phase != Phase.Voting) {
            revert InvalidPhase();
        }

        if (
            block.timestamp < startTime ||
            block.timestamp > endTime
        ) {
            revert VotingClosed();
        }

        if (!isRegistered[msg.sender]) {
            revert NotRegistered();
        }

        if (delegateOf[msg.sender] != address(0)) {
            revert DelegatedVoterCannotVote();
        }

        if (voteReceipt[msg.sender].hasVoted) {
            revert AlreadyVoted();
        }

        if (proposalId >= proposals.length) {
            revert InvalidProposal();
        }

        Proposal storage proposal = proposals[proposalId];

        if (!proposal.active) {
            revert InvalidProposal();
        }

        uint256 rawWeight = subtreeWeight[msg.sender];

        if (rawWeight == 0) {
            revert NotRegistered();
        }

        uint256 appliedWeight;

        if (quadratic) {
            appliedWeight = rawWeight.sqrt();
        } else {
            appliedWeight = rawWeight;
        }

        proposal.votes += appliedWeight;

        if (quadratic) {
            proposal.quadraticVotes += appliedWeight;
        }

        voteReceipt[msg.sender] = VoteReceipt({
            hasVoted: true,
            proposalId: proposalId,
            rawWeight: rawWeight,
            appliedWeight: appliedWeight,
            timestamp: block.timestamp
        });

        votersParticipated++;
        participatingWeight += rawWeight;

        emit Voted(
            msg.sender,
            proposalId,
            rawWeight,
            appliedWeight,
            quadratic
        );
    }

    // =============================================================
    //                         FINALIZATION
    // =============================================================

    function _finalize() internal {
        if (finalized) {
            revert PollAlreadyFinalized();
        }

        finalized = true;

        bool quorumReached = quorumReached();

        /**
         * If quorum isn't reached, the poll still ends,
         * but no valid winner is declared.
         */
        if (!quorumReached) {
            Phase previous = phase;

            phase = Phase.Ended;

            emit PhaseChanged(
                previous,
                phase
            );

            emit PollFinalized(
                type(uint256).max,
                0,
                false
            );

            return;
        }

        uint256 highestVotes;
        uint256 winner;

        for (
            uint256 i = 0;
            i < proposals.length;
            i++
        ) {
            if (
                proposals[i].active &&
                proposals[i].votes > highestVotes
            ) {
                highestVotes = proposals[i].votes;
                winner = i;
            }
        }

        winningProposal = winner;

        Phase previous = phase;

        phase = Phase.Ended;

        emit PhaseChanged(
            previous,
            phase
        );

        emit PollFinalized(
            winner,
            highestVotes,
            true
        );
    }

    // =============================================================
    //                           VIEWS
    // =============================================================

    /**
     * @notice Return total number of proposals.
     */
    function proposalCount()
        external
        view
        returns (uint256)
    {
        return proposals.length;
    }

    /**
     * @notice Return proposal information.
     */
    function getProposal(uint256 id)
        external
        view
        returns (
            string memory description,
            uint256 votes,
            uint256 quadraticVotes,
            address proposer,
            bool active
        )
    {
        if (id >= proposals.length) {
            revert InvalidProposal();
        }

        Proposal storage proposal = proposals[id];

        return (
            proposal.description,
            proposal.votes,
            proposal.quadraticVotes,
            proposal.proposer,
            proposal.active
        );
    }

    /**
     * @notice Return voting power currently controlled
     * by a voter.
     */
    function getVotingPower(address voter)
        external
        view
        returns (uint256)
    {
        if (!isRegistered[voter]) {
            return 0;
        }

        return subtreeWeight[voter];
    }

    /**
     * @notice Returns the final delegate/root controlling
     * a voter's voting power.
     */
    function getDelegateRoot(address voter)
        public
        view
        returns (address)
    {
        if (!isRegistered[voter]) {
            return address(0);
        }

        address cursor = voter;

        while (delegateOf[cursor] != address(0)) {
            cursor = delegateOf[cursor];
        }

        return cursor;
    }

    /**
     * @notice Check whether quorum has been reached.
     *
     * Example:
     *
     * registeredCount = 100
     * quorumBps = 5000
     *
     * Required participation = 50 voters worth of weight.
     */
    function quorumReached()
        public
        view
        returns (bool)
    {
        if (registeredCount == 0) {
            return false;
        }

        uint256 requiredWeight =
            (registeredCount * quorumBps) / 10_000;

        return participatingWeight >= requiredWeight;
    }

    /**
     * @notice Return quorum percentage in basis points.
     */
    function quorumPercentage()
        external
        view
        returns (uint256)
    {
        return quorumBps;
    }

    /**
     * @notice Return current leader.
     *
     * Can be called before finalization.
     */
    function currentLeader()
        external
        view
        returns (
            uint256 proposalId,
            string memory description,
            uint256 votes
        )
    {
        uint256 highestVotes;

        for (
            uint256 i = 0;
            i < proposals.length;
            i++
        ) {
            if (
                proposals[i].active &&
                proposals[i].votes > highestVotes
            ) {
                highestVotes = proposals[i].votes;
                proposalId = i;
            }
        }

        Proposal storage proposal = proposals[proposalId];

        return (
            proposalId,
            proposal.description,
            proposal.votes
        );
    }

