---
name: magento-integration-orders
description: >-
  Use when an external system polls Magento 2 orders and writes their progress back — the change cursor, order state and status, comments and history, and reading order lines for money and quantity. Covers a cursor that silently drops orders, transitions that leave no trace at all, and the item rows that must not be summed. Part of the `magento-integration-*` group.
---

# magento-integration-orders — the loop, and the rows that carry money

Group skill under `magento-integration-flow`. Orders are where the traffic reverses: every other family pushes data *into* Magento, orders mostly pull out of it and push status back. Different code, different failure modes, different monitoring. Agnostic of client and transport.

The document side — invoices, shipments, refunds, payment state and creating orders at all — is in `magento-integration-fulfilment`.

## The loop

Four calls and one cursor: pull the orders that changed, decide what to do with each, write back a status and a comment, then the fulfilment documents. Everything below is a detail of those four, and none of it is in any endpoint reference.

## The cursor is where orders go missing

The obvious incremental poll — ask for everything whose change timestamp is greater than the highest one seen last run — drops rows.

**The timestamp has one-second resolution and collisions are ordinary, not theoretical.** Two orders sharing a second happened twice inside one short test run. A strictly-greater cursor pinned to the highest value seen therefore **silently skips every row written in the second it stopped at**. Nothing reports it; the orders simply never arrive.

Two shapes work:

- **Overlap and de-duplicate.** Ask for greater-or-equal to the last value seen minus one second, and discard identifiers already processed. Costs a few redundant rows per run and is the cheaper of the two to get right.
- **Page by identifier within an equal timestamp.** Exact, more code.

**The auto-increment identifier is not a substitute.** It is monotonic and has no timestamp ambiguity, which makes it look like the better cursor — but it only ever finds orders that *did not exist* last run. An order created before the cursor and changed after it never reappears. That is correct for a "pull new orders" job and wrong for a "pull changes" job, and most integrations need both.

The change timestamp does move on everything that matters — invoice, shipment, hold, unhold, cancel, and adding a comment, each verified individually. The one thing that does not move it is adding tracking; see `magento-integration-fulfilment`.

## The order feed is not the admin grid

- **The columns the Adminhtml order listing searches are not the columns the API can filter on.** The grid reads a denormalised table built for it; the API reads the order entity. A poller written by reading the admin's filter UI will query a field that does not exist where it is looking.
- **An unknown field name is a 500, not a 400.** The name reaches the database layer unvalidated and the resulting driver exception is unhandled — for sorts as well as filters. So on this feed **a 500 usually means a misspelled field, not an outage.** Put that in the runbook: the generic message sends people to look at infrastructure for an afternoon.
- **Omitting the search criteria entirely is an error, and the message ships with its placeholder unresolved** — the field name it is complaining about is in the structured parameters, not in the string. Resolve placeholders centrally in the client rather than per call.
- **Prefer a negated set of terminal statuses over a set of active ones** for a standing "still in flight" query. An allow-list of active statuses silently stops matching the day somebody adds a custom status; a deny-list of three terminal ones rarely changes.
- **Absence is not a value.** Null columns are omitted from the response rather than sent as null. A client reading a total with a default of zero reports a zero-quantity order; one indexing it directly raises. Neither is what happened — distinguish "absent" from "zero" explicitly.
- **Documents are their own searchable feeds.** For a finance sync, polling the invoice feed on its own creation timestamp is far smaller than reading orders and walking their document collections.

Filter combination, paging while writing, and sorts that silently do nothing are in `magento-integration-querying`.

## No endpoint sets an order's state

The mental model to unlearn first. **State moves as a side effect of creating documents**, not by assignment:

- The first invoice moves an order into processing; being fully invoiced and fully shipped moves it to complete; a full refund closes it.
- Hold, unhold and cancel are the *only* direct transitions with their own calls.
- There is no route that sets the state field, and an integration that thinks in terms of "set the status" will fight this for weeks.

Writing a state directly is possible through the repository-save route, and it is a trap — see `magento-integration-fulfilment`, which covers what that route accepts.

## A comment cannot cross states

The comment endpoint looks like the status-setting endpoint. It is not.

**A status is only accepted if it is bound to the order's *current* state.** A fresh order's state has exactly one status, so it accepts only the status it already has; anything else fails naming the status rather than the state, and nothing in the message explains the rule. A comment carrying **no status at all** skips that validation entirely, keeps the current status, and still writes the history row — that is the safe form for an operational note.

