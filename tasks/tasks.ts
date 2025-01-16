

import { EnvType, OFTContractType, TEST_NETWORKS, MAIN_NETWORKS, tokenContractName, oftContractName, getLzConfig, checkNetwork, OPTIONS, TGE_CONTRACTS, LZ_CONFIG, getLzLibConfig , MULTI_SIG, ERC1967PROXY_BYTECODE, DETERMIN_CONTRSCT_FACTORY, INIT_TOKEN_HOLDER, TEST_LZ_ENDPOINT, MAIN_LZ_ENDPOINT, SIGNER} from "./const"
import { loadContractAddress, saveContractAddress, equalDVNs} from "./utils"
import { addressToBytes32, Options } from '@layerzerolabs/lz-v2-utilities'
import { DeployResult } from "hardhat-deploy/dist/types"
import { task, types } from "hardhat/config"
import { base58, hexlify } from "ethers/lib/utils"



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
            } else if (contractName === "OFTMock") {
                proxy = true
                lzEndpointAddress = getLzConfig(hre.network.name).endpointAddress
                owner = signer.address
                initArgs = [lzEndpointAddress, owner]
            } else if (contractName === "SolConnector") {
                proxy = true
                lzEndpointAddress = getLzConfig(hre.network.name).endpointAddress
                owner = signer.address
                console.log(`Owner: ${owner}`)
                const solEid = env === "mainnet" ? 30168 : 40168
                initArgs = [lzEndpointAddress, owner, solEid]
            }
            else {
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
            if (contractName === 'SolCCMock' || contractName === 'OFTMock' || contractName === 'SolConnector') {
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
            // const contractAddress = await loadContractAddress(env, network, contractName) as string
            // const contract = await hre.ethers.getContractAt(contractName, contractAddress, signer)
            
            // // encoded data for function call during upgrade
            // const data = "0x"
            // const upgradeTx = await contract.upgradeToAndCall(implAddress, data)
            // console.log(`Upgrading contract ${contractName} to ${implAddress} with tx hash ${upgradeTx.hash}`)
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

            const GAS_LIMIT = 1000000; // Gas limit for the executor
            const MSG_VALUE = 10000000; // msg.value for the lzReceive() function on destination in wei

            const options = Options.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, MSG_VALUE).toHex();

            const receiver = "0x18b9507fce83984a6b1959594a4df8149758cbaf2005d54e242dc27a1d35d976"

            const dstEid = 40168

            const param = {
                dstEid: dstEid,
                to: receiver,
                amountLD: 1000000,
                minAmountLD: 1000000,
                extraOptions: options,
                composeMsg: "0x",
                oftCmd: "0x"
            }
            const payLzToken = false
            let fee = await contract.quoteSend(param, payLzToken);
            console.log(`Fee in native: ${fee.nativeFee}`)

            const sendTx = await contract.send(param, fee, signer.address, {
                value: fee.nativeFee
            })
            await sendTx.wait()
            console.log(`Sending tokens with tx hash ${sendTx.hash}`)
            // const sendTx = await localContract.send(param, fee, signer.address, 
            // {   value: fee.nativeFee,
            //     nonce: nonce++
            // })
            // await sendTx.wait()
            // console.log(`Sending tokens from ${fromNetwork} to ${toNetwork} with tx hash ${sendTx.hash}`)


    })

