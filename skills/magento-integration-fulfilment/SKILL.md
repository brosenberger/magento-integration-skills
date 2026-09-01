---
name: magento-integration-fulfilment
description: >-
  Use when an external system invoices, ships, refunds or cancels Magento 2 orders, or creates orders inside Magento. Covers which document routes validate and which persist anything, an over-ship that is silently clamped, payment behaviour configured per method, calls that report success while doing nothing, and order injection that corrupts the inventory ledger. Part of the `magento-integration-*` group.
---

# magento-integration-fulfilment — sales documents, payment state, and the routes that validate nothing

Group skill under `magento-integration-flow`. Covers what an external system *writes* onto an order. The poll loop, order state and reading order lines are in `magento-integration-orders`. Agnostic of client and transport.

## The rule that predicts most of this

**There are two families of sales-document route, and they behave completely differently.** A route named after the collection of documents is a repository save: it persists whatever entity it is handed and validates almost nothing. A route that hangs off a specific order and names an action is the domain service: it validates, it moves the order's state, and it keeps the inventory ledger honest.

Both are declared, both return success, and the difference is invisible until a stock count six weeks later. **Use the order-scoped action routes for every document an integration creates.** The repository routes reject nothing the service routes reject — a credit-memo line for an item that is not on the order, an invoice for an amount unrelated to the order, an order in a state that cannot exist.

The trade is one-sided: the action routes cost an extra read to resolve the line identifiers, and in exchange they validate, transition and reserve correctly.

## Documents key on the order line, never on the SKU

Magento addresses invoice, shipment and refund lines by the **order item identifier**. An external system whose picking lines are keyed by article number has to resolve them through a read of the order first — and a composite order has more item rows than the external system has lines, so the resolution is not one-to-one. See `magento-integration-orders` for which rows those are.

## Partial documents, and where the shipping cost lands

Partials work in both directions. One thing about them is not intuitive and disagrees with almost every external system's own logic:

**The whole shipping cost is charged onto the first partial invoice**, not apportioned across them. An integration that spreads shipping over partial invoices will disagree with Magento on every split order, permanently and quietly.

## Over-shipping is clamped, not rejected

Asking to ship more than remains returns success and writes a shipment for **what was actually left**, not for what was asked. Stock moves by the smaller number too.

So the endpoint neither over-ships nor complains — and **the ordinary response to a timeout, retrying with the full quantity, produces a success and a document that does not match the request.** The two systems' fulfilment records then disagree permanently, and the disagreement was reported as success. **Re-read the shipped quantity after every shipment** rather than trusting the response.

Once nothing remains, both the invoice and shipment paths refuse — with **two stacked validation messages inside one message string, separated by newlines**. A client that pattern-matches on the message breaks the first time a second validation joins the first. Omitting the line list entirely produces the same refusal as sending an exhausted line: the endpoints do not distinguish "everything remaining" from "nothing" once nothing remains.

## An error message can name the wrong field

The invoice validator tests the order's **state** and prints the order's **status**. On a normal order the two agree closely enough that nobody notices; on a mismatched pair the error names a value that is not a problem and a field that is not the reason, and the integrator goes looking at status configuration and finds nothing wrong with it.

Generalise it: **an error names what the message was written to name, not necessarily what the predicate tested.** Confirm the failing condition from the stored state rather than from the wording.

## Refunds

- **Refund at the order level.** The invoice-level refund route crashes with an unhandled type error whenever the requested quantity is greater than or equal to the invoice line's quantity — which is to say, whenever an invoice is refunded in full. A partial refund of the same invoice returns a normal business error, so the route looks fine right up to the case an integration most needs. Measured on 2.4.8-p5; the order-level route does not share the code path and is unaffected.
- **Returning stock is a separate flag**, carried in the call's arguments rather than on the lines. Without it the money moves and the stock does not.
- **A return is a straight source increment with no ledger entry**, which looks asymmetric next to order placement and is correct: the unit was physically deducted at shipment and its reservation compensated then, so there is nothing left to compensate.

