// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title SecureOwnable
 * @notice Hardened two-step ownership management.
 *
 * Security features:
 * - Solidity 0.8+ checked arithmetic
 * - Two-step ownership transfer
 * - Zero-address protection
 * - Pending owner protection
 * - Cancelable ownership transfer
 * - Delayed ownership renunciation
 * - Cancelable renunciation
 * - Custom errors for lower gas usage
 * - Explicit ownership events
 * - No external calls during ownership transitions
 */
abstract contract SecureOwnable {
    // =============================================================
    //                           ERRORS
    // =============================================================

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    error OwnableInvalidPendingOwner(address pendingOwner);
    error NoPendingOwnershipTransfer();
    error NotPendingOwner();
    error RenounceAlreadyScheduled();
    error NoRenounceScheduled();
    error RenounceDelayNotPassed();
    error OwnershipTransferInProgress();

    // =============================================================
    //                           EVENTS
    // =============================================================

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    event OwnershipTransferStarted(
        address indexed previousOwner,
        address indexed pendingOwner
    );

    event OwnershipTransferCancelled(
        address indexed previousOwner,
        address indexed cancelledOwner
    );

    event OwnershipRenounceScheduled(
        address indexed owner,
        uint256 executeAfter
    );

    event OwnershipRenounceCancelled(
        address indexed owner
    );

    // =============================================================
    //                         CONSTANTS
    // =============================================================

    /**
     * @notice Minimum delay before ownership can be permanently
     * renounced.
     *
     * 2 days = 172800 seconds.
     */
    uint256 public constant RENOUNCE_DELAY = 2 days;

    // =============================================================
    //                           STORAGE
    // =============================================================

    address private _owner;

    /**
     * @notice Address that will become owner after accepting
     * the ownership transfer.
     */
    address private _pendingOwner;

    /**
     * @notice Timestamp after which renunciation can be executed.
     *
     * 0 means no renunciation is scheduled.
     */
    uint256 private _renounceExecuteAfter;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    /**
     * @dev Sets the initial owner.
     *
     * msg.sender becomes owner.
     */
    constructor() {
        _transferOwnership(msg.sender);
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    /**
     * @dev Restricts function access to current owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Restricts function access to pending owner.
     */
    modifier onlyPendingOwner() {
        if (msg.sender != _pendingOwner) {
            revert NotPendingOwner();
        }
        _;
    }

    // =============================================================
    //                         VIEW FUNCTIONS
    // =============================================================

    /**
     * @notice Returns current owner.
     */
    function owner()
        public
        view
        returns (address)
    {
        return _owner;
    }

    /**
     * @notice Returns pending owner.
     *
     * address(0) means no ownership transfer is pending.
     */
    function pendingOwner()
        public
        view
        returns (address)
    {
        return _pendingOwner;
    }

    /**
     * @notice Returns whether an address is the current owner.
     */
    function isOwner(address account)
        public
        view
        returns (bool)
    {
        return account == _owner;
    }

    /**
     * @notice Returns whether an ownership transfer is pending.
     */
    function ownershipTransferPending()
        public
        view
        returns (bool)
    {
        return _pendingOwner != address(0);
    }

    /**
     * @notice Returns whether ownership renunciation is scheduled.
     */
    function renounceScheduled()
        public
        view
        returns (bool)
    {
        return _renounceExecuteAfter != 0;
    }

    /**
     * @notice Returns the timestamp at which ownership
     * renunciation can be executed.
     */
    function renounceExecuteAfter()
        public
        view
        returns (uint256)
    {
        return _renounceExecuteAfter;
    }

    // =============================================================
    //                      OWNERSHIP TRANSFER
    // =============================================================

    /**
     * @notice Starts a two-step ownership transfer.
     *
     * IMPORTANT:
     * This function does NOT immediately transfer ownership.
     *
     * The new owner must call acceptOwnership().
     *
     * This protects against accidentally sending ownership
     * to the wrong address.
     */
    function transferOwnership(address newOwner)
        public
        onlyOwner
    {
        if (newOwner == address(0)) {
            revert OwnableInvalidPendingOwner(newOwner);
        }

        if (newOwner == _owner) {
            revert OwnableInvalidPendingOwner(newOwner);
        }

        _pendingOwner = newOwner;

        emit OwnershipTransferStarted(
            _owner,
            newOwner
        );
    }

    /**
     * @notice Pending owner accepts ownership.
     *
     * Only the address specified in transferOwnership()
     * can call this function.
     */
    function acceptOwnership()
        public
        onlyPendingOwner
    {
        address previousOwner = _owner;
        address newOwner = _pendingOwner;

        _pendingOwner = address(0);

        _transferOwnership(newOwner);

        emit OwnershipTransferred(
            previousOwner,
            newOwner
        );
    }

    /**
     * @notice Cancels a pending ownership transfer.
     *
     * Only the current owner can cancel it.
     */
    function cancelOwnershipTransfer()
        public
        onlyOwner
    {
        address cancelledOwner = _pendingOwner;

        if (cancelledOwner == address(0)) {
            revert NoPendingOwnershipTransfer();
        }

        _pendingOwner = address(0);

        emit OwnershipTransferCancelled(
            _owner,
            cancelledOwner
        );
    }

    // =============================================================
    //                    OWNERSHIP RENUNCIATION
    // =============================================================

    /**
     * @notice Schedules ownership renunciation.
     *
     * Ownership is NOT renounced immediately.
     *
     * The owner must wait RENOUNCE_DELAY before calling
     * executeRenounceOwnership().
     */
    function renounceOwnership()
        public
        onlyOwner
    {
        if (_renounceExecuteAfter != 0) {
            revert RenounceAlreadyScheduled();
        }

        if (_pendingOwner != address(0)) {
            revert OwnershipTransferInProgress();
        }

        uint256 executeAfter =
            block.timestamp + RENOUNCE_DELAY;

        _renounceExecuteAfter = executeAfter;

        emit OwnershipRenounceScheduled(
            _owner,
            executeAfter
        );
    }

    /**
     * @notice Permanently renounces ownership after the
     * mandatory delay.
     */
    function executeRenounceOwnership()
        public
        onlyOwner
    {
        uint256 executeAfter = _renounceExecuteAfter;

        if (executeAfter == 0) {
            revert NoRenounceScheduled();
        }

        if (block.timestamp < executeAfter) {
            revert RenounceDelayNotPassed();
        }

        address previousOwner = _owner;

        _renounceExecuteAfter = 0;
        _pendingOwner = address(0);
        _owner = address(0);

        emit OwnershipTransferred(
            previousOwner,
            address(0)
        );
    }

    /**
     * @notice Cancels a scheduled ownership renunciation.
     */
    function cancelRenounceOwnership()
        public
        onlyOwner
    {
        if (_renounceExecuteAfter == 0) {
            revert NoRenounceScheduled();
        }

        _renounceExecuteAfter = 0;

        emit OwnershipRenounceCancelled(
            _owner
        );
    }

    // =============================================================
    //                       INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Checks whether msg.sender is the owner.
     */
    function _checkOwner()
        internal
        view
    {
        if (msg.sender != _owner) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @dev Internal ownership assignment.
     */
    function _transferOwnership(address newOwner)
        internal
    {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(newOwner);
        }

        _owner = newOwner;
    }
}
