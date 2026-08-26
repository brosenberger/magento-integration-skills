---
name: magento-integration-prices-stock
description: >-
  Use when syncing Magento 2 prices, costs, tier prices or stock quantities from an external system. Covers why these never belong in a product save, the opposite error models of the price and stock paths, salable-versus-source quantity, and why a variant parent created before its stock is permanently stuck out of stock. Part of the `magento-integration-*` group.
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

A variant parent's stock status cannot be set directly. It is a **stored flag on the parent**, not a value computed when read — and that distinction is the whole problem, because the usual diagnosis is wrong.

**Reindexing does not fix a parent that will not go in stock.** The index faithfully reproduces the stored flag: the index is right, the flag is stale.

The platform does maintain that flag — a child stock write re-derives the parent from its children — but the rule it applies is asymmetric:

- **Downwards is unconditional.** When every child goes out of stock, the parent always follows them out.
- **Upwards is conditional.** To move a parent back *into* stock, the platform first requires a marker recording that the parent's present status was set automatically rather than by a person. Without that marker it refuses, on the grounds that it would be overruling a human decision.

The trap is where that marker comes from. **A product created without stock data is stored as out of stock with the marker cleared.** Nobody decided anything — those are simply the column defaults. So a parent created before its stock exists is born in the one state the platform will never move it out of, and the ordinary feed order walks straight into it:

1. create parents and children (structure only)
2. link the children
3. send quantities in a later feed

Step 3 revives nothing — not then, not ever. This is the most common cause of "the import worked but nothing is buyable", and it is not latency: waiting and reindexing change nothing.

The marker is also not written once and left alone. **The platform clears it on every product save.** So a parent that is currently out of stock and receives any routine structural update — a description change, a re-save while attaching children — is latched again from that moment. A catalogue can pass go-live and latch itself weeks later, which is why this looks intermittent and unreproducible from the outside.

Three ways to reach the same state without importing at all:

- **Re-saving an out-of-stock parent.** Any product write clears the marker, so a structural feed re-latches every parent that happens to be out of stock when it runs.
- **Sending the marker yourself.** It is a writable field on the public stock DTO and it appears in payload examples in the wild. A template that carries it as cleared latches every parent it touches.
- **Enabling a second inventory source.** Parent maintenance is gated on the install being in single-source mode, and that is defined as *fewer than two enabled sources* — not two sources in use. A second enabled source assigned to nothing at all still switches parent maintenance off entirely, freezing every parent's stored status where it stands.

On a multi-source install the source one is the most severe, not the mildest, because a second defect compounds it. The per-stock salability index for composite parents derives each secondary stock's answer partly from the parent's stored flag **for the default stock** — a value scoped to a different stock. Frozen flag plus that veto, on a parent created by an import and therefore starting out of stock, means the parent is unsalable in *every* stock and stays that way. On stock platform code, a multi-source catalogue loaded through the API has no buyable composite parents at all — variant, bundle or grouped; all three are affected, each through its own index query.

The two defects also explain each other, which matters if you are tempted to patch one. The gate exists *because* of the veto: lift the gate alone and the recompute starts writing a correct default-scoped flag, which the veto then propagates into secondary stocks, marking parents unsalable in stocks whose children are fine. That is a known, still-reproducible regression. Either half alone is useless or harmful.

Practical consequences:

- **Send stock before creating parents.** Ordering is not a throughput preference here; it decides whether parents can ever become salable.
- **Never send the automatic-status marker.** Strip it out of payload templates rather than echoing back whatever a read returned.
- **On multi-source, verify that composite parents are salable at all** before launch, rather than assuming stock feeds will sort it out. Reconciling the stored flag is not sufficient on its own there.
- **Repairing a stuck parent takes two steps:** restore the marker *and* re-derive the status. Restoring the marker alone only makes the next child write effective, which may never come.

The older checklist still applies underneath — children created before their quantities, a source not linked to the stock the website sells from, disabled or off-website children, outstanding reservations — but check the parent's own stored flag before any of them.

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
