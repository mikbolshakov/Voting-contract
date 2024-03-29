import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import type { VotingContract } from "../typechain-types";
import type { Signer } from "ethers";

describe("VotingContract", function () {
  // const amount: number = 1000000;
  async function deploy() {
    const [c1, c2, c3, v1, v2, v3, v4, v5] = await ethers.getSigners();

    const Factory = await ethers.getContractFactory("VotingContract");
    const votingContract: VotingContract = await Factory.deploy();

    await votingContract.deployed();

    return { votingContract, c1, c2, c3, v1, v2, v3, v4, v5 };
  }

  async function addCandidate(
    votingContract: VotingContract,
    account: Signer,
    votingId = 0
  ) {
    const tx = await votingContract.connect(account).addCandidate(votingId);
    await tx.wait();
  }

  async function voteForCandidate(
    votingContract: VotingContract,
    account: Signer,
    candidate: string,
    votingId = 0,
    // amount: 1000000
  ) {
    const tx = await votingContract
      .connect(account)
      .voteForCandidate(votingId, candidate) //, { value: amount });
    await tx.wait();
  }

  async function endVoting(
    votingContract: VotingContract,
    account: Signer,
    votingId = 1
  ) {
    const tx = await votingContract.connect(account).endVoting(votingId);
    await tx.wait();
  }

  it("Allows to vote and reveal winners", async function () {
    const { votingContract, c1, c2, c3, v1, v2, v3, v4, v5 } =
      await loadFixture(deploy);

    const addTx = await votingContract.addVoting();
    await addTx.wait();

    await addCandidate(votingContract, c1);
    await addCandidate(votingContract, c2);
    await addCandidate(votingContract, c3);

    await time.increase(121);

    await votingContract.startVoting(0);
    
    await voteForCandidate(votingContract, v1, c3.address) //, amount, 1000000);
    await voteForCandidate(votingContract, v2, c1.address) //, amount, 1000000);
    await voteForCandidate(votingContract, v3, c1.address) //, amount, 1000000);
    await voteForCandidate(votingContract, v4, c2.address) //, amount, 1000000);
    await voteForCandidate(votingContract, v5, c2.address) //, amount, 1000000);

    await time.increase(121);

    await votingContract.endVoting(0);

    expect(await votingContract.numberOfVotes(0, c1.address)).to.eq(2);

    const winners = await votingContract.checkWinners(0);
    expect(winners).to.include.members([c1.address, c2.address]);
    expect(winners.length).to.eq(2); // votingContract.allWinnersMapper
    expect(winners).not.to.include.members([c3.address]);
  });
});
