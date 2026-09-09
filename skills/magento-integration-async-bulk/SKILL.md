---
name: magento-integration-async-bulk
description: >-
  Use when an integration writes to Magento 2 through the queued path — the asynchronous and bulk routes. Covers the receipt that replaces the entity response, validation splitting into a synchronous all-or-nothing half and a deferred per-item half, the status routes and the unrelated permission that blocks them, and operations that never finish. Part of the `magento-integration-*` group.
---

# magento-integration-async-bulk — the queued write path, and the receipt you cannot cash

Group skill under `magento-integration-flow`. Covers what changes when a write is **queued instead of executed**. The routes are the synchronous ones behind a prefix, the payloads are the same payloads, and the family behaviour is unchanged — so the traps in `magento-integration-catalog-structure`, `-prices-stock`, `-customers` and the rest all still apply, they just arrive later and somewhere else.

What changes is the **result contract**, completely. Every rule below is about that, and about the fact that the queued path's failure modes are quieter than the synchronous path's rather than louder.

Agnostic of client and transport. Sequencing, build order and the broker question stay in `flow`.

## The response is a receipt, not an entity

The queued route does not return what it wrote. It returns a receipt: a batch identifier, one entry per item you sent, and a batch-level error flag.

Each entry carries three things — **a positional index, a content hash of that item, and an accepted-or-rejected flag**. It does not carry an entity identifier, the business key you sent, or a location to fetch later. So:

- **Correlation is positional and it is yours to maintain.** The index in the receipt is the index in your request array, and it is the same index the status routes use to identify the operation. Preserve request order and store the map from index to business key on your side. Nothing on the Magento side reconstructs it, and the batch identifier alone will not tell you which of your rows failed.
- **The content hash is not an idempotency key.** Re-posting a byte-identical batch is accepted again, into a new batch identifier, with the same hashes, and it executes again. Measured. The queue removes none of the duplicate-run risk the synchronous path has — so the *run it twice and diff* test from `flow` is not weakened here, it is the only thing that catches a replay.
- **Queuing a single entity gets you the same receipt.** There is a single-item queued route alongside the batch one; it takes one object instead of an array and returns a one-entry receipt. It does not return the entity either. If any part of the integration needs the created identifier back in the response, the queued path cannot serve it — use the synchronous route for that call.

## Validation splits in two, and the halves fail in opposite ways

This is the part most descriptions of the queued path get wrong, in both directions.

**Structural validation is still synchronous, and it is all-or-nothing for the whole batch.** Types are checked against each field's declaration before anything is queued, exactly as on the synchronous path (`flow`, payload types are per field). One item carrying a string where an integer is declared rejects the **entire request** with an ordinary error naming the field and the expected type. Measured on a two-item batch whose second item had a bad type: the request failed, and the structurally valid first item was never queued and never stored.

Two consequences worth designing around: validate types client-side rather than discovering them per batch, and **keep batches small enough that losing one to a single bad row is cheap to re-send**. A large batch is not free — it is a bigger blast radius for one malformed value.

**Business validation moves to the consumer, and it is per item.** An item that is structurally fine but references something that does not exist is accepted, queued, and fails on its own later. Same measurement, changing only the bad value to a well-typed but nonexistent reference: the good item was created, the bad one failed alone, and the batch reported both.

Nothing in the payload tells you which half will catch a given mistake. Assume both are live and build for partial success.

## Reading the outcome, and the permission that blocks it

Four read routes exist and they answer different questions:

- **Short status** — per-operation state, free-text message and error code, plus the batch's operation count, start time and originating queue topic.
- **Detailed status** — the above plus two things nothing else exposes: **the original payload echoed back**, and **the service's return value**, which for a create is the full stored entity including its identifier. This is the only place the created entity comes back.
- **Per-status count** — a bare integer. Answering "is this batch finished" costs one call per state, or one parse of the status list.
- **Operation search** — despite sitting on the batch path, this lists **operations across every batch**, not batches. There is no route that lists batches.

Two traps in that list. The detailed view carries an entity-identifier field and an entity-link field that look like they exist precisely for correlation; **both stayed empty on every create measured**, including ones that succeeded and returned a stored entity in the result. Do not build on them. And the entity only appears in the *detailed* view, so a poller written against the short one has no path to the identifier at all.

**The blocking finding: reading the status needs a permission unrelated to the write.** All four routes are guarded by an action-log resource under System — nothing to do with the entity family being written. Measured: a credential scoped to catalog only pushed a batch successfully, received an accepted receipt for both items, and was then refused on all three status routes with an authorization error naming that action-log resource. The integration gets a receipt it cannot cash, and the error points at a resource nobody scoping a catalog feed would think to grant.

