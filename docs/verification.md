---
type: Verification
title: Verification — how the behavioural claims were established
description: The install everything was executed against, the claims that contradicted prevailing advice, and what was deliberately not tested.
resource: https://brocode.at/blog/
tags: [magento2, verification, testing, provenance]
sources:
  - resource: https://magento2-sandbox.ddev.site
    title: magento2-sandbox — Magento Open Source 2.4.8-p5, Luma sample data, production mode
  - resource: https://brocode.at/blog/
    title: Article series carrying the per-family measurements and verification records
generated:
  by: claude-opus-5
  at: 2026-08-25T00:00:00Z
verified:
  - by: magento2-sandbox (Magento Open Source 2.4.8-p5)
    at: 2026-08-25T00:00:00Z
  - by: magento2-sandbox (Magento Open Source 2.4.8-p5, second website) — customer pass
    at: 2026-08-31T00:00:00Z
  - by: magento2-sandbox (Magento Open Source 2.4.8-p5) — order pass, stand-in gateway
    at: 2026-09-01T00:00:00Z
status: stable
stale_after: 2027-02-25T00:00:00Z
---

# The install

Every behavioural claim in these skills was executed against a running install, not taken from documentation and not inferred from reading source. Both of those were wrong about several of these claims.

| | |
|---|---|
| Magento | Open Source **2.4.8-p5** |
| Data | Luma sample data |
| Mode | Production |
| Scopes | One website, four store views |
| Search | OpenSearch 2.19.1 with Elasticsuite 2.12.1.1 |
| Queue | MySQL — deliberately no message broker |

The multi-store-view setup matters: several of the sharpest findings only appear once a second store view exists, and a single-scope install would have missed them entirely.

# Why execution rather than reading

Reading source is not sufficient, and this is not a theoretical concern. A template example was once written after confirming both methods existed — they did, on a different class than the one in scope, and the framework degraded the call silently rather than failing. Only running it surfaced that.

The costly errors were never wrong *identifiers*, which review catches. They were wrong *mechanisms*: plausible sentences about how a subsystem behaves, several of which were true in an earlier version and quietly stopped being true. Nothing about those looks like a mistake.

# Claims that contradicted prevailing advice

Each of these is widely repeated and was false on the tested version:

- A queued bulk path requires a dedicated message broker. It does not; it ran end to end on the database queue with no broker installed.
- There is no way to create an order for a known customer with an administrator credential. There is: cart creation for a customer is declared behind an ordinary permission, and the five-call cart sequence produces an order indistinguishable from a storefront one.
- The product-side collection that appears only in read responses is ignored on write. It assigns; the same save handler seeds its working set from it.
- The product-side category collection replaces the assignment set. It merges; only an empty collection clears.
- Repeated imports accumulate duplicate attribute options. They are rejected outright.
- An attribute value outside the entity's attribute set is written and merely hidden. It is not written at all.
- Two long-standing pagination and filtering defects on a listing endpoint. Both fixed.

On the read side, three failures were confirmed rather than assumed: a category filter returning 347 products where the storefront lists 32, a sort on position accepted and silently ignored (identical order ascending and descending), and the plural category-link field returning a server error rather than filtering.

The lesson is directional: where a claim here contradicts common advice, that is usually because the advice aged rather than because it was ever wrong.

# A correction made during verification

Worth recording because it is the failure mode this bundle warns about, committed by the bundle itself.

An earlier version reported that the published API schema returned 45 paths regardless of credential, and concluded the export was a fragment of the real surface. Re-measuring with a freshly issued credential gave **325 paths and 410 operations** against 344 distinct declared URL templates — roughly 95% coverage, and clearly permission-scoped: 45 anonymous, 71 for a catalog-only integration credential, 325 for an administrator.

The original request had almost certainly outlived its credential's short lifetime and was being served anonymously. Nothing in the response said so; it returned a valid schema, just a smaller one. **A successful response to an unauthenticated request looked exactly like a successful response to an authenticated one** — which is the same class of silent failure documented throughout these skills, and it survived one round of review before being caught.

# The customer and order passes

Both were executed after the initial pass, on the same install.

**Customers**, with a second website added so multi-site behaviour could be measured rather than assumed, and source cross-checks against a development checkout: the anonymous create and the mail it triggers, three scope payloads, per-website uniqueness across two websites, both password validation failures, the address replace-and-recreate, group and tax-class discovery, group assignment requiring authentication, automatic group assignment reversing it, an extension-attribute round trip, newsletter consent both ways, and the customer grid before and after reindex.

**Orders**, on Luma sample data with a single inventory source, offline payment and flat-rate shipping: the change cursor including two orders written inside one second, filter and sort failures on the order feed, every transition's effect on the change timestamp, the status-history table after a hold, an unhold and two cancels, four orders built specifically to expose the item-row rules including a bundle with a per-option quantity above one under a cart-wide rule, partial invoices and shipments, the over-ship clamp, the invoice-level refund crash at three quantities, tracking's effect on both change timestamps, and order injection through the repository routes with the reservation ledger read before and after.

**Payments were measured against a stand-in gateway whose calls always succeed**, so what is recorded is Magento's own bookkeeping — `payment_action` at placement, the capture flag with and without, cancel and void at each stage. No real payment provider was exercised, and the skill says so where it matters.

# The enablement-value pass

Executed 2026-09-07 on the same install, on a two-website topology (three store views on one website, one on the other), prompted by a field report rather than by an audit.

Measured: `catalog_eav_attribute.is_global` for the enablement attribute; four out-of-range writes across two typed scalars, one custom attribute and one bogus option reference, all accepted and stored; the fan-out of a single store-view-scoped write across a website; a default-scope write failing to clear those records; per-store reads across both websites; a price reindex with the invalid value and with the legitimate disabled value, on the affected website and the untouched one; both reset payloads (`null` and empty string) on a numeric, an optional text and a required text attribute, at store-view and at default scope; and a reindex after the default record was removed. Source was read only to explain results already observed — the source model's option list, the grid column's label lookup, and the indexer's join type. Probe products were removed afterwards.

# Not tested

Stated explicitly, because silence reads as coverage:

- **Real payment providers.** Redirect, push and review flows, partial-capture capability, and anything a provider module does inside placement. The per-method test pass in `magento-integration-fulfilment` exists because this cannot be generalised.
- **Two product-write hazards carried from the earlier gap survey** — a global-scope update assigning every website, and a store-scoped update pinning every attribute — are upstream reports rather than findings from this pass, and are marked as such in `magento-integration-catalog-structure`.
- **Deadlocks under parallel writers.** Deliberately provoked with 256 concurrent overlapping writes and **not reproduced** — which says the sandbox is too small, not that the problem is gone.
- **Behaviour at catalog scale.** Rewrite growth and reassignment cost need a catalog far larger than sample data.
- **Reservation behaviour under concurrent orders.** Needs order traffic this pass did not generate.
- **Single-scope topologies.** At least one protective check appears conditional on an entity being visible in more than one scope; that branch was read, not exercised.
- **The permission surface in depth.** Credential lifetime, the bearer-token toggle and basic role scoping were exercised; the full authorization model and the security implications of the unauthenticated endpoints were not.
