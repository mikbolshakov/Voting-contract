/*
контракт должен создавать объект голосования, принимая на вход массив адресов кандидатов.
голосований может быть много, по всем нужно иметь возможность посмотреть информацию.
голосование длится некоторое время.

пользователи могут голосовать за кандидата, переводя на контракт эфир.
по завершении голосования победитель может снять средства, 
которые были внесены в это голосование, за исключением комиссии площадки.
владелец площадки должен иметь возможность выводить комиссию.

покрыть контракт юнит-тестами;
создать task hardhat для каждой публичной функции;
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract VotingContract {
    enum Status {
        Empty,
        Created,
        Ongoing,
        Finished
    }

    struct Voting {
        address[] candidates;
        address[] voters;
        mapping(address => bool) isCandidate;
        mapping(address => uint256) numberOfVotes;
        mapping(address => address) voterChoices; // voter => candidate
        // mapping(address => bool) isWinner;
        Status votingStatus; // default Empty
        uint256 startsAt;
        uint256 endsAt;
        // uint256 fee;
        // uint256 totalAmount;
    }

    address payable owner;
    mapping(uint256 => Voting) public votings;
    // mapping(uint256 => address[]) public allWinnersMapper; // voting id => all winners
    uint256 private currentVotingId; // = 1;

    uint256 private constant VOTING_DURATION = 120;
    uint256 private constant CANDIDATE_ADD_DURATION = 120;
    // uint256 constant BASE_PAYMENT = 1000000;
    // uint256 constant BASE_FEE = 3; // in percents

    constructor() {
        owner = payable(msg.sender);
    }

    event VotingCreated(uint256 indexed votingId, uint256 startsAt);
    event VotingStarted(uint256 indexed votingId, uint256 endsAt);
    event VotingEnded(uint256 indexed votingId);
    event CandidateAdded(uint256 indexed votingId, address indexed candidate);
    event VotedForCandidate(uint256 indexed votingId, address indexed voter, address indexed candidate);

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not an owner");
        _;
    }

    function addVoting() external onlyOwner {
        votings[currentVotingId].startsAt =
            block.timestamp +
            CANDIDATE_ADD_DURATION;
        votings[currentVotingId].votingStatus = Status.Created;
        currentVotingId++;

        emit VotingCreated(currentVotingId, votings[currentVotingId].startsAt);
    }

    function addCandidate(uint256 _votingId) external {
        Voting storage currentVoting = votings[_votingId];

        require(
            currentVoting.votingStatus == Status.Created,
            "Voting is not created"
        );
        require(
            !currentVoting.isCandidate[msg.sender],
            "You are already a candidate"
        );
        require(
            currentVoting.startsAt > block.timestamp,
            "Voting has already started"
        );

        currentVoting.isCandidate[msg.sender] = true;
        currentVoting.candidates.push(msg.sender);

        emit CandidateAdded(_votingId, msg.sender);
    }

    function startVoting(uint256 _votingId) external onlyOwner {
        Voting storage currentVoting = votings[_votingId];

        require(
            currentVoting.startsAt <= block.timestamp,
            "Too early to start voting"
        );
        require(
            currentVoting.votingStatus == Status.Created,
            "There is no such vote"
        );
        require(
            currentVoting.candidates.length > 1,
            "No candidates for this vote"
        );

        currentVoting.votingStatus = Status.Ongoing;
        currentVoting.endsAt = block.timestamp + VOTING_DURATION;

        emit VotingStarted(_votingId, currentVoting.endsAt);
    }

    function voteForCandidate(
        uint256 _votingId,
        address _candidate
    ) external payable {
        Voting storage currentVoting = votings[_votingId];

        require(
            currentVoting.votingStatus == Status.Ongoing,
            "Voting is not going"
        );
        require(currentVoting.endsAt > block.timestamp, "Voting is over");
        require(
            currentVoting.isCandidate[_candidate],
            "This address is not candidate"
        );
        require(
            currentVoting.voterChoices[msg.sender] == address(0),
            "You have already voted"
        );
        // require(msg.value == BASE_PAYMENT, "Only fixed amount");

        // uint256 voteFee = msg.value * BASE_FEE / 100;
        // uint256 voteAmount = msg.value - voteFee;
        // currentVoting.totalAmount += voteAmount;
        // currentVoting.fee += voteFee;

        currentVoting.voterChoices[msg.sender] = _candidate;
        currentVoting.numberOfVotes[_candidate]++;
        currentVoting.voters.push(msg.sender);

        emit VotedForCandidate(_votingId, msg.sender, _candidate);
    }

    function endVoting(uint256 _votingId) external onlyOwner {
        Voting storage currentVoting = votings[_votingId];
        require(currentVoting.votingStatus == Status.Ongoing, "Voting is not going");
        require(currentVoting.endsAt <= block.timestamp, "Voting is not over");
        votings[_votingId].votingStatus = Status.Finished;

        emit VotingEnded(_votingId);
    }

    function checkWinners(uint256 _votingId) external view returns (address[] memory) {
        Voting storage currentVoting = votings[_votingId];

        require(
            currentVoting.votingStatus == Status.Finished,
            "Voting is not finished"
        );

        uint256 candidatesCount = currentVoting.candidates.length;
        uint256 winnersCount = 0;
        uint256 maximumVotes = 0;
        address[] memory localWinners = new address[](candidatesCount);

        for (uint256 i = 0; i < candidatesCount; i++) {
            address nextCandidate = currentVoting.candidates[i];

            if (currentVoting.numberOfVotes[nextCandidate] == maximumVotes) {
                winnersCount += 1;
                localWinners[winnersCount - 1] = nextCandidate;
                // currentVoting.isWinner[nextCandidate] = true;
            }

            if (currentVoting.numberOfVotes[nextCandidate] > maximumVotes) {
                maximumVotes = currentVoting.numberOfVotes[nextCandidate];
                winnersCount = 1;
                localWinners[0] = nextCandidate;
                // currentVoting.isWinner[nextCandidate] = true;
            }
        }

        address[] memory allWinners = new address[](winnersCount);

        for (uint256 i = 0; i < winnersCount; i++) {
            allWinners[i] = localWinners[i];
        }
        return allWinners;
        // return allWinnersMapper[_votingId] = allWinners;
    }

    function numberOfVotes(
        uint256 _votingId,
        address _candidate
    ) public view returns (uint256) {
        Voting storage currentVoting = votings[_votingId];
        return currentVoting.numberOfVotes[_candidate];
    }

    // function takeWinnersAmount(uint256 _votingId) external {
    //     Voting storage currentVoting = votings[_votingId];

    //     require(
    //         currentVoting.votingStatus == Status.Finished,
    //         "Voting not finished"
    //     );
    //     require(currentVoting.isWinner[msg.sender], "You don't have a prize");

    //     uint256 prize;
    //     if (allWinnersMapper[_votingId].length == 1) {
    //         prize = currentVoting.totalAmount;
    //         address payable winner = payable(msg.sender);
    //         winner.transfer(prize);
    //         currentVoting.isWinner[msg.sender] = false;
    //     } else {
    //         prize =
    //             currentVoting.totalAmount /
    //             allWinnersMapper[_votingId].length;
    //         address payable winner = payable(msg.sender);
    //         winner.transfer(prize);
    //         currentVoting.isWinner[msg.sender] = false;
    //     }
    // }

    // function takeOwnersFee(uint256 _votingId) external onlyOwner {
    //     Voting storage currentVoting = votings[_votingId];

    //     require(
    //         currentVoting.votingStatus == Status.Finished,
    //         "Voting not finished"
    //     );
    //     require(currentVoting.fee > 0, "Fee is already taken");

    //     owner.transfer(currentVoting.fee);
    //     currentVoting.fee = 0;
    // }

    fallback() external payable {}

    receive() external payable {}
}