Grant it explicitly when scoping the credential, and **verify the poller's read access before building the poller** — this failure appears only after the write path already looks finished.

## The states, and what none of them tell you

Five operation states: complete, retriably failed, not-retriably failed, open, and rejected. A client compares small integers here — on the tested version, one through five in that order — which is version-pinned surface, so read them from the install rather than hard-coding them from a blog post.

- **The error code is always zero.** Every failure produced in the pass — an invalid reference on a create, a missing entity on a delete, an unresolvable store — carried the same zero. Zero is falsy in most languages, so a client asking "is there an error code" concludes there was no error. **Classify on the state; log the message.** The free-text message is the only field that differs between causes, and it is the useful one.
- **The success message is not a result.** It names the service class that ran, not what it did. Read the result payload in the detailed view if you need the outcome.
- **Nothing retries a failed operation.** There is no route to retry one — the only retry surface in the platform is an admin grid. A client that wants retry re-sends the item, which makes the family's idempotency rules (`flow`) load-bearing on the queued path too. And *retriably* failed is a label, not a promise that anything will act on it.

## Operations that never run, and evidence that expires

- **An operation only leaves the open state when a consumer claims it.** Queued with no consumer running, it stays open **indefinitely** — nothing times it out and nothing alerts. A poller waiting for a terminal state waits forever, and a stalled consumer is indistinguishable from a slow import (`flow`, the consumer has to actually be running). Give the poller its own deadline; the platform will not supply one.
- **The sweeper that exists does not cover that case.** A periodic job flips operations to *retriably failed* with a generic unknown-error message and the same zero code — but only ones whose processing had already **started**, after a long fixed window. Operations no consumer ever claimed carry no start timestamp and are never matched. So the one automatic failure marker in the system fires on interrupted work, says nothing about why, and leaves the commonest stall untouched. Source-read on the tested version and consistent with the empty start timestamps observed on queued-but-unconsumed operations; not provoked end to end.
- **Batch records expire on a timer and are deleted regardless of state.** A cleanup job removes batches older than a configured number of days — sixty by the shipped default, read from configuration rather than observed expiring — with **no filter on whether their operations completed, failed, or are still open**, and the operations are removed with them. A failure nobody looked at disappears along with its evidence, and so does the identifier you stored to look it up.

The design consequence is one line: **the batch identifier is not durable storage.** Poll to a terminal state promptly, record the per-item outcome on your side, and treat Magento's record as a short-lived cache of something you own.

## What does not change, and what has no queued form

- **Every family rule still applies.** The scope trap in particular: a scopeless queued route writes the same silent default-store override as its synchronous counterpart, at batch scale (`flow`). Enumerated values are accepted unvalidated the same way (`magento-integration-catalog-structure`). Endpoints that report success and store nothing do it here too, just one layer further from the caller.
- **Reads have no queued form at all**, and asking for one fails with a generic "cannot be processed" message that does not mention the reason. Expect to debug that once.
- **Not every write route has a queued twin, and routes taking an identifier in the path need a declared alias** that moves the identifier into each array item. Which routes have one is declared in the install's own async route configuration — a *different* declaration from the synchronous route list, so the existence check in `flow` has to be run against that one. Do not infer a queued route from the presence of its synchronous original.
- The queued path needs no message broker (`flow`).

## Choosing the queued path at all

It buys throughput and costs feedback: no per-item response status, no immediate error, and a correlation problem you now own. That is usually the right trade for a scheduled import and the wrong one for anything a person is waiting on. Where a call needs the created identifier or an immediate validation answer, keep it synchronous — mixing the two within one integration is normal and is not a design failure.

## Verification

- **Before building the poller, confirm the integration credential can read the status routes.** This is the cheapest check in the skill and it fails after the write path already looks correct.
- Send a batch with one deliberately mistyped item and confirm your client handles losing the whole batch, not one row.
- Send a batch with one structurally valid but business-invalid item and confirm your client records the per-item failure against the right business key.
- Confirm the poller distinguishes *still open* from *failed*, and that it gives up on its own deadline rather than waiting for one the platform never sets.
- Re-send a completed batch and diff. A second run that is not a no-op means the family's write was never idempotent — the queue did not make it so.

## Anti-patterns

- Treating the receipt as confirmation that anything was written.
- Expecting the created entity's identifier anywhere in the receipt, or in the correlation fields that look built for it.
- Testing the error code instead of the state.
- Hard-coding the state integers from documentation instead of reading them from the install.
- Batching thousands of rows into one request, where a single type error costs all of them.
- Granting the write permission and not the status permission.
- Storing the batch identifier as the durable record of what happened.
- Sending user-facing writes down the queued path for throughput nobody needed.
- Assuming the queued path validates less than the synchronous one, or that it validates the same.
