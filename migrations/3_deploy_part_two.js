require('dotenv').config({ path: '../.env' })

const ForeignSwap = artifacts.require('./ForeignSwap.sol');
const BPD = artifacts.require('./BPD.sol');
const SubBalances = artifacts.require('./SubBalances.sol');

module.exports = async function (deployer, network, accounts) {
	return deployer.then(async () => {

		const { SETTER_ADDRESS } = process.env
		console.log('Setter address: ', SETTER_ADDRESS);

		// DEPLOY SWAP
		const foreignSwap = await deployer.deploy(ForeignSwap, SETTER_ADDRESS);
		
		// DEPLOY BPD
		const bpd = await deployer.deploy(BPD, SETTER_ADDRESS);

		// DEPLOY SUBBALANCES
		const subBalances = await deployer.deploy(SubBalances, SETTER_ADDRESS)
		
		console.log('Foreign Swap address: ', foreignSwap.address);
		console.log('BPD address: ', bpd.address);
		console.log('SubBalances address:', subBalances.address);


	})
}