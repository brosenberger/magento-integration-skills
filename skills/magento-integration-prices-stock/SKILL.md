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

The trap is where that marker comes from. **A parent created with neither stock data nor its children is stored as out of stock with the marker cleared.** Nobody decided anything — those are simply the column defaults. So it is born in the one state the platform will never move it out of, and the ordinary feed order walks straight into it:

1. create the parent on its own (structure only)
2. link the children in a later call
3. send quantities in a later feed still

Steps 2 and 3 revive nothing — not then, not ever. This is the most common cause of "the import worked but nothing is buyable", and it is not latency: waiting and reindexing change nothing.

**The decisive factor is whether the parent has its children at the moment it is created**, not whether stock exists yet. A parent created *already carrying* its links or options is born with the marker set, because the recompute runs inside that same save and records that it moved the status itself. That single difference explains why this defect looks intermittent between integrations: one that sends structure and links together never sees it, and its authors reasonably conclude the problem is somewhere else.

Measured states at creation, all three composite types:

| How the parent is created | Stored status | Marker | Can it ever recover? |
|---|---|---|---|
| Alone, no stock data | out of stock | cleared | **no** |
| Alone, with stock data saying in stock | in stock | cleared | yes — see below |
| Together with its links or options | out of stock | **set** | yes |

The second row works for a non-obvious reason worth understanding rather than memorising: the parent starts *in* stock, so the first time its children are all unsalable the platform moves it out — and moving it out is the automatic path, which sets the marker. From then on it can come back. Being born in stock buys the marker on the way down.

Three ways to reach the same state without importing at all:

- **Re-saving an out-of-stock parent.** Reported on 2.4.8-p5 and 2.4.9: a routine product write clears the marker again, so a structural feed re-latches every parent that is out of stock when it runs. Treat as version-sensitive — this did **not** reproduce on `2.4-develop` in August 2026, where no later save cleared the marker and the one platform plugin that clears it is variant-only and was never reached on the product-save path. If you are on a released version, assume it happens; if you are diagnosing on trunk, do not expect it.
- **Sending the marker yourself.** It is a writable field on the public stock DTO and it appears in payload examples in the wild. A template that carries it as cleared latches every parent it touches.
- **Enabling a second inventory source.** Parent maintenance is gated on the install being in single-source mode, and that is defined as *fewer than two enabled sources* — not two sources in use. A second enabled source assigned to nothing at all still switches parent maintenance off entirely, freezing every parent's stored status where it stands.

On a multi-source install the source one is the most severe, not the mildest, because a second defect compounds it. The per-stock salability index for composite parents derives each secondary stock's answer partly from the parent's stored flag **for the default stock** — a value scoped to a different stock. Frozen flag plus that veto, on a parent created by an import and therefore starting out of stock, means the parent is unsalable in *every* stock and stays that way. On stock platform code, a multi-source catalogue loaded through the API has no buyable composite parents at all — variant, bundle or grouped; all three are affected, each through its own index query.

The two defects also explain each other, which matters if you are tempted to patch one. The gate exists *because* of the veto: lift the gate alone and the recompute starts writing a correct default-scoped flag, which the veto then propagates into secondary stocks, marking parents unsalable in stocks whose children are fine. That is [magento/inventory#3350](https://github.com/magento/inventory/issues/3350), confirmed by measurement in August 2026: lifting the gate on current code reproduces it exactly. Either half alone is useless or harmful.

Removing both is not available to the platform either, which is why this is still open. The veto is *also* how a merchant's manual out-of-stock on a parent reaches secondary stocks, and the stored marker cannot distinguish "the platform moved this" from "a person moved this" — it reads the same in both cases. The trade-off is written up in [magento/inventory#3466](https://github.com/magento/inventory/issues/3466). For an integration the practical consequence is simply that you cannot wait for a platform fix here; design the feed to avoid the state.

Practical consequences:

- **Create parents together with their links or options, in one call.** This is the cheapest fix and it holds even when the children have no stock yet. If the feed cannot do that, send the parent with explicit stock data marking it in stock; either shape avoids the latch. Both are ordinary payload changes — no patch, no module, no repair run.
- **Send stock before creating parents** if neither of the above is possible. Ordering is not a throughput preference here; it decides whether parents can ever become salable.
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
