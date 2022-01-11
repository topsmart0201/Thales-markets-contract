const { ethers, upgrades } = require('hardhat');
const { getTargetAddress, setTargetAddress } = require('../helpers');
const { getImplementationAddress } = require('@openzeppelin/upgrades-core');
const w3utils = require('web3-utils');

async function main() {
	let accounts = await ethers.getSigners();
	let owner = accounts[0];
	let networkObj = await ethers.provider.getNetwork();
	let network = networkObj.name;
	if (network === 'unknown') {
		network = 'localhost';
	}

	if (network == 'homestead') {
		network = 'mainnet';
	}

	if (networkObj.chainId == 69) {
		networkObj.name = 'optimisticKovan';
		network = 'optimisticKovan';
	}
	if (networkObj.chainId == 10) {
		networkObj.name = 'optimistic';
		network = 'optimistic';
	}

	console.log('Account is: ' + owner.address);
	console.log('Network:' + network);

	const thalesAmmAddress = getTargetAddress('ThalesAMM', network);
	console.log('Found ThalesAMM at:', thalesAmmAddress);

	const ThalesAMM = await ethers.getContractFactory('ThalesAMM');
	await upgrades.upgradeProxy(thalesAmmAddress, ThalesAMM);

	console.log('ThalesAMM upgraded');

	const ThalesAMMImplementation = await getImplementationAddress(ethers.provider, thalesAmmAddress);

	console.log('Implementation ThalesAMM: ', ThalesAMMImplementation);

	setTargetAddress('ThalesAMMImplementation', network, ThalesAMMImplementation);

	let ThalesAMM_deployed = ThalesAMM.attach(thalesAmmAddress);

	let safeBoxAddress = getTargetAddress('SafeBox', network);

	let tx = await ThalesAMM_deployed.setSafeBox(safeBoxAddress);
	await tx.wait().then(e => {
		console.log('ThalesAMM: setSafeBox');
	});

	tx = await ThalesAMM_deployed.setSafeBoxImpact(w3utils.toWei('0.01'));
	await tx.wait().then(e => {
		console.log('ThalesAMM: setSafeBoxImpact');
	});

	tx = await ThalesAMM_deployed.setMinSpread(w3utils.toWei('0.01'));
	await tx.wait().then(e => {
		console.log('ThalesAMM: setMinSpread');
	});

	try {
		await hre.run('verify:verify', {
			address: ThalesAMMImplementation,
		});
	} catch (e) {
		console.log(e);
	}
}

main()
	.then(() => process.exit(0))
	.catch(error => {
		console.error(error);
		process.exit(1);
	});
