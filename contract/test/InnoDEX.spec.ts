import { Signer } from 'ethers'
import { ethers, network } from 'hardhat'
import chai, { expect } from 'chai'
import chaiAsPromised from 'chai-as-promised'
import { InnoCoin, InnoDEX } from '../typechain'

chai.use(chaiAsPromised)

// The enums are enumerated (haha got it? enums are enumerated lmao i'm so funny) automatically starting from 0,
// which is the exact behavior that the solidity compiler uses when compiling same enums from solidity code,
// so leaving them without explicit labels is good enough.

enum OrderSide {
  Bid,
  Ask
}

enum OrderFlags {
  ImmediateOrCancel,
  TimeInForce,
  GoodTillCancel
}

// some assertion helpers

enum OrderType {
  closedAsk = 'closedAsk',
  openAsk = 'openAsk',
  canceledAsk = 'canceledAsk',
  closedBid = 'closedBid',
  openBid = 'openBid',
  canceledBid = 'canceledBid'
}

async function expectOrderIds (dex: InnoDEX, type: OrderType, ids: number[]) {
  const methods = {
    [OrderType.closedAsk]: {
      amount: 'amountOfClosedAsks',
      array: 'closed_asks'
    },
    [OrderType.openAsk]: {
      amount: 'amountOfOpenAsks',
      array: 'asks'
    },
    [OrderType.canceledAsk]: {
      amount: 'amountOfCanceledAsks',
      array: 'canceled_asks'
    },
    [OrderType.closedBid]: {
      amount: 'amountOfClosedBids',
      array: 'closed_bids'
    },
    [OrderType.openBid]: {
      amount: 'amountOfOpenBids',
      array: 'bids'
    },
    [OrderType.canceledBid]: {
      amount: 'amountOfCanceledBids',
      array: 'canceled_bids'
    },
  }[type]

  const amountOfOrders = await dex[methods.amount]()
  expect(amountOfOrders).eq(ids.length)

  for (let i = 0; i < ids.length; i++) {
    const order = await dex[methods.array](i)
    expect(order.uid).eq(ids[i])
  }
}

async function expectAllOrderIds (dex: InnoDEX, ids: Partial<Record<OrderType, number[]>>) {
  await expectOrderIds(dex, OrderType.closedAsk, ids[OrderType.closedAsk] || [])
  await expectOrderIds(dex, OrderType.closedBid, ids[OrderType.closedBid] || [])
  await expectOrderIds(dex, OrderType.openAsk, ids[OrderType.openAsk] || [])
  await expectOrderIds(dex, OrderType.openBid, ids[OrderType.openBid] || [])
  await expectOrderIds(dex, OrderType.canceledAsk, ids[OrderType.canceledAsk] || [])
  await expectOrderIds(dex, OrderType.canceledBid, ids[OrderType.canceledBid] || [])
}