## Tracking is invisible to every poller

- Tracking is **push-only, confirmed by re-read**. Adding a track moves neither the order's nor the shipment's change timestamp, and deleting one does not either. An incremental poll on orders or shipments will therefore *never* surface a tracking change, and a downstream notification service keyed on those cursors silently never learns the parcel number. Whoever writes the track is the only party who knows it happened and must tell downstream systems itself.
- **Prefer adding tracking on the shipment call itself.** It is atomic and avoids the window where a shipment exists with no parcel number. A second parcel needs the separate track call, which does validate its order and shipment references — unlike the repository-save document routes. Capability is per endpoint; there is no API-wide contract to lean on.
- **The carrier code is not validated.** An unknown code stores fine and degrades silently in the customer account, where it decides whether the number is clickable. Map the external system's carrier identifiers to the store's configured codes explicitly and fail the mapping loudly, using the generic code where there is genuinely no match rather than inventing one.

## Payment: what is already done is configured per method

**Never invoice unconditionally.** Whether Magento has already invoiced the order is decided by a per-*method* setting, not a per-gateway one — one gateway commonly ships card as authorise-only, its wallet methods as authorise-and-capture, and a pay-later method as neither. Three behaviours, one integration, one configuration screen.

Derive what to do from **the order's own numbers**, never from the method name:

| Read on the order | What the integration should do |
|---|---|
| documents exist, nothing still due | ship only — the payment side is finished |
| no documents, the full amount still due | invoice, capturing at the gateway |
| documents exist and the amount is **still due** | **do not invoice again** — the capture lives at the payment provider |

That third row is a state that disagrees with itself: the invoice document says paid while the order says nothing was collected. Both readings are correct, and there is **no route that completes the payment** when the method cannot capture from Magento — the capture call refuses. For those methods the integration's job is to stop at the shipment and leave money alone.

Invoicing an order that is already fully invoiced fails with two stacked messages, neither of which says the order is already invoiced.

## The capture flag that quietly skips the provider

On authorise-only orders, the invoice call's capture flag decides whether the gateway is contacted at all. **Both values return success and produce a paid invoice with the same paid total** — from the outside they are identical. The difference is one line in the order's history: without capture there is no "captured online" entry, because the provider was never called. The money was booked as received while the authorisation sits there uncaptured, expiring in days to weeks, by which time Magento, the external system and the finance export all agree the order was paid.

**Default the flag to capture**, and send otherwise only where the payment genuinely was collected outside Magento. For offline methods it is irrelevant, which is why it looks harmless in a store that only has offline payments.

**Check the order history for the capture line after every invoice.** Its absence alongside a non-null paid total means the gateway was never called.

## Stopping an order: three different meanings, two silent failures

- **Cancel applies only to what is not yet invoiced.** On an uninvoiced order it cancels everything and releases the reservation. On a partly invoiced order it cancels only the remainder and the order correctly stays in progress, because the invoiced part still has to ship.
- **On a fully invoiced order, cancel returns success with a body of `false`.** No message, no history row, nothing changed. A client that checks the status code and moves on records a cancellation that did not happen. The correct call there is a refund.
- **Voiding a captured invoice returns `true` and does nothing** — state, flags, history and every total untouched. Void applies to an authorisation that has not been captured; once capture has happened there is nothing to void and the endpoint will not say so.
- **Cancelling a specific quantity is not expressible.** The cancel operation takes an order and nothing else; a line list is accepted and ignored, cancelling everything. No interface anywhere in Magento cancels part of a line. It is reachable through the repository save, at the price of the domain layer: the cancelled quantity lands, but the order-level cancelled total stays null, **no compensating reservation is written**, and no history row appears. Every finance export then under-reports and inventory keeps units reserved for goods that will never ship. Prefer cancelling the whole remainder and re-creating what should still ship.

**Read the body and re-read the order after any stop operation.** Two of these three report success while doing nothing.

## Creating orders inside Magento

Most integrations should not: normally the storefront creates the order and the external system reads and fulfils it. Creating orders over the API is the uncommon case — a phone-order desk, a marketplace bridge, a historical migration.

