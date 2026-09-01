---
name: magento-integration-flow
description: >-
  Use when planning or sequencing a Magento 2 data integration — an ERP, PIM or OMS feed pushing catalog, customer or order data. Covers build order, the cross-cutting failure modes every endpoint family shares, reading data back, and when to stop and verify. Entry point for the `magento-integration-*` group skills.
---

# magento-integration-flow — sequencing a Magento data integration

Orchestration skill. Decides **what to build in which order** and encodes the failure modes that recur across every endpoint family. Delegates per-family specifics to the group skills: `magento-integration-catalog-structure`, `-attributes`, `-media`, `-prices-stock`, `-categories`, `-customers`, `-orders`, `-fulfilment`, and the cross-cutting read path to `-querying`.

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
5. **Customers** — unblocks logged-in behaviour, and is what makes tier pricing testable. `magento-integration-customers`.
6. **Orders** — depends on both and blocks nobody on the shop side. Also where the traffic reverses: everything above pushes *into* Magento, orders mostly push status *out*. The poll loop and the write-back are `magento-integration-orders`; the documents, payment state and order creation are `magento-integration-fulfilment`.

Overlap 1–4 with a second integrator only if they can avoid touching the same products.

## Cross-cutting pitfalls

**Scope is validated asymmetrically, and the silent half is the dangerous one.** Across entities, a value belonging to a *different* website tends to be rejected with a clear error, while an omitted scope or the admin scope is quietly rewritten to the default. The loud failure is the one caught in testing; the silent one reaches production. Measured on customers in `magento-integration-customers`, and the same shape recurs elsewhere.

**Payload types are per field, not per API.** The REST layer type-checks each value against that field's own declaration - the `@param` on the interface setter, or the `type` attribute on an extension attribute - and core is not internally consistent about which it uses for the same *kind* of value. Two boolean-looking flags on the same entity:

```
"is_subscribed": true                → accepted   (declared boolean)
"disable_auto_group_change": true    → 400        (declared int)
"disable_auto_group_change": 1       → accepted
```

So there is no rule to apply. "Send booleans as booleans" is wrong, and so is "send everything as 0/1". A client library that normalises flags one way will fail on roughly half of them, and the failures are per-field rather than per-entity, so partial success across one payload is normal.

The saving grace is that this failure is **loud and informative** - `The "1" value's type is invalid. The "int" type was expected.` names the type it wanted. That is the opposite of the scope handling above, and the two together are the shape to expect: Magento tends to be strict and explicit about *types*, and silent and forgiving about *scope*. Trust a type error to tell you the answer; never trust a `200` to mean the scope you sent survived.

When in doubt, read the declaration rather than guessing: the interface for native fields, `extension_attributes.xml` for extensions.

**A write that succeeds can still undo an earlier one.** Magento reacts to writes with observers and plugins that reassign what you just set - customer group assignment reversed by a later address save is the clearest example. Assume nothing you wrote is still there because the call returned `200`; read it back on the paths that matter.


These recur in every family. Check each one per endpoint rather than assuming the API is consistent — it is not.

