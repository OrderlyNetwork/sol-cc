

import { EnvType, OFTContractType, TEST_NETWORKS, MAIN_NETWORKS, tokenContractName, oftContractName, getLzConfig, checkNetwork, OPTIONS, TGE_CONTRACTS, LZ_CONFIG, getLzLibConfig , MULTI_SIG, ERC1967PROXY_BYTECODE, DETERMIN_CONTRSCT_FACTORY, INIT_TOKEN_HOLDER, TEST_LZ_ENDPOINT, MAIN_LZ_ENDPOINT, SIGNER} from "./const"
import { loadContractAddress, saveContractAddress} from "./utils"
import { Options } from '@layerzerolabs/lz-v2-utilities'
import { DeployResult } from "hardhat-deploy/dist/types"
import { task, types } from "hardhat/config"



task("sol:deploy", "Deploys the contract to a specific network")
    .addParam("env", "The environment to deploy the OFT contract", undefined, types.string)
    .addParam("contract", "The contract to deploy", undefined, types.string)
    .addFlag("preAddress", "Predict the address of the contract before deployment")
    .setAction(async (taskArgs, hre) => {
        try {
            checkNetwork(hre.network.name)
            const env: EnvType = taskArgs.env as EnvType
            console.log(`Deploying contract to ${env} network`)
            const { deploy } = hre.deployments;
            const [ signer ] = await hre.ethers.getSigners();
            let contractAddress: string = ""
            let proxy: boolean = false
            let methodName: string = ""
            let lzEndpointAddress: string | undefined= ""
            let owner: string = ""
            let initArgs: any[] = []

            const contractName = taskArgs.contract

            if (contractName === "SolCCMock") {
                proxy = true
                lzEndpointAddress = getLzConfig(hre.network.name).endpointAddress
                owner = signer.address
                initArgs = [lzEndpointAddress, owner]
            } else {
                return console.error("Invalid contract name")
            }

            const salt = hre.ethers.utils.id(process.env.ORDER_DEPLOYMENT_SALT + `${env}` || "deterministicDeployment")
            const baseDeployArgs = {
                from: signer.address,
                log: true,
                deterministicDeployment: salt
            };
            // deterministic deployment
            let deployedContract: DeployResult

            if (proxy) {
                deployedContract = await deploy(contractName, {
                    ...baseDeployArgs,
                    proxy: {
                        owner: owner,
                        proxyContract: "UUPS",
                        execute: {
                            methodName: "initialize",
                            args: initArgs
                        }
                    },
                })
            } else {
                deployedContract = await deploy(contractName, {
                    ...baseDeployArgs,
                    args: initArgs
                })
            }
            console.log(`${contractName} contract deployed to ${deployedContract.address} with tx hash ${deployedContract.transactionHash}`);
            contractAddress = deployedContract.address
            saveContractAddress(env, hre.network.name, contractName, contractAddress)
        }
        catch (error) {
            console.error(error)
        }
    })



task("sol:upgrade", "Upgrades the contract to a specific network")
    .addParam("env", "The environment to upgrade the contract", undefined, types.string)
    .addParam("contract", "The contract to upgrade", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
        const network = hre.network.name
        checkNetwork(network)
        try {
            const contractName = taskArgs.contract 
            const env: EnvType = taskArgs.env as EnvType
            console.log(`Running on ${hre.network.name}`)
            const { deploy } = hre.deployments;
            const [ signer ] = await hre.ethers.getSigners();
            let implAddress = ""
            const salt = hre.ethers.utils.id(process.env.ORDER_DEPLOYMENT_SALT + `${env}` || "deterministicDeployment")
            if (contractName === 'SolCCMock') {
                const baseDeployArgs = {
                    from: signer.address,
                    log:true,
                    deterministicDeployment: salt
                }
                const contract = await deploy(contractName, {
                    ...baseDeployArgs
                })
                implAddress = contract.address
                console.log(`${contractName} implementation deployed to ${implAddress} with tx hash ${contract.transactionHash}`);
            }
            else {
                throw new Error(`Contract ${contractName} not found`)
            }
            const contractAddress = await loadContractAddress(env, network, contractName) as string
            const contract = await hre.ethers.getContractAt(contractName, contractAddress, signer)
            
            // encoded data for function call during upgrade
            const data = "0x"
            const upgradeTx = await contract.upgradeToAndCall(implAddress, data)
            console.log(`Upgrading contract ${contractName} to ${implAddress} with tx hash ${upgradeTx.hash}`)
        }
        catch (e) {
            console.log(`Error: ${e}`)
        }
    })

task("sol:send", "Sends a transaction to a contract")
    .addParam("env", "The environment to send the transaction", undefined, types.string)
    .addParam("contract", "The contract to send the transaction", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
            const contractName = taskArgs.contract 
            const env: EnvType = taskArgs.env as EnvType
            console.log(`Running on ${hre.network.name}`)
            const { deploy } = hre.deployments;
            const [ signer ] = await hre.ethers.getSigners();

            const contractAddress = await loadContractAddress(env, hre.network.name, contractName) as string
            const contract = await hre.ethers.getContractAt(contractName, contractAddress, signer)

            const GAS_LIMIT = 500000; // Gas limit for the executor
            const MSG_VALUE = 0; // msg.value for the lzReceive() function on destination in wei

            const _options = Options.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, MSG_VALUE).toHex();

            console.log(`Options: ${_options}`);

            const str = "Hello World";
            const dstEid = 40200;

            const fee = await contract.quote(dstEid, str, _options, false);

            console.log(`Fee: ${hre.ethers.utils.formatEther(fee[0])}`);


    })