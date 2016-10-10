module OrderbookTest (
  tests
) where

import Test.HUnit

import Orderbook

(agent1, agent2, trader) = ("AGENT1", "AGENT2", "TRADER")
bidsToUse = [ (49, 30, (agent1, 10))
            , (48, 20, (agent1, 20))
            , (46, 30, (agent2, 30))
            ]
bidsRemaining = [(43, 100, (agent1, 40))]

bidOrderPage = bidsToUse ++ bidsRemaining

asksToUse = [ (50, 30, (agent1, 1))
            , (50, 20, (agent1, 2))
            , (51, 30, (agent2, 3))
            ]
asksRemaining = [(53, 100, (agent2, 4))]

askOrderPage = asksToUse ++ asksRemaining

orderBook = OrderBook bidOrderPage askOrderPage

-- Note that all these tests implicitly also test that priority is maintained.
-- TODO Not sure how to achieve good code re-use here, because you would need to parameterize 
-- literally every input
buyCompletelyFilledTest = TestCase $ do
  let (filledOrders, resultOb) = handleOrder (Buy, (trader, 0), 51, 80) orderBook
  let expectedResult = OrderBook bidOrderPage asksRemaining
  assertEqual "the resulting orderbook," expectedResult resultOb
  assertEqual "the orders filled" asksToUse filledOrders

sellCompletelyFilledTest = TestCase $ do
  let (filledOrders, resultOb) = handleOrder (Sell, (trader, 0), 44, 80) orderBook
  let expectedResult = OrderBook bidsRemaining askOrderPage
  assertEqual "the resulting orderbook," expectedResult resultOb
  assertEqual "the orders filled" bidsToUse filledOrders

buyIncompleteUsageTest = TestCase $ do
  let (filledOrders, resultOb) = handleOrder (Buy, (trader, 0), 51, 70) orderBook
  let expectedResult = OrderBook bidOrderPage ((51, 10, (agent2, 3)) : asksRemaining)
  let expectedFilled = (init asksToUse ++ [(51, 20, (agent2, 3))])
  assertEqual "the resulting orderbook," expectedResult resultOb
  assertEqual "the orders filled" expectedFilled filledOrders

sellIncompleteUsageTest = TestCase $ do
  let (filledOrders, resultOb) = handleOrder (Sell, (trader, 0), 44, 70) orderBook
  let expectedResult = OrderBook ((46, 10, (agent2, 30)) : bidsRemaining) askOrderPage
  let expectedFilled = (init bidsToUse ++ [(46, 20, (agent2, 30))])
  assertEqual "the resulting orderbook," expectedResult resultOb
  assertEqual "the orders filled" expectedFilled filledOrders

buyWithListingTest = TestCase $ do
  let (filledOrders, resultOb) = handleOrder (Buy, (trader, 0), 51, 110) orderBook
  let newbids = [(51, 30, (trader, 0))] ++ bidOrderPage
  let expectedResult = OrderBook newbids asksRemaining
  assertEqual "the resulting orderbook," expectedResult resultOb
  assertEqual "the orders filled" asksToUse filledOrders

sellWithListingTest = TestCase $ do
  let (filledOrders, resultOb) = handleOrder (Sell, (trader, 0), 44, 110) orderBook
  let newasks = [(44, 30, (trader, 0))] ++ askOrderPage
  let expectedResult = OrderBook bidsRemaining newasks
  assertEqual "the resulting orderbook," expectedResult resultOb
  assertEqual "the orders filled" bidsToUse filledOrders


tests = TestList [  TestLabel "buyCompletelyFilledTest" buyCompletelyFilledTest
                 , TestLabel "sellCompletelyFilledTest" sellCompletelyFilledTest
                 , TestLabel "buyIncompleteUsageTest" buyIncompleteUsageTest
                 , TestLabel "sellIncompleteUsageTest" sellIncompleteUsageTest
                 , TestLabel "buyWithListingTest" buyWithListingTest
                 , TestLabel "sellWithListingTest" sellWithListingTest
                 ]
