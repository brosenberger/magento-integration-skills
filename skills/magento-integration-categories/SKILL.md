---
name: magento-integration-categories
description: >-
  Use when an external system needs to create, assign or remove Magento 2 categories. Covers the missing natural key, the two assignment paths and their asymmetric semantics, why removal needs its own call, and the rewrite bloat that follows reassignment. Part of the `magento-integration-*` group.
---

# magento-integration-categories — an entity with no natural key

Group skill under `magento-integration-flow`. Agnostic of client and transport.

## The root problem

Products have a stable business key. **Categories have none.** Identifiers are auto-increment and therefore environment-local, names are scope-dependent and repeat across branches, slugs are unique only among siblings, and the path is a chain of the same auto-increment identifiers. Nothing in the stock schema is stable across a database refresh.

Everything below follows from that.

**Give categories the key the platform does not.** Add a dedicated external-identifier attribute, write it on creation, and resolve identifiers at runtime by querying it. Build the whole map once per run and cache it for the duration; never resolve per product, and never persist a resolved identifier anywhere outside the run.

Hardcoding a category identifier — in config, in the external system, or in a mapping file — is the defining mistake of category integration. It does not fail loudly. It assigns products to a plausible-looking wrong category after the next environment refresh.

## Assignment has two paths with different semantics

- **From the product side**, as part of a product write: convenient, and the wrong default for a feed.
- **From the category side**, one assignment at a time: additive, and what a diff-driven integration should use.

The asymmetry that catches people: **a product-side array does not express removal.** Sending a shorter list is not a deletion — the assignments that are missing from it simply stay. Sending an empty list, however, removes everything, including whatever a merchandiser curated by hand.

So assignments only ever accumulate unless you remove them explicitly, and the only blunt instrument available removes far too much.

## Removal is its own operation, and it is not idempotent

Removing one assignment requires the category-side removal call. It succeeds once. Calling it again — or calling it for an assignment that never existed — **fails**, and the failure cannot distinguish "already removed" from "never assigned".

That is backwards from the add path, which *is* idempotent. Design for it: treat "not currently assigned" as the desired state reached, not as an error, and keep the two paths on separate retry policies.

## Ownership

Define the subtree the feed owns and diff only within it. The external system knows its own merchandising hierarchy; it does not know about the seasonal category someone built last week. Either compute the diff and drive it through the category-side calls, or read the current assignments, preserve everything outside the owned subtree, and write the union.

## Consequences that surface late

- **Position overwrites merchandising order.** If the feed has no meaningful ordering, omit position rather than sending a constant — a constant flattens every manually ordered category in the store.
- **Products roll up to parents only where the parent is an anchor.** A structurally correct import into a non-anchor tree produces empty parent pages and empty layered navigation, which reads as an import failure and is not one.
- **Category names and slugs are scope-dependent.** Creating categories through a scoped route rather than a global one yields a tree that is right in one store view and wrong in the rest.
- **Deleting a category cascades** to its children and unassigns every product beneath. There is no dry run. A hierarchy renumbering that triggers deletes can remove a subtree in one call.
- **Rewrite rows multiply with assignments.** Reassigning categories across a large catalog regenerates them all and is usually the slowest part of the whole import.

## Reading assignments back

The category side is authoritative for **order**: it returns position per assignment, and the product collection cannot sort by it. A sort on position against products is accepted and silently ignored, so any merchandised ordering has to come from the category endpoint and be joined client-side.

Filtering products by category uses the singular link field. The plural one visible in read responses is not a filter and fails hard rather than quietly — an instance of the general rule in `magento-integration-querying` that a field appearing in a response is not necessarily filterable.

## Verification

- Re-run and confirm the second run changes nothing.
- Check for categories missing the external key — those are unmappable on the next run.
- Check for non-anchor categories with children before believing an "empty category page" bug report.
- Watch rewrite row counts across runs; unbounded growth means the feed is churning assignments.

## Anti-patterns

- Hardcoded category identifiers anywhere.
- Using the product-side array to express a removal.
- Letting a nightly feed own categories a human curates.
- Deleting to "clean up".
