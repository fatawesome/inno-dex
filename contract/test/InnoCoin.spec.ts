import { Signer } from 'ethers'
import { ethers } from 'hardhat'
import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { InnoCoin } from '../typechain'

chai.use(chaiAsPromised)

describe('InnoCoin', () => {
  let instance: InnoCoin
  let accounts: Signer[]

  beforeEach(async () => {
    const InnoCoinFactory = await ethers.getContractFactory('InnoCoin')
    instance = await InnoCoinFactory.deploy() as InnoCoin
    await instance.deployed()

    accounts = await ethers.getSigners()

    for (const account of accounts) {
      await instance.connect(account).tap()
    }
  })

  describe('#tap', () => {
    it('should add 100000 coins to the caller\'s account', async () => {
      const balanceBefore = await instance.balanceOf(await accounts[0].getAddress())
      await instance.connect(accounts[0]).tap()
      const balance = await instance.balanceOf(await accounts[0].getAddress())

      expect(balance.toNumber() - balanceBefore.toNumber()).eql(100000)
    })
  })

  describe('#transfer', () => {
    it('should subtract values from the sender\'s account and add them to the recipient\'s account', async () => {
      const balance0Before = await instance.balanceOf(await accounts[0].getAddress())
      const balance1Before = await instance.balanceOf(await accounts[1].getAddress())

      await instance.transfer(await accounts[1].getAddress(), 100,)

      const balance0 = await instance.balanceOf(await accounts[0].getAddress())
      const balance1 = await instance.balanceOf(await accounts[1].getAddress())

      expect(balance0.toNumber() - balance0Before.toNumber()).eq(-100)
      expect(balance1.toNumber() - balance1Before.toNumber()).eq(100)
    })

    describe('when there is not enough funds to transfer', () => {
      it('should throw', async () => {
        await expect(instance.transfer(await accounts[1].getAddress(), 1000000))
          .rejectedWith('Must have enough funds to transfer')
      })
    })
  })
})
