import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { Signer } from 'ethers'
import { ethers } from 'hardhat'
import { InnoCoin } from '../typechain'

chai.use(chaiAsPromised)

describe('InnoCoin', () => {
  let instance: InnoCoin
  let signers: Signer[]

  beforeEach(async () => {
    const InnoCoinFactory = await ethers.getContractFactory('InnoCoin')
    instance = await InnoCoinFactory.deploy() as InnoCoin
    await instance.deployed()

    signers = await ethers.getSigners()

    for (const account of signers) {
      await instance.connect(account).tap()
    }
  })

  describe('#tap', () => {
    it('should add 100000 coins to the caller\'s account', async () => {
      await instance.connect(signers[0]).tap()
      const balance = await instance.balanceOf(await signers[0].getAddress())

      expect(balance.toNumber()).eql(200000)
    })
  })

  describe('#transfer', () => {
    it('should subtract values from the sender\'s account and add them to the recipient\'s account', async () => {
      await instance.transfer(await signers[1].getAddress(), 100)

      const balance0 = await instance.balanceOf(await signers[0].getAddress())
      const balance1 = await instance.balanceOf(await signers[1].getAddress())

      expect(balance0.toNumber()).eq(99900)
      expect(balance1.toNumber()).eq(100100)
    })

    describe('when there is not enough funds to transfer', () => {
      it('should throw', async () => {
        await expect(instance.transfer(await signers[1].getAddress(), 1000000))
          .rejectedWith('Must have enough funds to transfer')
      })
    })
  })
})
