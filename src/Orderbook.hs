-- Pure functions that handle changing the state of the OrderBook
-- TODO move this to OrderBook.Internal so we can test private functions.
module Orderbook (
  Price,
  Quantity,
  Direction(..),
  OrderBook(..),
  handleOrder,
) where

import Data.List (partition)

type MktAgentId = (String, Int)
type Price = Float
type Quantity = Int
data Direction = Buy | Sell deriving (Show, Eq, Ord)

--type BookKey   = (Security, Direction)
type BookEntry = (Price, Quantity, MktAgentId)

type OrderReq  = (Direction, MktAgentId, Price, Quantity)
type OrderReq' = (MktAgentId, Price, Quantity)

-- This OrderBook keeps identifying information around because we need that info
-- to handle cancels, fills, and outs.
type OrderPage = [BookEntry]
-- Note that as a consequence of making handleOrder pure, we need to lock the entire book, not just 
-- each page. (That is, we will use something like `Map BookKey (TMVar OrderBook)` for concurrency)
data OrderBook = OrderBook { bids :: OrderPage, asks :: OrderPage } deriving (Eq, Show)

-- Fill the order as much as possible (possibly not at all), returning how much remains to be filled.
-- Also track whose orders were filled and in what quantity, for generating TRADE and FILL messages.
fillOrder :: (Price -> Price -> Bool) -> OrderReq' -> OrderPage -> (Quantity, [BookEntry], OrderPage)
fillOrder cmp (agentId, price, quantity) op = 
    (unfilledQuantity,  removeZeroOrders filledOrders, removeZeroOrders newOb)
  where
    -- keep the previous order info around so we can do less work using scanl
    useOrders :: (Quantity, BookEntry, BookEntry) -> BookEntry -> (Quantity, BookEntry, BookEntry)
    useOrders (quantityToUse, _, _) (p, q, agentId) =
      let 
        remainingQuantity = if p `cmp` price then (max 0 (quantityToUse - q)) else quantityToUse
        usedQuantity = if p `cmp` price then (min quantityToUse q) else 0
      in
        (remainingQuantity, (p, usedQuantity, agentId), (p, q - usedQuantity, agentId))

    orderZero :: BookEntry
    orderZero = (0.0, 0, ("", 0))
    opTraversed = tail $ scanl useOrders (quantity, orderZero, orderZero) op
    (usedQuantities, filledOrders, newOb) = unzip3 opTraversed

    unfilledQuantity = minimum usedQuantities
    removeZeroOrders = filter (\(_, q, _) -> q > 0)

-- Buy if listed price is less than target, Sell if listed price is greater than target.
fillBuy  = fillOrder (<=)
fillSell = fillOrder (>=)

-- Given that the order can't be placed on the book, list it on the book.
-- There's no concept of "partial completion" here.
listOrder :: OrderReq' -> OrderPage -> OrderPage
listOrder (agentOrderId, price, quantity) op =
  let 
    (higherPriority, lowerPriority) = partition (\(p, _, _) -> p == price) op
  in 
    higherPriority ++ [(price, quantity, agentOrderId)] ++ lowerPriority

-- Compose filling the order and listing whatever is left over
handleOrder :: OrderReq -> OrderBook -> ([BookEntry], OrderBook)
handleOrder (dir, agentId, price, quantity) ob =
    (filledOrders, finalOb) 
  where
    (fill, op, otherOp) = if dir == Buy 
      then (fillBuy, asks ob, bids ob)
      else (fillSell, bids ob, asks ob)
    (unfilledQuantity, filledOrders, newOp) = fill (agentId, price, quantity) op
    -- making sure to use the OTHER page from the orderbook.
    finalOtherOp = if unfilledQuantity > 0 
      then listOrder (agentId, price, unfilledQuantity) otherOp
      else otherOp
    finalOb = if dir == Buy 
      then OrderBook finalOtherOp newOp
      else OrderBook newOp finalOtherOp

-- TODO modify OrderBook to support private and anonymized (public) orderbook pages.
-- anonymizeOrderBook :: OrderBook OrderPage' -> OrderBook OrderPage
-- reduction function to present an OrderBook for public consumption.
