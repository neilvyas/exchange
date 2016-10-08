Exchange
========

A concurrent, thread-safe exchange orderbook server written in Haskell. 

Orderbook
=========

An orderbook for a given security is a list of offers to buy (the *bids*) and sell (the *asks*). We
conventionally order these by price and time. Traders can buy and sell the stock by checking the
orderbook; if any bids or asks look attractive, the trader can *fill* the order, removing it from the
orderbook. We refer to this as *taking liquidity*, while putting entries into the orderbook, or
making orders, is *providing liquidity*. Some market participants make money off of providing
liquidity by taking both sides of the book and exploiting the *bid-ask spread*, or the difference in
buying- and selling-prices; these market participants are called *market makers*. Note that all of
these actions are anonymized - the orderbook holds no offer-er information, and **Exchange** doesn't
publish who bought or sold.

**Exchange** maintains an orderbook for a fixed list of securities. At present, this list includes 

* **BOND**  
  A security whose value is fixed.
* **A**, **B**, **C**
  Securities that fluctuate in value.
* **ETF**  
  An ETF constructed with the following formula:
    
    10 ETF = 2 A + 3 B + 2 C

but is easily extensible.

RPC
===

Clients communicate with the exchange using the following JSON RPC over a socket.

Public Messages
===============

* **BOOK**  
  The complete current state of the orderbook across all securities. The schema is as follows:

  ```JSON
  {
    "type": "book",
    "timestamp": server_timestamp,
    "book": {
      stock_name: [(price, quantity), ...],
      ...
    }
  }
  ```

  This message is sent every time the state of the orderbook changes.

* **TRADE**  
  Trades that successfully completed, with participants anonymized. You can think of these as
differential updates to the state of the orderbook; for client convenience we provide both **BOOK**
and **TRADE** messages. The schema is as follows:

  ```JSON
  {
    "type": "trade",
    "timestamp": server_timestamp,
    "security": security_name,
    "price": execution_price,
    "quantity": execution_quantity
  }
  ```

  A message is sent for each trade that completes at a given price point, so if someone puts in a
market order and takes the top 4 offers from the orderbook, 4 messages will be sent (but only one
orderbook message).


Client Actions
==============

Of course, you want to actually participate in the market, so you need to be able to talk to the
exchange. You can accomplish this by writing the following messages to the socket. Note: for any
orders, you must generate and provide an `order_id` to the exchange, so that it can track any
subsequent changes to the status of that order. It is up to you to guarantee uniqueness of these ids;
the server will happily push "incorrect" messages to overlapping `order_id`s.

* **HANDSHAKE**  
  This must be the first message you send on connecting to the exchange. Sending this message
initiates a handshake that registers your client on the server. The schema is as follows:

  ```JSON
  {
    "type": "handshake",
    "name": your_name
  }
  ```

  You can only send this message *once*, so don't rely on it to determine your positions. Do your own
bookkeeping!

* **MARKET**  
  Market-order a given quantity of a security. This is atomic even if multiple orders have to be
filled - i.e. if you ask for a quantity greater than the best price, then we immediately carry over
to filling the next-best offer, without allowing other orders to be placed in between. The schema is
as follows:

  ```JSON
  {
    "type": "market",
    "order_id": order_id,
    "security": security_name,
    "direction": "buy" | "sell",
    "quantity": desired_quantity
  }
  ```

* **LIMIT**  
  The smart way to trade, this order also lets you provide liquidity by listing an order on the
orderbook. As opposed to a market order, a limit order must also specify a *price*. If the order can
be filled immediately, it is, otherwise it is listed on the orderbook. Partially-filled orders behave
exactly as you would expect.

  ```JSON
  {
    "type": "limit",
    "order_id": order_id,
    "security": security_name,
    "direction": "buy" | "sell",
    "price": desired__price,
    "quantity": desired_quantity
  }
  ```

  Let's go through the filling mechanics. If `direction` is `buy`, then all asks currently on the book
less than `price` are filled (atomically), up to your specified `quantity`. If there's still quantity
left in your order, but no satisfactory orders on the book, you add a bid for the remaining quantity
to the book. Similarly for `sell` orders.

  If you're market making, or otherwise trying to provide liquidity, a quick way to add your order to
the orderbook is to bid just above the current highest bid or ask just below the current lowest ask.
  
* **CANCEL**  
  Cancel an offer of yours sitting on the orderbook by `order_id`. Upon success you'll receive an
`out` message. Note that while the `cancel` message is being sent and processed, others can trade
against your order.

  ```JSON
  {
    "type": "cancel",
    "order_id": order_id
  }
  ```

Private Messages
================

* **HANDSHAKE**  
  This is the response the server sends when your handshake has been confirmed and your client
succesfully registered. If and when we implement a supervisor layer, then this will also hold
information about risk limits and cash. The schema is as follows:

  ```JSON
  {
    "type": "handshake",
    "positions": {
      security_name: net_position,
      ...
    }
  }
  ```

  All of your positions should be `0` to begin with, so this basically functions as a listing of
securities on the market. 
  
* **TRADE**  
  When you fill an order on the orderbook, via either a market order or a satisfied limit order, the
server will send this message to confirm to you that the trade went through. The direction is
consistent with the direction provided in the original order. One of these is sent for each different
execution price.

  ```JSON
  {
    "type": "trade_completed",
    "order_id": order_id,
    "direction": "buy" | "sell",
    "price": trade_price,
    "quantity": trade_quantity
  }
  ```

* **ACK**  
  When you make a limit order that can't be satisfied, the remaining quantity is added to the book.
This message just confirms that your limit order made it onto the book. Note that the server uses
`order_id` to tell you which order has been acked.

  ```JSON
  {
    "type": "ack",
    "order_id": order_id,
    "direction": "buy" | "sell",
    "price": price_listed,
    "quantity": quantity_listed
  }
  ```

* **FILL**  
  When you have an order that is sitting on the orderbook and someone trades against it, the server
will notify you with this message.

  ```JSON
  {
    "type": "fill",
    "order_id": order_id,
    "price": price_filled,
    "quantity": quantity_filled
  }
  ```

* **OUT**  
  When your order has been removed from the orderbook, the server will send this message. This
can happen via either the entire order being filled or a `cancel` message successfully received. 

  ```JSON
  {
    "type": "out",
    "order_id": order_id
  }
  ```

* **REJECT**  
  Something went wrong handling your message.

  ```JSON
  {
    "type": "reject",
    "msg": message_body
  }
  ```


Standard Clients
================

Along with the backend, we provide implementations of the following clients:

* **Frontend explorer**  
  Only consumes the public messages and functions as a nice real-time dashboard.

* **Trader**  
  Trades on the exchange, taking liquidity.

* **Market Maker**  
  Provides liquidity to the market by listing offers on the orderbook.