- **Scope is decided by the route, silently.** A scopeless route does not mean "global"; on update it writes a store-level override that shadows the global value forever. Decide per attribute which scope it belongs to, and make the client fail rather than fall back when a scope lookup returns nothing.
- **There is no API-wide error contract.** Some families report per-item failures and apply the good rows; some take the whole batch or none; some accept bad data silently and persist it. Establish the model per family *before* writing retry logic.
- **The shape of a route predicts whether it validates.** A route named after a collection of entities is usually a repository save that persists whatever it is handed; one that hangs off a single entity and names an action is usually the domain service that validates, transitions and keeps side effects honest. Both are declared and both return success. Worked out in full for sales documents in `magento-integration-fulfilment`, where the repository routes accept orders that cannot exist — but check it wherever two routes look like alternatives for the same job.
- **A success status does not mean the data was stored.** Several endpoints accept a payload, return success, and write nothing. Read back what matters instead of trusting the response.
- **Idempotency is per-endpoint, not per-API.** Adjacent endpoints doing the same conceptual job differ: one upserts, its neighbour fails when the thing already exists. Write retry handling per call.
- **Failure messages carry unresolved placeholders.** The human-readable string frequently omits the value; the value sits in a structured parameters field. Log the structured field or the log is useless.
- **Queued acceptance is not completion.** An accepted batch is a receipt, not a result. Poll for terminal status and treat anything unfinished as an incident; failed operations are not retried indefinitely on their own.
- **There are no cross-resource transactions.** Structure, media, prices and stock are separate writes with no shared rollback. Design for partial state: make each step idempotent, record per-entity progress, make re-running a failed batch safe.
- **Indexer mode decides the runtime.** Update-on-save turns every write into a reindex. Schedule mode plus a drain is the difference between one hour and nine.
- **A generic failure message is a wrapper, not a cause.** Repositories catch and re-throw as "could not save", discarding nothing but telling you nothing either. The original is attached underneath — read the wrapped exception before changing any code. Guessing at fixtures, permissions or configuration because the top-level message was vague costs hours that one unwrap would have saved.
- **"The indexer has not caught up" is the most over-used diagnosis in this platform.** Some values are computed at read time and genuinely need an index; others are stored flags that something is supposed to recompute and did not. Reindexing cannot repair a stale stored flag — the index will faithfully reproduce it. Establish which kind you are looking at before scheduling a reindex.

## Throughput, and the failures that are not in the API

- **A queued bulk path does not require a dedicated message broker.** This is the most repeated wrong thing about it: the consumer declares no connection and falls back to the database queue unless a broker is configured, and a full queued import ran end to end on a store with no broker installed at all. That was true in an older major version and stopped being true; assuming otherwise blocks imports on infrastructure nobody needs. A broker is still the better choice under real load — it is not a precondition.
- **The consumer has to actually be running.** Cron starts it in most deployments; one started by hand dies with the terminal. Run it supervised with a message cap so it recycles, and remember that a stalled consumer looks exactly like a slow import for hours.
- **The queued path carries the scope trap at bulk scale.** A scopeless queued route writes the same silent default-store override as its synchronous counterpart. Put the scope in the route there too.
- **Indexer mode decides the runtime.** Beyond schedule-versus-save: the change-log tables grow to millions of rows during a large run and cron has to drain them, and for a full replacement it is often faster to turn indexing off entirely, import, and reindex once. Cache invalidation lands at the end regardless, so schedule imports away from traffic peaks and warm afterwards.
- **Parallel writers deadlock.** Writers touching the same entity, index and rewrite tables produce lock-wait failures. Partition work by a hash of the entity key so one entity is only ever touched by one worker, cap concurrency low and measure — past the deadlock threshold, more workers *reduce* throughput — retry the deadlock error with jittered backoff, since unlike a validation failure it is legitimately retryable, and never run two imports of the same catalog concurrently. **Honest limit:** a deliberate attempt to provoke this on a small sandbox produced no deadlock at all, so treat it as sound practice that one verification pass could not reproduce a failure for rather than as measured behaviour.
- **The API shares the storefront's process pool** unless it is separated. A hot import can take the shop down while every Magento metric looks healthy. Give the API its own pool.

## Not everything has an API

Before designing around an endpoint, check it exists — and expect the gaps to cluster in one place. **The data plane is well covered; the control plane largely is not.** Configuration, cache and index control, admin users and roles, website and store-view creation, email templates, widgets and import profiles have no write surface. Neither do catalog price rules, which catches promotions work specifically because *cart* price rules do exist. A couple of merchant-facing features built before the API-first era — wishlists, reviews — have no REST surface but do have a GraphQL one.

Two consequences:

- **Check REST, then GraphQL, then accept it is configuration or CLI.** A feature added after the storefront moved to GraphQL often landed there instead, and a feature older than both landed in neither.
- **Scoped configuration cannot be reset over the API at all**, and the CLI can set but not unset it. That is the configuration-level relative of the attribute-scope reset in `magento-integration-catalog-structure`.

