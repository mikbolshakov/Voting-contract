/*
контракт должен создавать объект голосования, принимая на вход массив адресов кандидатов.
голосований может быть много, по всем нужно иметь возможность посмотреть информацию.
голосование длится некоторое время.

пользователи могут голосовать за кандидата, переводя на контракт эфир.
по завершении голосования победитель может снять средства, которые были внесены в это голосование, за исключением комиссии площадки.
владелец площадки должен иметь возможность выводить комиссию.

покрыть контракт юнит-тестами;
создать task hardhat для каждой публичной функции;
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract VotingContract {
    enum Status {
        Created,
        Ongoing,
        Finished
    }

    struct Voting {
        address[] candidates;
        mapping(address => bool) isCandidate;
        mapping(address => uint) numberOfVotes;
        address[] voters;
        mapping(address => address) voterChoices; // voter => candidate
        Status votingStatus;
        uint startsAt;
        uint endsAt;
        uint fee;
        uint totalAmount;
    }

    address payable owner;
    mapping(uint => Voting) public votings;
    mapping(uint => address[]) public allWinnersMapper; // voting id => all winners
    uint currentVotingId = 1;

    uint private constant VOTING_DURATION = 120;
    uint private constant CANDIDATE_ADD_DURATION = 120;
    uint constant BASE_PAYMENT = 1000000;
    uint constant BASE_FEE = 3; // in percents

    constructor() {
      owner = payable(msg.sender);
    }

    event VotingCreated(uint indexed votingId, uint startsAt);
    event VotingStarted(uint indexed votingId, uint endsAt);
    event VotingEnded(uint indexed votingId);

    modifier onlyOwner {
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

    function addCandidate(uint _votingId) external {
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
    }

    function startVoting(uint _votingId) external onlyOwner {
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
            currentVoting.candidates.length >= 2,
            "No candidates for this vote"
        );

        currentVoting.votingStatus = Status.Ongoing;
        currentVoting.endsAt = block.timestamp + VOTING_DURATION;

        emit VotingStarted(_votingId, currentVoting.endsAt);
    }

    function voteForCandidate(uint _votingId, address _candidate) external payable {
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
        require(msg.value == BASE_PAYMENT, "Only fixed amount");

        uint voteFee = msg.value * BASE_FEE / 100;
        uint voteAmount = msg.value - voteFee;
        currentVoting.totalAmount += voteAmount;
        currentVoting.fee += voteFee;

        currentVoting.voterChoices[msg.sender] = _candidate;
        currentVoting.voters.push(msg.sender);
        currentVoting.numberOfVotes[_candidate]++;
    }

    function endVoting(uint _votingId) external {
        Voting storage currentVoting = votings[_votingId];
        require(currentVoting.votingStatus == Status.Ongoing);
        require(currentVoting.endsAt <= block.timestamp);
        votings[_votingId].votingStatus = Status.Finished;

        emit VotingEnded(_votingId);
    }

    function winners(uint _votingId) external returns (address[] memory) {
        Voting storage currentVoting = votings[_votingId];

        uint candidatesCount = currentVoting.candidates.length;
        uint winnersCount;
        uint maximumVotes;
        address[] memory localWinners = new address[](candidatesCount);

        for (uint i = 0; i < candidatesCount; i++) {
            address nextCandidate = currentVoting.candidates[i];

            if (currentVoting.numberOfVotes[nextCandidate] == maximumVotes) {
                winnersCount += 1;
                localWinners[winnersCount - 1] = nextCandidate;
            }

            if (currentVoting.numberOfVotes[nextCandidate] > maximumVotes) {
                maximumVotes = currentVoting.numberOfVotes[nextCandidate];
                winnersCount = 1;
                localWinners[0] = nextCandidate;
            }
        }

        address[] memory allWinners = new address[](winnersCount);

        for (uint i = 0; i < winnersCount; i++) {
            allWinners[i] = localWinners[i];
        }

        return allWinnersMapper[_votingId] = allWinners;
    }

    function numberOfVotes(
        uint _votingId,
        address _candidate
    ) public view returns (uint) {
        Voting storage currentVoting = votings[_votingId];
        return currentVoting.numberOfVotes[_candidate];
    }

    function takeWinnersAmount(uint _votingId) external {
      Voting storage currentVoting = votings[_votingId];

      require(allWinnersMapper[_votingId].length > 0, "Can't find any winners");
      require(currentVoting.totalAmount > 0, "Prize money is already taken");
      require(currentVoting.votingStatus == Status.Finished, "Voting not finished");

      uint prize;
      if(allWinnersMapper[_votingId].length == 1) {
        prize = currentVoting.totalAmount;
      } else {
        prize = currentVoting.totalAmount / allWinnersMapper[_votingId].length;
      }
      address payable winner = payable(msg.sender);
      winner.transfer(prize);
      currentVoting.totalAmount = 0;
    }

    function takeOwnersFee(uint _votingId) external onlyOwner {
      Voting storage currentVoting = votings[_votingId];

      require(currentVoting.votingStatus == Status.Finished, "Voting not finished");
      require(currentVoting.fee > 0, "Fee is already taken");

      owner.transfer(currentVoting.fee);
      currentVoting.fee = 0;
    }

    fallback() external payable {}

    receive() external payable {}
}
