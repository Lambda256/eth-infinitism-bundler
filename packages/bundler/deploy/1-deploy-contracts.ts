import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import {
  DeterministicDeployer,
  entryPointSalt
} from '@account-abstraction/utils'
import { JsonRpcProvider } from '@ethersproject/providers'
import TokenArtifact from '../artifacts/contracts/Token.sol/Token.json'
import EntryPointArtifact from '@account-abstraction/contracts/artifacts/EntryPoint.json'
import LambdaAccountFactoryArtifact from '../artifacts/contracts/LambdaAccountFactory.sol/LambdaAccountFactory.json'
import hre from 'hardhat'

export const contractSalt =
  '0x90d8084deab30c2a37c45e8d47f49f2f7965183cb6990a98943ef94940681de3'

export function getDeterministicAddress (bytecode: string): string {
  return DeterministicDeployer.getAddress(bytecode, contractSalt)
}

export async function deployContractWithDeterministicAddress (
  provider: JsonRpcProvider,
  bytecode: string,
  params: any[] = []
): Promise<string> {
  const signer = provider.getSigner()

  return await new DeterministicDeployer(provider, signer).deterministicDeploy(
    bytecode,
    entryPointSalt,
    params
  )
}

export async function deployWithParams (
  provider: JsonRpcProvider,
  abi: { contractName: string, bytecode: string },
  params: any[] = []
): Promise<string> {
  const result = await hre.deployments.deploy(abi.contractName, {
    from: await provider.getSigner().getAddress(),
    args: params,
    gasLimit: 6e6,
    log: true,
    deterministicDeployment: true,
    skipIfAlreadyDeployed: true
  })

  if (result.newlyDeployed) {
    console.log(`"${abi.contractName}" deployed to ${result.address}\n`)
  } else {
    console.log(
      `"${abi.contractName}" already deployed at ${result.address}\n`
    )
  }
  return result.address
}

export async function checkAndDeployContract (
  provider: JsonRpcProvider,
  abi: { contractName: string, bytecode: string }
): Promise<string> {
  let address = getDeterministicAddress(abi.bytecode)
  if ((await provider.getCode(address)) !== '0x') {
    console.log(`"${abi.contractName}" already deployed at ${address}\n`)
    return address
  }

  address = await deployContractWithDeterministicAddress(
    provider,
    abi.bytecode
  )
  console.log(`"${abi.contractName}" deployed to ${address}\n`)

  return address
}

const deployContracts: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  console.log(
    '-------------------------------------------- [deploying contracts] --------------------------------------------'
  )

  const entryPointAddress = await checkAndDeployContract(
    hre.ethers.provider,
    EntryPointArtifact
  )

  const accountFactoryAddress = await deployWithParams(
    hre.ethers.provider,
    LambdaAccountFactoryArtifact,
    [entryPointAddress]
  )

  const tokenAddress = await checkAndDeployContract(
    hre.ethers.provider,
    TokenArtifact
  )

  // const pm = await hre.ethers.deployContract("LambdaPaymaster", [
  //   entryPointContractAddress,
  //   "0xd5524a2942096843101d031b97897bcbd249bb46",
  //   token.address,
  // ]);
  //
  // console.log("Paymaster deployed to:", pm.target);
}

export default deployContracts