**Use the cart sequence.** Create a cart for the customer, add items, ask for the shipping methods the cart offers, set the shipping information, then place the order. The result is indistinguishable from a storefront order: a quote behind it, collected totals, a coherent state and a real stock reservation. Two details that are not obvious from a route list:

- **Setting the shipping information is the load-bearing call.** It carries both addresses, selects the carrier, recalculates totals and returns the payment methods actually available for that cart. Skipping it leaves the quote without an address and placement fails.
- **Estimating shipping methods is not optional in practice**, because the carrier and method codes have to be ones that cart offers and there is no catalogue of them independent of a cart with an address on it.
- **Placement always emails the customer.** The interface takes a cart and a payment method and nothing else, so there is no per-call suppression: a historical backfill emails everyone in it. Disable the transactional mail at configuration level for the duration, and note that this silences it rather than deferring it — see `magento-integration-customers`, where the same switch is the same decision.

## Order injection corrupts the inventory ledger permanently

The repository-save order route is the first hit for anyone searching for order creation, and it is the trap the rule at the top of this skill exists for. It persists whatever it is handed: no quote, no totals collection, no payment, no stock.

Measured consequences, all under a success response:

- **An impossible state-and-status pair is stored verbatim**, including a status the store has never heard of and **a state no code path will ever match** — every state comparison in core and in every extension silently takes the else branch for that order, forever.
- **Totals are stored as sent.** Nothing is recalculated, and the order-level quantity stays null while the line rows carry quantities.
- **The order appears in the admin grid looking ordinary**, which is why this gets found late.
- **No reservation is written.** That looks harmless until the order is fulfilled: the shipment handler writes a *positive* reservation to cancel out a negative one that does not exist, so salable quantity ends up above source quantity. The reservation table is an **append-only ledger, not a derived index — no reindex reconciles it.** Cancelling such an order does the same damage in reverse. An injected order is inconsistent from the moment it is written and every legitimate event applied to it afterwards makes it worse.
- **It is not one bad endpoint.** The invoice and credit-memo repository routes behave the same way: an invoice for an arbitrary amount with no lines, against an unrelated order, is accepted and marked paid — and it appears in the document feed a finance sync polls.
- **Sending an existing identifier rewrites that order as a partial merge.** The permission behind it is the ordinary sales-write resource, so **any credential that can create an order can rewrite every existing one**, and the queued path carries both traps at scale.

Magento's own reservation-consistency command detects all of it and exits non-zero. Run it after any bulk order creation; it is the cheapest way to find out whether something has been injecting orders, and most people running an integration have never heard of it.

## Verification

- After a partial invoice, the invoiced total should equal the line value **plus the full shipping**, not a pro-rated share.
- After every shipment, re-read the shipped quantity and compare it with what was asked — this catches the silent clamp.
- After every invoice, look for the capture line in the order history.
- After any cancel or void, re-read the state and the cancelled total rather than trusting the response.
- After a refund that returns stock, source quantity should rise by exactly the returned quantity with no new reservation row.
- After writing tracking, re-read the shipment. Do not expect a poller to see it.
- After creating orders, run the reservation-consistency check and confirm every order has a quote behind it, a state-and-status pair from the shipped mapping, and an order-level quantity matching its lines.
- Place one test order **per payment method**, record whether an invoice appeared unasked, and repeat the pass after every payment-module upgrade. Derive nothing from the method's name, from another project, or from this skill: a payment module can place the order into review, capture from a webhook, or create the invoice itself, and capability is five independent flags — a method that captures fully but not partially will accept a partial invoice and then fail on the capture.

## Anti-patterns

- Repository-save document routes anywhere in an integration.
- Keying fulfilment on SKU.
- Invoicing unconditionally, or apportioning shipping across partial invoices.
- Sending the non-capturing flag on an online method because it "worked in testing".
- Treating a success status as success on cancel or void.
- Voiding a captured invoice instead of refunding it.
- Trusting the admin grid as evidence an order is sound.
