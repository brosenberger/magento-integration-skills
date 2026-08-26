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

# Not tested

Stated explicitly, because silence reads as coverage:

- **Customer and order behaviour.** Not executed at all. No skill covers them.
- **Deadlocks under parallel writers.** Deliberately provoked with 256 concurrent overlapping writes and **not reproduced** — which says the sandbox is too small, not that the problem is gone.
- **Behaviour at catalog scale.** Rewrite growth and reassignment cost need a catalog far larger than sample data.
- **Reservation behaviour under concurrent orders.** Needs order traffic this pass did not generate.
- **Single-scope topologies.** At least one protective check appears conditional on an entity being visible in more than one scope; that branch was read, not exercised.
- **The permission surface in depth.** Credential lifetime, the bearer-token toggle and basic role scoping were exercised; the full authorization model and the security implications of the unauthenticated endpoints were not.
