'use strict';

const { artifacts, contract, web3 } = require('hardhat');
const { toBN } = web3.utils;

const { assert, addSnapshotBeforeRestoreAfterEach } = require('../../utils/common');

const { toBytes32 } = require('../../../index');

var ethers2 = require('ethers');
var crypto = require('crypto');

const SECOND = 1000;
const HOUR = 3600;
const DAY = 86400;
const WEEK = 604800;
const YEAR = 31556926;

const {
	fastForward,
	toUnit,
	currentTime,
	multiplyDecimalRound,
	divideDecimalRound,
} = require('../../utils')();

contract('ThalesRoyale', accounts => {
	const [first, owner, second, third, fourth] = accounts;
	let priceFeedAddress;
	let rewardTokenAddress;
	let ThalesRoyale;
	let royale;
	let MockPriceFeedDeployed;

	beforeEach(async () => {
		priceFeedAddress = owner;
		rewardTokenAddress = owner;

		let MockPriceFeed = artifacts.require('MockPriceFeed');
		MockPriceFeedDeployed = await MockPriceFeed.new(owner);

		await MockPriceFeedDeployed.setPricetoReturn(1000);

		priceFeedAddress = MockPriceFeedDeployed.address;

		ThalesRoyale = artifacts.require('ThalesRoyale');
		royale = await ThalesRoyale.new(
			owner,
			toBytes32('SNX'),
			priceFeedAddress,
			toUnit(10000),
			rewardTokenAddress,
			7,
			DAY * 3,
			HOUR * 8,
			DAY
		);
	});

	describe('Init', () => {
		it('Signing up cant be called twice', async () => {
			await royale.signUp({ from: first });
			await royale.signUp({ from: second });
			let player1 = await royale.players(0);
			console.log('Player1 is ' + player1);

			let player2 = await royale.players(1);
			console.log('Player2 is ' + player2);

			let players = await royale.getPlayers();
			console.log('players are ' + players);

			let initTotalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			// not started
			assert.equal(0, initTotalPlayersInARound);

			let initEliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			// not started
			assert.equal(0, initEliminatedPlayersInARound);

			await expect(royale.signUp({ from: first })).to.be.revertedWith('Player already signed up');
		});

		it('Signing up only possible in specified time', async () => {
			await fastForward(DAY * 4);
			await expect(royale.signUp({ from: first })).to.be.revertedWith('Sign up period has expired');
		});

		it('check require statements', async () => {
			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			await expect(royale.takeAPosition(1, { from: first })).to.be.revertedWith(
				'Competition not started yet'
			);

			await expect(royale.takeAPosition(3, { from: first })).to.be.revertedWith(
				'Position can only be 1 or 2'
			);

			await expect(royale.startRoyale()).to.be.revertedWith(
				"Can't start until signup period expires"
			);

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();
			await fastForward(HOUR * 72 + 1);

			await expect(royale.takeAPosition(2, { from: first })).to.be.revertedWith(
				'Round positioning finished'
			);
		});

		it('take a losing position and end first round and try to take a position in 2nd round', async () => {
			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(false, isPlayerFirstAlive);

			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			let initTotalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			// not started
			assert.equal(0, initTotalPlayersInARound);

			let initEliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			// not started
			assert.equal(0, initEliminatedPlayersInARound);

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			let totalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			console.log('Total players in a 1. round: ' + totalPlayersInARound);
			// equal to total number of players
			assert.equal(2, totalPlayersInARound);

			let eliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARound);
			// zero  round need to be finished
			assert.equal(0, eliminatedPlayersInARound);

			await royale.takeAPosition(2, { from: first });

			let roundTargetPrice = await royale.roundTargetPrice();
			console.log('roundTargetPrice is ' + roundTargetPrice);

			let currentPrice = await MockPriceFeedDeployed.rateForCurrency(toBytes32('SNX'));
			console.log('currentPrice is ' + currentPrice);

			await MockPriceFeedDeployed.setPricetoReturn(900);

			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			roundTargetPrice = await royale.roundTargetPrice();
			console.log('roundTargetPrice is ' + roundTargetPrice);

			currentPrice = await MockPriceFeedDeployed.rateForCurrency(toBytes32('SNX'));
			console.log('currentPrice is ' + currentPrice);

			let roundResult = await royale.roundResult(1);
			console.log('roundResult is  ' + roundResult);

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			let totalPlayersInARoundTwo = await royale.getTotalPlayersPerRound(2);
			console.log('Total players in a 2. round: ' + totalPlayersInARoundTwo);
			// equal to zero because second didn't take position
			assert.equal(0, totalPlayersInARoundTwo);

			let eliminatedPlayersInARoundOne = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARoundOne);
			// two because first did take losing position, and second did't take position at all
			assert.equal(2, eliminatedPlayersInARoundOne);

			assert.equal(false, isPlayerFirstAlive);

			await expect(royale.takeAPosition(2, { from: first })).to.be.revertedWith(
				'Player no longer alive'
			);
		});

		it('take a winning position and end first round and try to take a position in 2nd round', async () => {
			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(false, isPlayerFirstAlive);

			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			let totalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			console.log('Total players in a 1. round: ' + totalPlayersInARound);
			// equal to total number of players
			assert.equal(2, totalPlayersInARound);

			let eliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARound);
			// zero  round need to be finished
			assert.equal(0, eliminatedPlayersInARound);

			await royale.takeAPosition(2, { from: first });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await royale.takeAPosition(2, { from: first });

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			let totalPlayersInARoundTwo = await royale.getTotalPlayersPerRound(2);
			console.log('Total players in a 2. round: ' + totalPlayersInARoundTwo);
			// equal to one because first
			assert.equal(1, totalPlayersInARoundTwo);

			let eliminatedPlayersInARoundOne = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARoundOne);
			// second did't take position at all so eliminated is 1
			assert.equal(1, eliminatedPlayersInARoundOne);

			assert.equal(true, isPlayerFirstAlive);
		});

		it('take a winning position and end first round then skip 2nd round', async () => {
			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(false, isPlayerFirstAlive);

			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			let alivePlayers = await royale.getAlivePlayers();
			console.log('alivePlayers are ' + alivePlayers);

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			let totalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			console.log('Total players in a 1. round: ' + totalPlayersInARound);
			// equal to total number of players
			assert.equal(2, totalPlayersInARound);

			let eliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARound);
			// zero  round need to be finished
			assert.equal(0, eliminatedPlayersInARound);

			await royale.takeAPosition(2, { from: first });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundTwo = await royale.getTotalPlayersPerRound(2);
			console.log('Total players in a 2. round: ' + totalPlayersInARoundTwo);
			// equal to one because first
			assert.equal(1, totalPlayersInARoundTwo);

			let eliminatedPlayersInARoundOne = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARoundOne);
			// second did't take position at all so eliminated is 1
			assert.equal(1, eliminatedPlayersInARoundOne);

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			alivePlayers = await royale.getAlivePlayers();
			console.log('alivePlayers2 are ' + alivePlayers);

			await MockPriceFeedDeployed.setPricetoReturn(900);
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundThree = await royale.getTotalPlayersPerRound(3);
			console.log('Total players in a 3. round: ' + totalPlayersInARoundThree);
			// equal to zero because first player didn't take position
			assert.equal(0, totalPlayersInARoundThree);

			let eliminatedPlayersInARoundTwo = await royale.getEliminatedPerRound(2);
			console.log('Total players eliminated in a 2. round: ' + eliminatedPlayersInARoundTwo);
			// first did't take position at all so eliminated in round two is 1
			assert.equal(1, eliminatedPlayersInARoundTwo);

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(false, isPlayerFirstAlive);
		});

		it('win till the end', async () => {
			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			let totalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			console.log('Total players in a 1. round: ' + totalPlayersInARound);
			// equal to total number of players
			assert.equal(2, totalPlayersInARound);

			let eliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARound);
			// zero  round need to be finished
			assert.equal(0, eliminatedPlayersInARound);

			await royale.takeAPosition(2, { from: first });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			//#1
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundTwo = await royale.getTotalPlayersPerRound(2);
			console.log('Total players in a 2. round: ' + totalPlayersInARoundTwo);
			// equal to one - first player win
			assert.equal(1, totalPlayersInARoundTwo);

			let eliminatedPlayersInARoundOne = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARoundOne);
			// equal to 1 second player did't take position
			assert.equal(1, eliminatedPlayersInARoundOne);

			//#2
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundThree = await royale.getTotalPlayersPerRound(3);
			console.log('Total players in a 3. round: ' + totalPlayersInARoundThree);
			// equal to one - first player win
			assert.equal(1, totalPlayersInARoundThree);

			let eliminatedPlayersInARoundTwo = await royale.getEliminatedPerRound(2);
			console.log('Total players eliminated in a 2. round: ' + eliminatedPlayersInARoundTwo);
			// no one left untill the end player one win
			assert.equal(0, eliminatedPlayersInARoundTwo);

			//#3
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundFour = await royale.getTotalPlayersPerRound(4);
			console.log('Total players in a 4. round: ' + totalPlayersInARoundFour);
			// equal to one - first player win
			assert.equal(1, totalPlayersInARoundFour);

			let eliminatedPlayersInARoundThree = await royale.getEliminatedPerRound(3);
			console.log('Total players eliminated in a 3. round: ' + eliminatedPlayersInARoundThree);
			// no one left untill the end player one win
			assert.equal(0, eliminatedPlayersInARoundThree);

			//#4
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundFive = await royale.getTotalPlayersPerRound(5);
			console.log('Total players in a 5. round: ' + totalPlayersInARoundFive);
			// equal to one - first player win
			assert.equal(1, totalPlayersInARoundFive);

			let eliminatedPlayersInARoundFour = await royale.getEliminatedPerRound(4);
			console.log('Total players eliminated in a 4. round: ' + eliminatedPlayersInARoundFour);
			// no one left untill the end player one win
			assert.equal(0, eliminatedPlayersInARoundFour);

			//#5
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundSix = await royale.getTotalPlayersPerRound(6);
			console.log('Total players in a 6. round: ' + totalPlayersInARoundSix);
			// equal to one - first player win
			assert.equal(1, totalPlayersInARoundSix);

			let eliminatedPlayersInARoundFive = await royale.getEliminatedPerRound(5);
			console.log('Total players eliminated in a 5. round: ' + eliminatedPlayersInARoundFive);
			// no one left untill the end player one win
			assert.equal(0, eliminatedPlayersInARoundFive);

			//#6
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundSeven = await royale.getTotalPlayersPerRound(7);
			console.log('Total players in a 7. round: ' + totalPlayersInARoundSeven);
			// equal to one - first player win
			assert.equal(1, totalPlayersInARoundSeven);

			let eliminatedPlayersInARoundSix = await royale.getEliminatedPerRound(6);
			console.log('Total players eliminated in a 6. round: ' + eliminatedPlayersInARoundSix);
			// no one left untill the end player one win
			assert.equal(0, eliminatedPlayersInARoundSix);

			//#7
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARoundEight = await royale.getTotalPlayersPerRound(8);
			console.log('Total players in a 8. round: ' + totalPlayersInARoundEight);
			// equal to ZERO, no 8. round!
			assert.equal(0, totalPlayersInARoundEight);

			let eliminatedPlayersInARoundSeven = await royale.getEliminatedPerRound(7);
			console.log('Total players eliminated in a 7. round: ' + eliminatedPlayersInARoundSeven);
			// no one left untill the end player one win
			assert.equal(0, eliminatedPlayersInARoundSeven);

			let alivePlayers = await royale.getAlivePlayers();
			console.log('final alive players are ' + alivePlayers);

			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await expect(royale.closeRound()).to.be.revertedWith('Competition finished');
		});

		it('take a winning position and end first round then skip 2nd round', async () => {
			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(false, isPlayerFirstAlive);

			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			let alivePlayers = await royale.getAlivePlayers();
			console.log('alivePlayers are ' + alivePlayers);

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			await royale.takeAPosition(2, { from: first });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			alivePlayers = await royale.getAlivePlayers();
			console.log('alivePlayers2 are ' + alivePlayers);

			await MockPriceFeedDeployed.setPricetoReturn(900);
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(false, isPlayerFirstAlive);
		});

		it('win till the end', async () => {
			await royale.signUp({ from: first });
			await royale.signUp({ from: second });

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			await royale.takeAPosition(2, { from: first });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			//#1
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#2
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#3
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#4
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#5
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#6
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#7
			await royale.takeAPosition(2, { from: first });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let alivePlayers = await royale.getAlivePlayers();
			console.log('final alive players are ' + alivePlayers);

			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await expect(royale.closeRound()).to.be.revertedWith('Competition finished');
		});

		it('win till the end', async () => {
			await royale.signUp({ from: first });
			await royale.signUp({ from: second });
			await royale.signUp({ from: third });
			await royale.signUp({ from: fourth });

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(2, { from: fourth });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			//#1
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#2
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(2, { from: fourth });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#3
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(2, { from: fourth });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#4
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(2, { from: fourth });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#5
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(2, { from: fourth });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			//#6
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(1, { from: fourth });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let alivePlayers = await royale.getAlivePlayers();
			console.log('final alive players are ' + alivePlayers);

			//#7
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			alivePlayers = await royale.getAlivePlayers();
			console.log('final alive players are ' + alivePlayers);

			let isPlayerFirstAlive = await royale.isPlayerAlive(first);

			assert.equal(true, isPlayerFirstAlive);

			await expect(royale.closeRound()).to.be.revertedWith('Competition finished');
		});

		it('win till the end and check results', async () => {
			await royale.signUp({ from: first });
			await royale.signUp({ from: second });
			await royale.signUp({ from: third });
			await royale.signUp({ from: fourth });

			await fastForward(HOUR * 72 + 1);
			await royale.startRoyale();

			let totalPlayersInARound = await royale.getTotalPlayersPerRound(1);
			console.log('Total players in a 1. round: ' + totalPlayersInARound);
			// equal to total number of players
			assert.equal(4, totalPlayersInARound);

			let eliminatedPlayersInARound = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARound);
			// zero round need to be finished
			assert.equal(0, eliminatedPlayersInARound);

			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(2, { from: fourth });

			await MockPriceFeedDeployed.setPricetoReturn(1100);

			//#1
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARound2 = await royale.getTotalPlayersPerRound(2);
			console.log('Total players in a 2. round: ' + totalPlayersInARound2);
			// equal to total number of players
			assert.equal(4, totalPlayersInARound2);

			let eliminatedPlayersInARound1 = await royale.getEliminatedPerRound(1);
			console.log('Total players eliminated in a 1. round: ' + eliminatedPlayersInARound1);
			// zero - all players are good
			assert.equal(0, eliminatedPlayersInARound1);

			//#2
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(2, { from: third });
			await royale.takeAPosition(1, { from: fourth });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARound3 = await royale.getTotalPlayersPerRound(3);
			console.log('Total players in a 3. round: ' + totalPlayersInARound3);
			// equal to three
			assert.equal(3, totalPlayersInARound3);

			let eliminatedPlayersInARound2 = await royale.getEliminatedPerRound(2);
			console.log('Total players eliminated in a 2. round: ' + eliminatedPlayersInARound2);
			// one player eliminated
			assert.equal(1, eliminatedPlayersInARound2);

			//#3
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await royale.takeAPosition(1, { from: third });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARound4 = await royale.getTotalPlayersPerRound(4);
			console.log('Total players in a 4. round: ' + totalPlayersInARound4);
			// equal to two
			assert.equal(2, totalPlayersInARound4);

			let eliminatedPlayersInARound3 = await royale.getEliminatedPerRound(3);
			console.log('Total players eliminated in a 3. round: ' + eliminatedPlayersInARound3);
			// one player eliminated
			assert.equal(1, eliminatedPlayersInARound3);

			//#4
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARound5 = await royale.getTotalPlayersPerRound(5);
			console.log('Total players in a 5. round: ' + totalPlayersInARound5);
			// equal to two
			assert.equal(2, totalPlayersInARound5);

			let eliminatedPlayersInARound4 = await royale.getEliminatedPerRound(4);
			console.log('Total players eliminated in a 4. round: ' + eliminatedPlayersInARound4);
			// zero - all players are good
			assert.equal(0, eliminatedPlayersInARound4);

			//#5
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARound6 = await royale.getTotalPlayersPerRound(6);
			console.log('Total players in a 6. round: ' + totalPlayersInARound6);
			// equal to two
			assert.equal(2, totalPlayersInARound6);

			let eliminatedPlayersInARound5 = await royale.getEliminatedPerRound(5);
			console.log('Total players eliminated in a 5. round: ' + eliminatedPlayersInARound5);
			// zero - all players are good
			assert.equal(0, eliminatedPlayersInARound5);

			//#6
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(2, { from: second });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let totalPlayersInARound7 = await royale.getTotalPlayersPerRound(7);
			console.log('Total players in a 7. round: ' + totalPlayersInARound7);
			// equal to two
			assert.equal(2, totalPlayersInARound7);

			let eliminatedPlayersInARound6 = await royale.getEliminatedPerRound(6);
			console.log('Total players eliminated in a 6. round: ' + eliminatedPlayersInARound6);
			// zero - all players are good
			assert.equal(0, eliminatedPlayersInARound6);

			let alivePlayers = await royale.getAlivePlayers();
			console.log('final alive players are ' + alivePlayers);

			//#7
			await royale.takeAPosition(2, { from: first });
			await royale.takeAPosition(1, { from: second });
			await fastForward(HOUR * 72 + 1);
			await royale.closeRound();

			let eliminatedPlayersInARound7 = await royale.getEliminatedPerRound(7);
			console.log('Total players eliminated in a 7. round: ' + eliminatedPlayersInARound7);
			// one player eliminated
			assert.equal(1, eliminatedPlayersInARound7);

			alivePlayers = await royale.getAlivePlayers();
			console.log('final alive players are ' + alivePlayers);

			let isPlayerFirstAlive = await royale.isPlayerAlive(first);
			let isPlayerSecondAlive = await royale.isPlayerAlive(second);
			let isPlayerThirdAlive = await royale.isPlayerAlive(third);
			let isPlayerFourthAlive = await royale.isPlayerAlive(fourth);

			assert.equal(true, isPlayerFirstAlive);
			assert.equal(false, isPlayerSecondAlive);
			assert.equal(false, isPlayerThirdAlive);
			assert.equal(false, isPlayerFourthAlive);

			// check to be zero (don't exist)
			let totalPlayersInARound8 = await royale.getTotalPlayersPerRound(8);
			let eliminatedPlayersInARound8 = await royale.getEliminatedPerRound(8);
			assert.equal(0, totalPlayersInARound8);
			assert.equal(0, eliminatedPlayersInARound8);

			await expect(royale.closeRound()).to.be.revertedWith('Competition finished');
		});
	});
});
