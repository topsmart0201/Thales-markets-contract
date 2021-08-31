const { ethers } = require('hardhat');
const w3utils = require('web3-utils');
const { artifacts, contract, web3 } = require('hardhat');
const snx = require('synthetix');

const { toBN } = web3.utils;

const { toBytes32 } = require('../../index');

const util = require('util');

//let managerAddress = '0x46d9DB2830C005e38878b241199bb09d9d355994'; //kovan
let managerAddress = '0x46d9DB2830C005e38878b241199bb09d9d355994'; //ropsten

//mainnet
let oracleContract = '0x56dd6586DB0D08c6Ce7B2f2805af28616E082455';
let sportsJobId = '7dd85c2336ed43888905844e549479f1';

async function main() {
	let accounts = await ethers.getSigners();
	let owner = accounts[0];
	let networkObj = await ethers.provider.getNetwork();
	let network = networkObj.name;
	let fundingAmount = w3utils.toWei('1');
	if (network == 'homestead') {
		network = 'mainnet';
		fundingAmount = w3utils.toWei('1000');
	}

	console.log('Account is:' + owner.address);
	console.log('Network name:' + networkObj.name);

	const addressResolver = snx.getTarget({ network, contract: 'ReadProxyAddressResolver' });
	console.log('Found address resolver at:' + addressResolver.address);

	const safeDecimalMath = snx.getTarget({ network, contract: 'SafeDecimalMath' });
	console.log('Found safeDecimalMath at:' + safeDecimalMath.address);

	const BinaryOptionMarketManager = await ethers.getContractFactory('BinaryOptionMarketManager', {
		libraries: {
			SafeDecimalMath: safeDecimalMath.address,
		},
	});
	let manager = await BinaryOptionMarketManager.attach(managerAddress);

	console.log('found manager at:' + manager.address);

	let IntegersContract = await ethers.getContractFactory('Integers');
	const integersDeployed = await IntegersContract.deploy();
	await integersDeployed.deployed();

	console.log('integersDeployed deployed to:', integersDeployed.address);

	let USOpenFeed = await ethers.getContractFactory('USOpenFeed');
	const USOpenFeedDeployed = await USOpenFeed.deploy(
		owner.address,
		oracleContract,
		toBytes32(sportsJobId),
		w3utils.toWei('1'),
		'2020'
	);
	await USOpenFeedDeployed.deployed();

	console.log('USOpenFeedDeployed deployed to:', USOpenFeedDeployed.address);

	let USOpenFeedInstanceContract = await ethers.getContractFactory('USOpenFeedInstance');

	let maturityDate = Math.round(Date.parse('13 SEP 2021 00:00:00 GMT') / 1000);

	const ProxyERC20sUSD = snx.getTarget({ network, contract: 'ProxyERC20sUSD' });
	console.log('Found ProxyERC20sUSD at:' + ProxyERC20sUSD.address);
	let abi = ['function approve(address _spender, uint256 _value) public returns (bool success)'];
	let contract = new ethers.Contract(ProxyERC20sUSD.address, abi, owner);
	await contract.approve(manager.address, w3utils.toWei('10000'), {
		from: owner.address,
	});
	console.log('Done approving');

	let oracleAddress1 = await createOracleInstance(
		USOpenFeedInstanceContract,
		owner.address,
		USOpenFeedDeployed.address,
		w3utils.toWei('605658'),
		'Dominic Thiem',
		'1',
		'US Open 2020 winner'
	);
	await createMarket(manager, maturityDate, fundingAmount, oracleAddress1);

	//-----verifications

	await hre.run('verify:verify', {
		address: integersDeployed.address,
	});

	await hre.run('verify:verify', {
		address: USOpenFeedDeployed.address,
		constructorArguments: [
			owner.address,
			oracleContract,
			toBytes32(sportsJobId),
			w3utils.toWei('1'),
			'2020',
		],
		contract: 'contracts/SportOracles/USOpenFeed.sol:USOpenFeed',
	});

	await hre.run('verify:verify', {
		address: oracleAddress1,
		constructorArguments: [
			owner.address,
			USOpenFeedDeployed.address,
			w3utils.toWei('605658'),
			'Dominic Thiem',
			'1',
			'US Open 2020 winner',
		],
		contract: 'contracts/SportOracles/USOpenFeedInstance.sol:USOpenFeedInstance',
	});
}

main()
	.then(() => process.exit(0))
	.catch(error => {
		console.error(error);
		process.exit(1);
	});

async function createMarket(
	manager,
	maturityDate,
	fundingAmount,
	sportFeedOracleInstanceContractDeployedAddress
) {
	const result = await manager.createMarket(
		toBytes32(''),
		0,
		maturityDate,
		fundingAmount,
		true,
		sportFeedOracleInstanceContractDeployedAddress,
		{ gasLimit: 5500000 }
	);

	await result.wait().then(function(receipt) {
		let marketCreationArgs = receipt.events[receipt.events.length - 1].args;
		for (var key in marketCreationArgs) {
			if (marketCreationArgs.hasOwnProperty(key)) {
				if (key == 'market') {
					console.log('Market created at ' + marketCreationArgs[key]);
				}
			}
		}
	});
}

async function createOracleInstance(
	USFeedOracleContract,
	ownerAddress,
	sportFeedContractDeployedAddress,
	competitor,
	country,
	place,
	eventName
) {
	const USFeedOracleContractDeployed = await USFeedOracleContract.deploy(
		ownerAddress,
		sportFeedContractDeployedAddress,
		competitor,
		country,
		place,
		eventName
	);
	await USFeedOracleContractDeployed.deployed();

	console.log('USFeedOracleContractDeployed deployed to:', USFeedOracleContractDeployed.address);
	console.log(
		'with params country ' + country + ' place ' + place + ' event ' + eventName,
		+' competitor ' + competitor
	);

	return USFeedOracleContractDeployed.address;
}

function getEventByName({ tx, name }) {
	return tx.logs.find(({ event }) => event === name);
}