// TODO: probably using an "abstract" stubbed implementation would be better than an instance of an actual coin
//  but hardhat is still ways away from actual useful testing utils (even though it is leagues ahead of truffle).
//  So, we are happy with what we get now.
describe('InnoDEX', () => {
  let dex: InnoDEX
  let coin: InnoCoin
  let signers: Signer[]

  beforeEach(async () => {
    const InnoCoinFactory = await ethers.getContractFactory('InnoCoin')
    coin = await InnoCoinFactory.deploy() as InnoCoin
    await coin.deployed()

    const InnoDEXFactory = await ethers.getContractFactory('InnoDEX')
    dex = await InnoDEXFactory.deploy(coin.address) as InnoDEX
    await dex.deployed()

    signers = await ethers.getSigners()

    for (const account of signers) {
      await coin.connect(account).tap()
      await coin.connect(account).approve(dex.address, 100000)
    }
  })

  describe('#limitOrder', () => {
    describe('when the order book is empty', () => {
      describe('when placing a new ask with the GoodTillCancel flag', () => {
        it('should just place an empty ask', async () => {
          await dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.GoodTillCancel, 0)
          const ask = await dex.asks(0)

          expect(ask.uid).eq(1)
          expect(ask.price.toNumber()).eq(10)
          expect(ask.quantity.toNumber()).eq(20)
          expect(ask.flags).eq(OrderFlags.GoodTillCancel)
          expect(ask.good_till.toNumber()).eq(0)
          expect(ask.owner).eq(await signers[0].getAddress())
        })
      })

      describe('when placing a new bid with the GoodTillCancel flag', () => {
        it('should just place an empty bid', async () => {
          await dex.limitOrder(1, OrderSide.Bid, 15, 30, OrderFlags.GoodTillCancel, 0, { value: 15 * 30 })
          const bid = await dex.bids(0)

          expect(bid.uid).eq(1)
          expect(bid.price.toNumber()).eq(15)
          expect(bid.quantity.toNumber()).eq(30)
          expect(bid.original_quantity.toNumber()).eq(30)
          expect(bid.flags).eq(OrderFlags.GoodTillCancel)
          expect(bid.good_till.toNumber()).eq(0)
          expect(bid.owner).eq(await signers[0].getAddress())
        })
      })
    })

    describe('when the order book is not empty (general closing behaviour with GoodTillCancel)', () => {
      describe('when placing a new bid', () => {
        describe('when there is an equal ask', () => {
          it('should completely cover both and emit OrderClosed events', async () => {
            // arranging the set
            await dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.GoodTillCancel, 0)

            // remembering some values to assert
            const eth0Before = await signers[0].getBalance()

            // acting
            const promise = dex
              .connect(signers[1])
              .limitOrder(2, OrderSide.Bid, 10, 20, OrderFlags.GoodTillCancel, 0, { value: 10 * 20 })

            // asserting

            // events for both bids should be emitted
            await expect(promise)
              .emit(dex, 'OrderClosed')
              .withArgs(1)
            await expect(promise)
              .emit(dex, 'OrderClosed')
              .withArgs(2)

            await expectAllOrderIds(dex, {
              // the previous respective order should be the only closed one
              [OrderType.closedAsk]: [1],
              [OrderType.closedBid]: [2]
            })

            // the first account should have more eth
            const eth0 = await signers[0].getBalance()
            expect(eth0.sub(eth0Before)).eq(200)

            // the second account should have more balance
            const balance1 = await coin.balanceOf(await signers[1].getAddress())
            expect(balance1).eq(100000 + 20)
          })
        })

        describe('when there is an ask with same quantity, but a higher price', () => {
          it('should not cover any position', async () => {
            // arranging the set
            await dex.limitOrder(1, OrderSide.Ask, 11, 20, OrderFlags.GoodTillCancel, 0)

            // acting
            await dex
              .connect(signers[1])
              .limitOrder(2, OrderSide.Bid, 10, 20, OrderFlags.GoodTillCancel, 0, { value: 10 * 20 })

            // asserting
            // there should be only one open order from each side
            await expectAllOrderIds(dex, {
              [OrderType.openAsk]: [1],
              [OrderType.openBid]: [2]
            })
          })
        })

        describe('when there is an ask with same quantity, but a lower price', () => {
          it('should completely cover both using the bid price and emit OrderClosed events', async () => {
            // arranging the set
            await dex.limitOrder(1, OrderSide.Ask, 9, 20, OrderFlags.GoodTillCancel, 0)

            // remembering some values to assert
            const eth0Before = await signers[0].getBalance()

            // acting
            const promise = dex
              .connect(signers[1])
              .limitOrder(2, OrderSide.Bid, 10, 20, OrderFlags.GoodTillCancel, 0, { value: 10 * 20 })

            // asserting

            // events for both bids should be emitted
            await expect(promise)
              .emit(dex, 'OrderClosed')
              .withArgs(1)
            await expect(promise)
              .emit(dex, 'OrderClosed')
              .withArgs(2)

            // the previous respective order should be the only closed one
            await expectAllOrderIds(dex, {
              [OrderType.closedAsk]: [1],
              [OrderType.closedBid]: [2]
            })

            // the first account should have more eth by the bid's price point
            const eth0 = await signers[0].getBalance()
            expect(eth0.sub(eth0Before)).eq(200)

            // the second account should have more balance
            const balance1 = await coin.balanceOf(await signers[1].getAddress())
            expect(balance1).eq(100000 + 20)
          })
        })

        describe('when there is an ask with a lower quantity, but same price', () => {
          it('should completely cover the ask and partially cover the bid', async () => {
            // arranging the set
            await dex.limitOrder(1, OrderSide.Ask, 10, 15, OrderFlags.GoodTillCancel, 0)

            // remembering some values to assert
            const eth0Before = await signers[0].getBalance()

            // acting
            const promise = dex
              .connect(signers[1])
              .limitOrder(2, OrderSide.Bid, 10, 20, OrderFlags.GoodTillCancel, 0, { value: 10 * 20 })

            // asserting

            // event for the ask should be emitted
            await expect(promise)
              .emit(dex, 'OrderClosed')
              .withArgs(1)

            // the bid should remain open, and the ask should move to the "closed" pile
            // the previous respective order should be the only closed one
            await expectAllOrderIds(dex, {
              [OrderType.closedAsk]: [1],
              [OrderType.openBid]: [2]
            })

            // the first account should have more eth by the bid's price point
            const eth0 = await signers[0].getBalance()
            expect(eth0.sub(eth0Before)).eq(15 * 10)

            // the second account should have more balance
            const balance1 = await coin.balanceOf(await signers[1].getAddress())
            expect(balance1).eq(100000 + 15)

            // the bid should have less quantity, but retain original_quantity
            const bid = await dex.bids(0)
            expect(bid.quantity).eq(5)
            expect(bid.original_quantity).eq(20)
          })
        })

        describe('when there is an ask with a higher quantity, but same price', () => {
          it('should completely cover the bid and partially cover the ask', async () => {
            // arranging the set
            await dex.limitOrder(1, OrderSide.Ask, 10, 25, OrderFlags.GoodTillCancel, 0)

            // remembering some values to assert
            const eth0Before = await signers[0].getBalance()

            // acting
            const promise = dex
              .connect(signers[1])
              .limitOrder(2, OrderSide.Bid, 10, 20, OrderFlags.GoodTillCancel, 0, { value: 10 * 20 })

            // asserting

            // event for the bid should be emitted
            await expect(promise)
              .emit(dex, 'OrderClosed')
              .withArgs(2)

            // the ask should remain open, and the bid should move to the "closed" pile
            // the previous respective order should be the only closed one
            await expectAllOrderIds(dex, {
              [OrderType.closedBid]: [2],
              [OrderType.openAsk]: [1],
            })

            // the first account should have more eth by the bid's price point
            const eth0 = await signers[0].getBalance()
            expect(eth0.sub(eth0Before)).eq(20 * 10)

            // the second account should have more balance
            const balance1 = await coin.balanceOf(await signers[1].getAddress())
            expect(balance1).eq(100000 + 20)

            // the ask should have less quantity, but retain original_quantity
            const ask = await dex.asks(0)
            expect(ask.quantity).eq(5)
            expect(ask.original_quantity).eq(25)
          })
        })
      })

      // assuming that placing asks works the same, and thus not testing it properly
      // will write out the tests if bugs keep occurring
    })

    describe('when placing an ImmediateOrCancel order', () => {
      describe('when it does not close immediately', () => {
        it('should immediately put the order into the closed pile', async () => {
          const promise = dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.ImmediateOrCancel, 0)

          await expect(promise)
            .emit(dex, 'OrderCanceled')
            .withArgs(1)

          await expectAllOrderIds(dex, {
            [OrderType.canceledAsk]: [1]
          })
        })
      })

      describe('when it closes immediately', () => {
        it('should just behave normally', async () => {
          await dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.GoodTillCancel, 0)

          const promise = dex.limitOrder(2, OrderSide.Bid, 10, 20, OrderFlags.ImmediateOrCancel, 0, { value: 10 * 20 })
          await expect(promise)
            .emit(dex, 'OrderClosed')
            .withArgs(2)
        })
      })
    })

    describe('when placing a TimeInForce order (handled using the next order)', () => {
      describe('when time is still good', () => {
        it('should not do anything with the order', async () => {
          await dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.TimeInForce, Math.floor(new Date().valueOf() / 1000 + 24 * 60 * 60))
          await dex.limitOrder(2, OrderSide.Ask, 10, 20, OrderFlags.GoodTillCancel, 0)

          await expectAllOrderIds(dex, {
            [OrderType.openAsk]: [1, 2]
          })
        })
      })

      describe('when time is up', () => {
        it('should cancel the old order', async () => {
          await dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.TimeInForce, Math.floor(new Date().valueOf() / 1000 + 24 * 60 * 60))
          await network.provider.send('evm_increaseTime', [2 * 24 * 60 * 60])
          await dex.limitOrder(2, OrderSide.Ask, 10, 20, OrderFlags.GoodTillCancel, 0)

          await expectAllOrderIds(dex, {
            [OrderType.openAsk]: [2],
            [OrderType.canceledAsk]: [1]
          })
        })
      })
    })
  })

  describe('#cancelOrder', () => {
    describe('when canceling an ask', () => {
      it('should cancel the order and emit OrderCanceled', async () => {
        await dex.limitOrder(1, OrderSide.Ask, 10, 20, OrderFlags.GoodTillCancel, 0)
        const promise = dex.cancelOrder(1)

        await expect(promise)
          .emit(dex, 'OrderCanceled')
          .withArgs(1)

        await expectAllOrderIds(dex, {
          [OrderType.canceledAsk]: [1]
        })
      })
    })

    describe('when canceling a bid', () => {
      it('should cancel the order and emit OrderCanceled', async () => {
        await dex.limitOrder(1, OrderSide.Bid, 10, 20, OrderFlags.GoodTillCancel, 0, { value: 10 * 20 })
        const promise = dex.cancelOrder(1)

        await expect(promise)
          .emit(dex, 'OrderCanceled')
          .withArgs(1)

        await expectAllOrderIds(dex, {
          [OrderType.canceledBid]: [1]
        })
      })
    })

    describe('when canceling a non-existent order', () => {
      it('should revert', async () => {
        const promise = dex.cancelOrder(100500)

        await expect(promise)
          .revertedWith('Order not found')
      })
    })
  })
})