**The rule is also the mechanism for a real ERP sub-state.** The allowed set is read from configuration, so a custom status assigned to the state an order is already in becomes a legal value — and once written it is filterable, so "everything the ERP has flagged as picked" is one query. The assignment itself has no REST route: it is admin configuration or a data patch, and it belongs in the deployment rather than the integration.

## Hold, unhold and cancel write no history at all

The finding that justifies pairing every transition with a comment. After a hold, an unhold and two cancels, the status-history table held exactly **one** row across the whole test store — the one comment that was posted explicitly.

The admin's *Comments History* block is built from that table. So an order the integration put on hold, took off hold and cancelled shows **nothing** about any of it: whoever opens it later sees a cancelled order with no reason and no actor.

**Magento will not record what your integration did. You have to.** Two calls per event, not one — the transition, then a comment. Carry the external system's own reference in the comment text; it is the only place a Magento-side reader can find out which external process did this. Set the customer-notification and storefront-visibility flags off on operational notes; both round-trip on read, and no mail was sent for any of them.

## Reading order lines: which rows carry money

Composite products emit a parent row *and* child rows, and **which rows carry the money depends on the product type**. Summing every row on a test order gave 260 against a real subtotal of 199.

| Type | Parent row | Child rows |
|---|---|---|
| simple | the price | — |
| variant parent | the whole price | zero — and the tax-inclusive price is null rather than zero |
| bundle (dynamic pricing) | the aggregate | **their own real prices**, which sum to the parent |

So a variant parent is safe to sum naively and a bundle is not. **Money and quantity come from the rows with no parent reference**; those reconcile exactly against the order header. The child rows exist to say what to pick and ship, never what to bill.

**Discount breaks that rule, on the same table, in the same order.** A bundle parent aggregates the row total and the tax and aggregates **nothing** of the discount — the children carry all of it. So the line total, the quantity and the tax must be summed over parent rows only, while the discount must be summed over **every** row. One filter does not serve both, and the percentage field sits on the opposite row from the amount, so deriving one from the other fails exactly where it matters.

**The shape that hides the bug:** when a promotion happens to discount a non-composite product, the parent-only sum is correct and a wrong implementation passes completely. The two shapes are indistinguishable from the endpoint and merchandising moves between them without telling anybody. Build the test order with a bundle under a cart-wide rule, or the test proves nothing.

Two more:

- **The order-level discount is stored negative while the per-item values are positive.** Adding instead of comparing produces a number wrong by exactly twice the discount, and it looks plausible.
- **Take the base-currency values** unless the external system genuinely operates per currency. The others move with whatever rate applied that day.

## The order line's SKU is not the catalogue SKU

- A variant parent's row carries the **child's** SKU, so the parent product's own SKU never appears on the order at all.
- A bundle's parent row carries a **synthesised composite** — the bundle key with every selection appended — which exists nowhere in the catalogue and matches nothing in an article master.

**Join on the product identifier, not on the row's SKU.** It resolves correctly for every row and every type. Human-readable detail — the chosen options, their labels, the underlying product name — lives in the item's options blob; build picking lists and invoice descriptions from that, never from the composite SKU.

**Quantities multiply, and a quantity-of-one order hides it.** A bundle child's quantity is the bundle's quantity times that option's selection quantity. A picking list that assumes one component per bundle is wrong for any option configured above one, and nothing in the parent row hints at it.

**Grouped products do not appear at all.** One cannot be ordered by its own key; ordering its children produces plain top-level rows with nothing referencing the grouped parent. It is a storefront presentation device that disappears at the moment of ordering — an external system will never see one and should not model one.

## Verification

- **Write two orders inside the same second, then poll twice.** Both must appear. This is the test that catches the cursor defect, and it fails on a naive strictly-greater cursor.
- **Read the comment trail back** and confirm one row per transition the integration triggered, including the holds and cancels Magento does not log for you.
- **Reconcile three numbers on every order at import**, and refuse the order if any disagrees: line totals over parent rows against the order subtotal, quantities over parent rows against the order quantity, and discount over **all** rows against the order discount. The failure mode here is a number that is merely wrong rather than missing, so nothing else will tell you.
- **Filter on the custom status** and confirm it returns exactly the orders the external system flagged.
- **Watch the mail catcher** while the write-back runs; it should stay empty.

## Anti-patterns

- A strictly-greater timestamp cursor with no overlap.
- The auto-increment identifier as the only cursor on a "pull changes" job.
- An allow-list of active statuses in a standing query.
- Treating a 500 on the order feed as an incident before checking the field names.
- Grouping order lines by SKU — the same SKU appears at two levels; use the line identifier.
- Assuming a transition left a trace.
