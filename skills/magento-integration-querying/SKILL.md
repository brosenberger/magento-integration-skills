---
name: magento-integration-querying
description: >-
  Use when an integration reads data out of Magento 2 — querying, filtering, paging, sorting, reconciling, or reproducing what a storefront shows. Covers the filter-combination model and its hard limit, the reads that silently do nothing, and paging safely while writing. Part of the `magento-integration-*` group.
---

# magento-integration-querying — reading data out without silently losing rows

Group skill under `magento-integration-flow`. Covers **query mechanics**, which are the same for every entity. Family-specific read traps stay with their family: what a category listing actually contains lives in `magento-integration-catalog-structure`, and merchandised ordering in `magento-integration-categories`.

Agnostic of client and transport.

## The filter-combination model, and the shape you cannot express

One rule covers everything:

- Conditions in **different** filter groups are **AND**-ed.
- Conditions within the **same** group are **OR**-ed.

That is the whole model, and it has a hard limit that is expensive to discover late: **`(A AND B) OR (C AND D)` is not expressible.** There is no nesting. A feed that needs that shape needs two queries and a client-side union, and finding out at integration time is far cheaper than finding out when a reconciliation report is wrong.

Two consequences that follow directly:

- A bounded range needs its lower and upper conditions in **separate groups**. Put both in one group and they OR — which matches nearly everything and looks like the filter was ignored.
- Membership in a set is one condition with a set operator, not several equality conditions. Both work; the set operator says what it means and is shorter.

Two operators are easy to miss because most write-ups omit them: a **negated set-membership** test for multi-value fields, and a **greater-or-equal variant** that exists alongside the usual comparison family. Both are implemented in the query builder. Worth knowing before writing a client-side filter to compensate for one you assumed was missing.

**The parameter names in the URL are not the names in code.** The query form uses underscores; the object form used in application code uses camel case, and most published examples show the second. Pasting a camel-cased name into a query produces either a silent no-filter — every row returned, looking like a filter that matched everything — or a validation failure, depending on version. This is the first thing to check when a count comes back higher than expected.

**A collection read needs at least one criteria key present.** With none at all the request fails rather than defaulting to everything, and the message ships with its placeholder unresolved. Always send a page number at minimum.

One documented limit applies everywhere: **only top-level fields are searchable.** Anything nested behind an extension or custom-attribute container cannot be filtered on directly, and attempting it fails as a storage-layer error naming a column rather than as a validation message — which reads like a bug in your query rather than an unsupported operation.

The same shape catches EAV attributes: an attribute reachable in the flattened form of the entity filters normally, and one that is not produces a storage-layer complaint about a missing column. Where an attribute genuinely has to be filtered on, the search-engine-backed endpoint or a GraphQL query answers it; filtering client-side after reading everything does not scale, and rebuilding the flat form to include the attribute is a store-wide decision rather than an integration one.

## Reads that silently do nothing

The recurring failure. A query is accepted, returns a plausible result, and one of its instructions was quietly discarded.

- **A sort on a field the collection cannot reach is accepted and ignored.** Not an error, not a warning — just unsorted data in whatever order the storage returned. The cheapest detection is to **request the same query ascending and then descending**: if the order is identical, the sort never applied. Make that a test, not an inspection.
- **A field appearing in a read response is not necessarily filterable.** Read shape and query shape are separate contracts, and the mismatch fails inconsistently — sometimes ignored, sometimes a server error naming nothing useful.
- **Filters do not reproduce storefront logic.** A query returns entity rows. Visibility, enablement, price rules and stock-based exclusions are applied on top by the storefront. A query that looks like a listing is not one until every one of those is filtered for explicitly — and some of them cannot be expressed as filters at all.
- **A scope in the route scopes attribute *values*, not the result set.** Reading through a store-scoped route does not restrict results to that scope's entities. If you need that restriction, filter for it.

Treat every one of these the same way: **assume nothing applied until the result proves it did.**

## Paging while writing

**Never page a query while writing to the same entities.** Offset-based paging assumes a stable result set; concurrent writes shift rows between pages, so records are silently skipped or returned twice. Neither shows up as an error, and a reconciliation built on it is quietly wrong.

Two workable approaches:

- Snapshot the identifiers first in one pass, then fetch detail by identifier.
- Sort on a stable key and page by *that key's last value* rather than by offset, so a shifting result set cannot move rows across a page boundary.

Also worth knowing: paging past the end of a result set does not always behave as a clean empty response. Bound the loop on a count you trust, not on the assumption that an empty page is the terminator.

## Cost

Reads are cheap individually and expensive in aggregate. Two rules that survive contact with a real catalog:

- **Do not read one entity at a time to decide whether to write it.** Two calls per entity to avoid one unnecessary write is a bad trade at volume. Hash the payload on your side and skip rows whose hash has not changed since the last successful run.
- **Request only the fields you need** where the API supports narrowing the response. Full entity payloads at catalog scale dominate transfer time and memory. Two mechanics worth knowing: the projection is **not part of the filter model** — it is its own parameter and combines with the criteria freely, despite a long-standing report that they cannot be used together — and on a **list** endpoint the projection has to name the collection wrapper and the total, not the entity's own fields, or it returns nothing useful. On a single-entity route the same names are flat. This is the highest-value parameter on the read path for a two-stage poller: a cheap change-detection sweep, then a full fetch of only what changed.

The exception is media, where reading before writing genuinely pays — see `magento-integration-media`.

## Verification

- For any query with a sort, confirm ascending and descending actually differ.
- For any query intended to mirror a storefront view, compare the count against what the storefront shows and reconcile the difference deliberately rather than assuming.
- For any paged read that runs alongside writes, confirm the total processed matches the total expected — a mismatch is the paging problem, not a coincidence.

## Anti-patterns

- Assuming a filter or sort applied because the response was successful.
- Camel-cased criteria names in a URL.
- Nesting logic that the filter model cannot express, then trusting the result.
- Offset paging over a set being written to concurrently.
- Reading each entity before writing it.
- Treating a collection query as equivalent to a storefront listing.
