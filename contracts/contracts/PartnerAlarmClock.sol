// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./BaseCommitment.sol";
import "./library/AlarmSchedule.sol";
import {ISocialAlarmClockHub} from "./interfaces/ISocialAlarmClockHub.sol";

/**
 * The partner alarm clock is a commitment contract that allows two people to set an 'alarm'
 * together, which represents an agreement for both parties to wake up at the same time on the
 * designated days. To verify that each party has woken up, they simply need to submit a
 * confirmation transaction before the alarm time. Failure to do so can result in a penalty
 * that will transfer funds to the other party.
 */
contract PartnerAlarmClock is BaseCommitment {
    string constant IMPLEMENTATION_NAME = "Partner Alarm Clock";
    ISocialAlarmClockHub deploymentHub;

    using AlarmSchedule for AlarmSchedule.Schedule;

    struct Player {
        AlarmSchedule.Schedule schedule;
        uint depositAmount;
    }

    mapping(address => Player) players;

    uint public alarmTime;
    uint8[] public alarmActiveDays;
    uint public submissionWindow;
    int public timezoneOffset;
    uint public betAmount;
    address public player1;
    address public player2;
    uint public missedAlarmPenalty;

    function init(
        bytes calldata data
    ) public payable virtual override initializer {
        require(msg.value > 0, "BET_VALUE_REQUIRED");
        deploymentHub = ISocialAlarmClockHub(msg.sender);

        // Initialize to an inactive state, commitment becomes activated once player 2 starts
        status = CommitmentStatus.INACTIVE;
        name = IMPLEMENTATION_NAME;
        betAmount = msg.value;
        player1 = tx.origin;

        (
            alarmTime,
            alarmActiveDays,
            missedAlarmPenalty,
            submissionWindow,
            timezoneOffset,
            player2
        ) = abi.decode(data, (uint, uint8[], uint, uint, int, address));

        players[player1].depositAmount = msg.value;
        players[player1].schedule = AlarmSchedule.init(
            alarmTime,
            alarmActiveDays,
            submissionWindow,
            timezoneOffset
        );

        players[player2].schedule = AlarmSchedule.init(
            alarmTime,
            alarmActiveDays,
            submissionWindow,
            timezoneOffset
        );
    }

    modifier onlyPlayer() {
        require(
            msg.sender == player1 || msg.sender == player2,
            "ONLY_PLAYER_ACTION"
        );
        _;
    }

    /**
     * Only player2 can start the alarm
     */
    function start() public payable {
        require(status == CommitmentStatus.INACTIVE, "ALREADY_STARTED");
        require(msg.value >= betAmount, "INSUFFICIENT_FUNDS_SENT");
        require(msg.sender == player2, "ONLY_PLAYER_2_CAN_START");

        players[player1].schedule.start();
        players[player2].schedule.start();
        players[player2].depositAmount += msg.value;

        deploymentHub.emitUserJoined(
            RegisteredAlarmType.PARTNER_ALARM_CLOCK,
            player2
        );

        status = CommitmentStatus.ACTIVE;
        emit CommitmentInitialized("Alarm Bet Started");
    }

    function addToBalance(address player) public payable onlyPlayer {
        require(status == CommitmentStatus.ACTIVE, "NOT_ACTIVE");
        require(player == player1 || player == player2, "INVALID_PLAYER");
        players[msg.sender].depositAmount += msg.value;
    }

    /**
     * Allow either player to 'confirm' a wakeup. Wakeups must be submitted within
     * the submission window on an alarm day for the entry to be recorded
     */
    function submitConfirmation() public override onlyPlayer {
        players[msg.sender].schedule.recordEntry();
        emit ConfirmationSubmitted(msg.sender);
    }

    function missedDeadlines(address player) public view returns (uint) {
        return players[player].schedule.missedDeadlines();
    }

    function numConfirmations(address player) public view returns (uint) {
        return players[player].schedule.entries();
    }

    function timeToNextDeadline(address player) public view returns (uint) {
        return players[player].schedule.timeToNextDeadline();
    }

    function alarmDays() public view returns (uint8[] memory) {
        return alarmActiveDays;
    }

    // Ends the alarm and withdraws funds for both players with penalties/earnings applied
    function withdraw() public onlyPlayer {
        address otherPlayer = msg.sender == player1 ? player2 : player1;

        uint senderPenalty = 0;
        uint otherPlayerPenalty = 0;
        if (status == CommitmentStatus.ACTIVE) {
            senderPenalty = getPenaltyAmount(msg.sender);
            otherPlayerPenalty = getPenaltyAmount(otherPlayer);
        }

        uint otherPlayerWithdrawAmount = players[otherPlayer].depositAmount +
            senderPenalty -
            otherPlayerPenalty;

        players[msg.sender].depositAmount = 0;
        players[otherPlayer].depositAmount = 0;

        payable(otherPlayer).transfer(otherPlayerWithdrawAmount);
        payable(msg.sender).transfer(address(this).balance);

        emit StatusChanged(status, CommitmentStatus.CANCELLED);
        status = CommitmentStatus.CANCELLED;
    }

    function getPlayerBalance(address player) public view returns (uint) {
        return players[player].depositAmount - getPenaltyAmount(player);
    }

    function getPenaltyAmount(address player) public view returns (uint) {
        uint numMissedDeadlines = players[player].schedule.missedDeadlines();
        uint penaltyVal = numMissedDeadlines * missedAlarmPenalty;
        if (penaltyVal > players[player].depositAmount) {
            return players[player].depositAmount;
        }
        return penaltyVal;
    }
}
