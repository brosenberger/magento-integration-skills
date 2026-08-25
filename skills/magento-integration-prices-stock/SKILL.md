---
name: magento-integration-prices-stock
description: >-
  Use when syncing Magento 2 prices, costs, tier prices or stock quantities from an external system. Covers why these never belong in a product save, the opposite error models of the price and stock paths, and the salable-versus-source quantity trap. Part of the `magento-integration-*` group.
---

# magento-integration-prices-stock — commercial data without a product save

Group skill under `magento-integration-flow`. Agnostic of client and transport.

## The one rule

**Price and stock deltas never justify a full product save.** Both have dedicated narrow paths that accept many entities per call and skip the product repository entirely. A nightly price file applied as thousands of product saves is the single largest avoidable cost in a Magento integration, and it is avoidable by choosing a different endpoint, not by tuning anything.

Full product saves are for *structural* change. Price, cost, tier price and quantity are not structural.

## The two error models are opposites — this is the whole skill

Price and stock look like the same kind of endpoint. They behave in opposite ways on both axes, and code written for one silently corrupts data when pointed at the other.

| | Price paths | Stock path |
|---|---|---|
| Failure granularity | **Per item** — good rows apply, bad rows are reported | **Whole batch** — one structural error rolls everything back |
| Bad data | Rejected and reported | **Accepted silently and persisted** |
| Return value | A failure list; empty means everything applied | Nothing meaningful — the response says nothing about success |

Consequences to design for:

- On the price side, **read the failure list and interpolate the structured parameters** — the message string alone frequently names no entity. Feed those into a retry set.
- On the stock side, **validate entity identifiers before sending**. Nothing downstream will tell you a quantity was written against an identifier that does not exist, and the row persists as an orphan nothing will ever read.
- Keep stock batches small enough that an all-or-nothing rollback is cheap to retry.
- Negative and nonsensical quantities are not rejected. Range-check client-side.

## Salable quantity is not the quantity you wrote

The number the storefront sells against is source quantity minus outstanding reservations, and reservations are event-driven. Three consequences:

- **Never "correct" quantities by overwriting them from an export.** The export was generated before the orders placed since; overwriting discards them.
- Sync source quantities and let the platform own reservations. When the numbers drift, look at reservations before looking at the import.
- A source that is not linked to the stock the website sells from yields zero salable quantity while every write reports success.

## Pick one stock representation and stay on it

There is a modern multi-source path and a legacy single-source view of the same data. Writing through both produces two indexes that disagree, and different storefront paths read different ones — so the same product is in stock on its own page and absent from listings. Choose one, and make mixing it a review-blocking rule.

## Parent products derive their status

A variant parent's stock status is computed from its children; it cannot be set. When a parent looks wrong, the cause is almost always one of: children created before their quantities, a source not linked to the right stock, disabled or off-website children, outstanding reservations, or simply the indexer not having caught up. Check in that order before touching the import.

## Verification

- Re-run the delta and confirm the second run changes nothing.
- Compare source quantity against salable quantity for a sample, and reconcile the difference against reservations rather than assuming a bug.
- Sweep for stock rows whose entity no longer exists — the residue of silently accepted bad identifiers.
- Confirm the price scope you are writing at is the scope the store actually resolves.

## Anti-patterns

- One retry policy shared between the price and stock paths.
- Trusting a success response from the stock path as evidence anything was stored.
- Full product payloads for a price change.
- Reconciling stock by overwriting rather than by reading reservations.
