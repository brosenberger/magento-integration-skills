---
name: magento-integration-flow
description: >-
  Use when planning or sequencing a Magento 2 data integration — an ERP, PIM or OMS feed pushing catalog, customer or order data. Covers build order, the cross-cutting failure modes every endpoint family shares, reading data back, and when to stop and verify. Entry point for the `magento-integration-*` group skills.
---

# magento-integration-flow — sequencing a Magento data integration

Orchestration skill. Decides **what to build in which order** and encodes the failure modes that recur across every endpoint family. Delegates per-family specifics to the group skills: `magento-integration-catalog-structure`, `-attributes`, `-media`, `-prices-stock`, `-categories`.

Deliberately agnostic about transport and language. Nothing here assumes a particular client, framework, or whether calls are made synchronously, batched, or queued.

## Decision-order justification

1. Use existing thing as-is — Magento's own import (CSV) beats an API integration for a genuine full-catalog load; reach for the API for deltas and for systems that cannot drop a file on the server.
2. Configure — step skipped: sequencing is not configurable.
3. Extend — step skipped: this encodes project process, not code.
4. Rearrange — this skill *is* the rearrangement: existing endpoints, ordered.
5. New — the group skills exist because per-family behaviour does not generalise.

## Build order

Sequence by **who is unblocked**, not by what is easiest.

1. **Catalog structure** — products, their attributes, their variants. Unblocks theme, content, SEO and search simultaneously. Real names, real image dimensions and real attribute sets are what layout work needs; decisions made against sample data get redone.
2. **Media** — separable, and deliberately on a slower cadence than everything else. Photographs do not change nightly.
3. **Prices and stock** — the narrow endpoints. Cheap, frequent, and the wrong thing to do with a full product save.
4. **Categories** — the tree can be attached after the catalog is loaded and reviewed flat.
5. **Customers** — unblocks logged-in behaviour, and is what makes tier pricing testable.
6. **Orders** — depends on both and blocks nobody on the shop side. Also where the traffic reverses: everything above pushes *into* Magento, orders mostly push status *out*.

Overlap 1–4 with a second integrator only if they can avoid touching the same products.

## Cross-cutting pitfalls

These recur in every family. Check each one per endpoint rather than assuming the API is consistent — it is not.

- **Scope is decided by the route, silently.** A scopeless route does not mean "global"; on update it writes a store-level override that shadows the global value forever. Decide per attribute which scope it belongs to, and make the client fail rather than fall back when a scope lookup returns nothing.
- **There is no API-wide error contract.** Some families report per-item failures and apply the good rows; some take the whole batch or none; some accept bad data silently and persist it. Establish the model per family *before* writing retry logic.
- **A success status does not mean the data was stored.** Several endpoints accept a payload, return success, and write nothing. Read back what matters instead of trusting the response.
- **Idempotency is per-endpoint, not per-API.** Adjacent endpoints doing the same conceptual job differ: one upserts, its neighbour fails when the thing already exists. Write retry handling per call.
- **Failure messages carry unresolved placeholders.** The human-readable string frequently omits the value; the value sits in a structured parameters field. Log the structured field or the log is useless.
- **Queued acceptance is not completion.** An accepted batch is a receipt, not a result. Poll for terminal status and treat anything unfinished as an incident; failed operations are not retried indefinitely on their own.
- **There are no cross-resource transactions.** Structure, media, prices and stock are separate writes with no shared rollback. Design for partial state: make each step idempotent, record per-entity progress, make re-running a failed batch safe.
- **Indexer mode decides the runtime.** Update-on-save turns every write into a reindex. Schedule mode plus a drain is the difference between one hour and nine.

## Access, before anything else

Every call needs credentials, and the wrong credential choice fails hours into a run rather than at the start.

- **Use a long-lived integration credential, not an interactive one.** An interactive administrator session token expires on a short fixed lifetime — four hours by default on the tested version. A seven-hour import authenticated that way dies partway through with authorization failures that read like a permissions problem, sending you to inspect roles instead of clocks.
- **Cache the credential rather than re-authenticating per call.** Issuing one is itself an expensive request.
- **Scope the integration account to what it actually needs.** Each endpoint declares the permission it requires; an integration that runs as a full administrator is one compromise away from being a full administrator.
- **Know which endpoints need no credential at all.** A significant part of the surface is deliberately unauthenticated — account creation and guest flows among them — which is a security consideration for the store, not a convenience for the integration. Do not assume an endpoint is protected because it writes.

## Reading data back

Every family here is written about as a write path, but integrations read too — to diff, to reconcile, and to reproduce what the shop shows. Read failures are quieter than write failures: a query is accepted, returns something plausible, and one of its instructions was silently discarded.

See `magento-integration-querying` for the mechanics — filter combination and its hard limit, sorts that silently do nothing, paging safely while writing, and read cost. The one rule to carry into every family: **assume nothing applied until the result proves it did.**

## When you need concrete calls

These skills stay agnostic on purpose: routes, payload shapes and field names are version- and install-specific, and baking them into a skill guarantees they rot. When an actual request is needed, generate it from the target system rather than from memory or from this skill.

**Export the API description from the running install and drive it as a tool**, rather than hand-writing a route index. The platform publishes a machine-readable schema; import it into a collection and expose that collection over MCP, so the concrete calling layer is generated from the same system you are integrating with and regenerates when it changes. See the `postman-collection-mcp` skills for the setup.

Two caveats measured rather than assumed:

- **The published schema is not the whole API.** On one 2.4.8-p5 install the schema endpoint returned 45 paths against 432 routes actually declared in the install's own configuration, identical with and without an admin token. Treat the export as a starting point and confirm the endpoints you need are in it.
- **The declared configuration in the install is the authority on existence.** If a route is not declared there, it does not exist, whatever any documentation or model says. That check is what prevents invented endpoints, and it costs one search.

Everything else in this skill set is behaviour, which no schema describes.

## When to stop and verify

Verify at these points, not at the end:

- After the first structural batch — before loading the rest.
- Whenever a family's error model is assumed rather than observed.
- Before any removal or reset operation, which is where the asymmetries bite.
- After a Magento version change: behaviour documented here has changed between versions before and will again.

The test that matters: **run the sync twice and diff.** A correct integration's second run is a no-op — no new media, no new rewrite rows, no new assignments. If the second run is not a no-op, the first one was not idempotent, regardless of what it reported.

## Anti-patterns

- Ordering the build by what the ERP exports first rather than by who is blocked.
- One retry policy applied API-wide.
- Treating validation failures as retryable; they fail identically forever.
- Chasing atomicity across resources instead of designing for resumability.
- Letting a feed own data a human curates in the admin.