Where a gap blocks the work, the supported answer is a small module declaring its own route over an existing service — not a database write, and not a CLI shelled out from an integration.

## Access, before anything else

Every call needs credentials, and the wrong credential choice fails hours into a run rather than at the start.

- **Use a long-lived integration credential, not an interactive one.** An interactive administrator session token expires on a short fixed lifetime — four hours by default on the tested version. A seven-hour import authenticated that way dies partway through with authorization failures that read like a permissions problem, sending you to inspect roles instead of clocks.
- **Cache the credential rather than re-authenticating per call.** Issuing one is itself an expensive request.
- **Scope the integration account to what it actually needs.** Each endpoint declares the permission it requires; an integration that runs as a full administrator is one compromise away from being a full administrator.
- **Know which endpoints need no credential at all.** A significant part of the surface is deliberately unauthenticated — account creation and guest flows among them — which is a security consideration for the store, not a convenience for the integration. Do not assume an endpoint is protected because it writes.
- **The declared permission on a route is not the effective one.** Configuration can rewrite it. There is a store setting whose documented purpose reads like *restricting* anonymous access and whose actual effect is to **grant** it: switching it on moved a catalogue read from refusing an unauthenticated caller to returning the entire catalogue — every product, price and stock figure — to anyone who asks. Measured, not inferred.

  Two consequences. Never conclude an endpoint is protected from its declaration alone; **call it with no credential and see**. And treat that setting as a publication decision about your catalogue rather than an integration convenience — if a client cannot authenticate, fix the client.
- **Authenticate an integration the supported way — sign the requests.** An integration credential is issued as a set (consumer key and secret, token and secret) and the signing handshake is what the platform supports. Implement that.
- **Do not enable the standalone-bearer-token setting to avoid it.** Passing an integration's access token as a plain bearer header is deprecated and **disabled by default**; the setting that re-enables it is store-wide, so turning it on to unblock one client re-opens the shortcut for every integration on the store. That is a much larger blast radius than the problem it solves. Treat "just switch it on" as a change to the store's security posture, not a configuration detail.
- **Know what that failure looks like, because it lies.** With the setting off, calls fail reporting that the consumer is not authorized for a resource the integration demonstrably *does* have. It reads as a permissions problem and is not one. Check the toggle before auditing the role — and then fix it by signing requests, not by flipping the toggle.
- **Permission scoping is real and worth using.** A credential restricted to what it needs is refused elsewhere with an error naming the missing resource — and the same scoping shapes the API description the install will hand you.

## Reading data back

Every family here is written about as a write path, but integrations read too — to diff, to reconcile, and to reproduce what the shop shows. Read failures are quieter than write failures: a query is accepted, returns something plausible, and one of its instructions was silently discarded.

See `magento-integration-querying` for the mechanics — filter combination and its hard limit, sorts that silently do nothing, paging safely while writing, and read cost. The one rule to carry into every family: **assume nothing applied until the result proves it did.**

## When you need concrete calls

These skills stay agnostic on purpose: routes, payload shapes and field names are version- and install-specific, and baking them into a skill guarantees they rot. When an actual request is needed, generate it from the target system rather than from memory or from this skill.

**Export the API description from the running install and drive it as a tool**, rather than hand-writing a route index. The platform publishes a machine-readable schema; import it into a collection and expose that collection over MCP, so the concrete calling layer is generated from the same system you are integrating with and regenerates when it changes. See the `postman-collection-mcp` skills for the setup.

Two things worth knowing about that export:

- **It is permission-scoped.** The schema reflects what the requesting credential may call — measured on one install as 45 paths anonymously, 325 with an administrator credential, and 71 with an integration credential restricted to catalog. Generate it with the credential the client will actually use, and the result describes exactly that client's reachable surface rather than a theoretical one.
- **The declared configuration in the install is the authority on existence — and only on existence.** If a route is not declared there it does not exist, whatever any documentation or model says, and that check is what prevents invented endpoints. It is *not* authoritative on authorization: the permission a route declares can be rewritten by configuration at runtime, so the only reliable answer to "is this endpoint reachable, and by whom" comes from calling it.

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