task("sol:peer", "Sets the peer contract for the contract")
    .addParam("env", "The environment to send the transaction", undefined, types.string)
    .addParam("contract", "The contract to send the transaction", undefined, types.string)
    .addParam("peer", "The peer contract to set", undefined, types.string)
    .setAction(async (taskArgs, hre) => {
            const contractName = taskArgs.contract 
            const env: EnvType = taskArgs.env as EnvType
            console.log(`Running on ${hre.network.name}`)
            const { deploy } = hre.deployments;
            const [ signer ] = await hre.ethers.getSigners();

            const contractAddress = await loadContractAddress(env, hre.network.name, contractName) as string
            const contract = await hre.ethers.getContractAt(contractName, contractAddress, signer)

            const solAddress = hexlify(base58.decode(taskArgs.peer))
            const solEid = env === "mainnet" ? 30168 : 40168
            const setPeerTx = await contract.setPeer(solEid, solAddress)
            await setPeerTx.wait()
            console.log(`Setting peer contract with tx hash ${setPeerTx.hash}`)
    })

    task("sol:owner", "Set the owner of SolConnector ")
    .addParam("env", "The environment to operate", undefined, types.string)
    .addFlag("setOwner", "Set the multisig as owner", )
    .setAction(async (taskArgs, hre) => {
        checkNetwork(hre.network.name)
        try {
            const fromNetwork = hre.network.name
            console.log(`Running on ${fromNetwork}`)
            const [ signer ] = await hre.ethers.getSigners()
            const localContractName = "SolConnector"
            const localContractAddress = await loadContractAddress(taskArgs.env, fromNetwork, localContractName) as string
            const localContract = await hre.ethers.getContractAt(localContractName, localContractAddress, signer)

            const endpointV2Deployment = await hre.deployments.get('EndpointV2')
            const endpointV2 = await hre.ethers.getContractAt(endpointV2Deployment.abi, endpointV2Deployment.address, signer)

            const owner = await localContract.owner()
            const delegator = await endpointV2.delegates(localContractAddress)

            console.log(`OFT Owner: ${owner}`)
            console.log(`OFT Delegator: ${delegator}`)

            if (taskArgs.setOwner) {
                const multiSig = MULTI_SIG[taskArgs.env]
                if (multiSig && owner !== multiSig) {
                    const txSetDelegator = await localContract.setDelegate(multiSig)
                    await txSetDelegator.wait()
                    console.log(`Set OFT Delegator to ${multiSig}`)
                    const txSetOwner = await localContract.transferOwnership(multiSig)
                    await txSetOwner.wait()
                    console.log(`Set OFT Owner to ${multiSig}`)
                } else {
                    console.log(`OFT Owner already set to ${multiSig} or not found`)
                }
            }



        }
        catch (e) {
            console.log(`Error: ${e}`)
        }
    })

const CONFIG_TYPE_EXECUTOR = 1
const CONFIG_TYPE_ULN = 2
const EXECUTOR_CONFIG_STRUCT = "tuple(uint32 maxMessageSize, address executorAddress)"
// const EXECUTOR_CONFIG_STRUCT = ["uint32","address"]
const ULN_CONFIG_STRUCT = "tuple(uint64 confirmations, uint8 requiredDVNCount, uint8 optionalDVNCount, uint8 optionalDVNThreshold, address[] requiredDVNs, address[] optionalDVNs)"
// const ULN_CONFIG_STRUCT = ["uint64","uint8","uint8","uint8","address[]","address[]"]

