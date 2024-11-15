import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { parseEther } from 'ethers/lib/utils'

const fundsigner: DeployFunction = async function (
  hre: HardhatRuntimeEnvironment
) {
  console.log(
    '-------------------------------------------- [funding signer] --------------------------------------------'
  )
  // on geth, fund the default "hardhat node" account.

  const provider = hre.ethers.provider
  const signer = provider.getSigner()
  const signerBalance = await provider.getBalance(signer.getAddress())
  const account = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'
  const bal = await provider.getBalance(account)
  if (bal.lt(parseEther('1')) && signerBalance.gte(parseEther('10000'))) {
    console.log('funding account at', account)
    await signer.sendTransaction({
      to: account,
      value: parseEther('1').sub(bal)
    })
  } else {
    console.log('account already funded', account)
  }
}

export default fundsigner