task("sol:getconfig", "Gets the configuration of the contract")
    .addParam("env", "The environment to deploy the OFT contract", undefined, types.string)
    .addFlag("setConfig", "Set the configuration of OFT contracts for different networks", )
    .addFlag("forceSet", "Force set the configuration of OFT contracts for different networks", )
    .addFlag("multisig", "Get the proposal for multisig", )
    .setAction(async (taskArgs, hre) => {
        try{
            const env = taskArgs.env as EnvType
            const fromNetwork = hre.network.name
            const toNetwork = env === "mainnet" ? "solana" : "soldev"
            const endpointV2Deployment = await hre.deployments.get('EndpointV2')
            const [ signer ] = await hre.ethers.getSigners()
            const endpointV2 = await hre.ethers.getContractAt(endpointV2Deployment.abi, endpointV2Deployment.address, signer)
            const localContractName = "SolConnector"
            const localContractAddress = await loadContractAddress(taskArgs.env, fromNetwork, localContractName) as string
            const lzLibConfig = getLzLibConfig(fromNetwork)
            let remoteLzConfig, remoteEid, defaultSendLib, defaultReceiveLib, onchainSendLibConfigExecutor, onchainSendLibConfigULN, onchainReceiveLibConfigULN, lzSendConfig, lzReceiveConfig
            let rawSendLibExecutor, rawSendLibULN, rawReceiveLibULN, setSendLibExecutor, setSendLibULN, setReceiveLibULN
            let receiveLibConfigULNArray = []
            let sendLibConfigExecutorULNArray = []
            remoteLzConfig = getLzConfig(toNetwork)
            remoteEid = remoteLzConfig["endpointId"]
            defaultSendLib = await endpointV2.defaultSendLibrary(remoteEid)
            defaultReceiveLib = await endpointV2.defaultReceiveLibrary(remoteEid)
            onchainSendLibConfigExecutor = await endpointV2.getConfig(localContractAddress, defaultSendLib, remoteEid, CONFIG_TYPE_EXECUTOR)
            onchainSendLibConfigULN = await endpointV2.getConfig(localContractAddress, defaultSendLib, remoteEid, CONFIG_TYPE_ULN)
            onchainReceiveLibConfigULN = await endpointV2.getConfig(localContractAddress, defaultReceiveLib, remoteEid, CONFIG_TYPE_ULN)
            const [decodeSendLibConfigExecutor] = hre.ethers.utils.defaultAbiCoder.decode([EXECUTOR_CONFIG_STRUCT], onchainSendLibConfigExecutor)
            const [decodeSendLibConfigULN] = hre.ethers.utils.defaultAbiCoder.decode([ULN_CONFIG_STRUCT], onchainSendLibConfigULN)
            const [decodeReceiveLibConfigULN] = hre.ethers.utils.defaultAbiCoder.decode([ULN_CONFIG_STRUCT], onchainReceiveLibConfigULN)
            lzSendConfig = lzLibConfig.sendLibConfig
            lzReceiveConfig = lzLibConfig.receiveLibConfig
            console.log(`=================Print Config for pathway to ${toNetwork}===================`)
            console.log(`Default SendLib: ${defaultSendLib}`)
            console.log(`Onchain SendLibConfigExecutor: \n maxMessageSize: ${decodeSendLibConfigExecutor[0]},\n executor: ${decodeSendLibConfigExecutor[1]}`)
            console.log(`Onchain SendLibConfigULN: \n confirmations: ${decodeSendLibConfigULN[0]}, \n requiredDVNCount: ${decodeSendLibConfigULN[1]}, \n optionalDVNCount: ${decodeSendLibConfigULN[2]}, \n optionalDVNThreshold: ${decodeSendLibConfigULN[3]}, \n requiredDVNs: ${decodeSendLibConfigULN[4]}, \n optionalDVNs: ${decodeSendLibConfigULN[5]} \n`)
            
            console.log(`Default ReceiveLib: ${defaultReceiveLib}`)
            console.log(`Onchain ReceiveLibConfigULN: \n confirmations: ${decodeReceiveLibConfigULN[0]}, \n requiredDVNCount: ${decodeReceiveLibConfigULN[1]}, \n optionalDVNCount: ${decodeReceiveLibConfigULN[2]}, \n optionalDVNThreshold: ${decodeReceiveLibConfigULN[3]}, \n requiredDVNs: ${decodeReceiveLibConfigULN[4]}, \n optionalDVNs: ${decodeReceiveLibConfigULN[5]} \n`)

            if (taskArgs.setConfig) {
                
                const isDefaultSendLib = await endpointV2.isDefaultSendLibrary(localContractAddress, remoteEid)
                if (isDefaultSendLib) {
                    const txSetSendLib = await endpointV2.setSendLibrary(localContractAddress, remoteEid, defaultSendLib)
                    await txSetSendLib.wait()
                    console.log(`✅ Set SendLib for ${toNetwork}`)
                } else {
                    console.log(`👌 SendLib already set for ${toNetwork}`)
                }

                const receiveLibOnContract = await endpointV2.getReceiveLibrary(localContractAddress, remoteEid)
                const expiryBlocks = 0
                if (receiveLibOnContract.isDefault == true) {
                    const txSetReceiveLib = await endpointV2.setReceiveLibrary(localContractAddress, remoteEid, defaultReceiveLib, expiryBlocks)
                    await txSetReceiveLib.wait()
                    console.log(`✅ Set ReceiveLib for ${toNetwork}`)
                } else {
                    console.log(`👌 ReceiveLib already set for ${toNetwork}`)
                }
                    
            }

            // create new arreys to set config
            rawSendLibExecutor = [...decodeSendLibConfigExecutor || []]
            // console.log(rawSendLibExecutor)
            rawSendLibULN = [...decodeSendLibConfigULN || []]
            rawReceiveLibULN = [...decodeReceiveLibConfigULN || []]

            // console.log(rawSendLibULN[4])
            if (!equalDVNs(rawSendLibULN[4], lzLibConfig.sendLibConfig?.ulnConfig.requiredDVNs!)) {
                console.log(`🚨 The onchain Send DVNs on chain are not the same as defined on config file`)
                rawSendLibULN[4] = lzLibConfig.sendLibConfig?.ulnConfig.requiredDVNs
                rawSendLibULN[1] = lzLibConfig.sendLibConfig?.ulnConfig.requiredDVNs.length
                setSendLibULN = true
                // console.log(rawSendLibULN)
                const encodeSendLibConfigExecutor = hre.ethers.utils.defaultAbiCoder.encode([EXECUTOR_CONFIG_STRUCT], [rawSendLibExecutor])
                sendLibConfigExecutorULNArray.push([remoteEid, CONFIG_TYPE_EXECUTOR, encodeSendLibConfigExecutor])
                const encodeSendLibConfigULN= hre.ethers.utils.defaultAbiCoder.encode([ULN_CONFIG_STRUCT], [rawSendLibULN])
                sendLibConfigExecutorULNArray.push([remoteEid, CONFIG_TYPE_ULN, encodeSendLibConfigULN])

            } else {
                console.log(`👌 The onchain Send DVNs on chain are the same as defined on config file`)
            }

            // console.log(decodeReceiveLibConfigULN[4])
            if (!equalDVNs(decodeReceiveLibConfigULN[4], lzLibConfig.receiveLibConfig?.ulnConfig.requiredDVNs!))  { 
                console.log(`🚨 The onchain Receive DVNs on chain are not the same as defined on config file`)
                rawReceiveLibULN[4] = lzLibConfig.receiveLibConfig?.ulnConfig.requiredDVNs
                rawReceiveLibULN[1] = lzLibConfig.receiveLibConfig?.ulnConfig.requiredDVNs.length
                setReceiveLibULN = true
                // console.log(rawReceiveLibULN)
                const encodeRceiveLibConfigULN = hre.ethers.utils.defaultAbiCoder.encode([ULN_CONFIG_STRUCT], [rawReceiveLibULN])
                receiveLibConfigULNArray.push([remoteEid, CONFIG_TYPE_ULN, encodeRceiveLibConfigULN])
                
            } else {
                console.log(`👌 The onchain Receive DVNs on chain are the same as defined on config file`)
            }

            if (taskArgs.setConfig) {
                if(setSendLibULN || taskArgs.forceSet) {
                    console.log("=====🚨 Set SendLib config for all above listed networks=====")
                    const txSetSendConfig = await endpointV2.setConfig(localContractAddress, defaultSendLib, sendLibConfigExecutorULNArray)
                    await txSetSendConfig.wait()
                    console.log(`✅ Set SendLib config on ${fromNetwork}`)
                } else {
                    console.log(`👌 SendLib config already set on ${fromNetwork}`)
                }
                if (setReceiveLibULN || taskArgs.forceSet) {
                    console.log("=====🚨 Set ReceivedLib config for all above listed networks=====")
                    const txSetULNConfig = await endpointV2.setConfig(localContractAddress, defaultReceiveLib, receiveLibConfigULNArray)
                    await txSetULNConfig.wait()
                    console.log(`✅ Set ReceiveLib config on ${fromNetwork}`)
                } else {
                    console.log(`👌 ReceiveLib config already set on ${fromNetwork}`)
                }    
            }

            // const endpointV2Deployment = await hre.deployments.get('EndpointV2')
            // const endpointV2 = await hre.ethers.getContractAt(endpointV2Deployment.abi, endpointV2Deployment.address, signer)
            const localContract = await hre.ethers.getContractAt(localContractName, localContractAddress, signer)

            const orderDeliver = await localContract.orderDelivery()
            const inboundNonce = await localContract.inboundNonce()
            const solEid = await localContract.solEid()
            const solPeer = await localContract.peers(solEid)
            const [withdrawMsgGas, withdrawMsgValue] = await localContract.msgOptions(1)   // 1: withdraw
            const owner = await localContract.owner()
            const endpoint = await localContract.endpoint()
            const ledger = await localContract.ledger()
            const delegator = await endpointV2.delegates(localContractAddress)
            console.log(`=================Print SolConnector Information===================`)
            console.log(`Order Deliver: ${orderDeliver}`)
            console.log(`Inbound Nonce: ${inboundNonce}`)
            console.log(`Solana EID: ${solEid}`)
            console.log(`Withdraw Msg Gas: ${withdrawMsgGas}, Withdraw Msg Value: ${withdrawMsgValue}`)
            console.log(`Solana Peer: ${base58.encode(solPeer)}`)
            console.log(`Endpoint address: ${endpoint}`)
            console.log(`Ledger address: ${ledger}`)
            console.log(`SolConnector Owner: ${owner}`)
            console.log(`SolConnector Delegator: ${delegator}`)
        } catch (error) {
            console.error(error)
        }
    })