---
name: magento-integration-attributes
description: >-
  Use when an external system defines Magento 2 product attributes or their options — types, option lists, per-store labels, swatches. Covers what the API accepts, what it silently drops, how to change one translation without deleting the others, and why properties added by third-party modules are usually unreachable. Part of the `magento-integration-*` group.
---

# magento-integration-attributes — what the attribute API will and will not accept

Group skill under `magento-integration-flow`. Agnostic of client and transport.

## The boundary that explains most surprises

The attribute API exposes a **closed field list**. The underlying attribute record has many more properties than that, and every module you install adds more — search weighting, faceting behaviour, display formatting, swatch rendering.

**Anything outside the exposed list is rejected outright**, whichever module owns it, including properties the platform itself defines. Rejection is loud and specific, which is better than silence — but it means a whole class of attribute configuration simply cannot be done through the API.

The only way a module can expose its own attribute properties is by explicitly declaring them as an extension to the interface. Most modules do not. Assume a third-party property is unreachable until proven otherwise, and check the module rather than guessing from the presence of a column.

**Therefore: attribute definition is not integration work.** Search weighting, facet behaviour, swatch rendering and display formatting are presentation and merchandising decisions. Put them in a versioned migration, and let the external system own attribute *values* on products rather than the attributes themselves. If a feed genuinely must create attributes, accept that it creates them half-configured and that a migration has to complete them — or you ship plain dropdowns where you meant swatches.

## Storage follows the input type

You choose the input type; the platform derives the storage type from it. That mapping decides which table values land in and therefore how you query them later. It is not independently settable, so do not try to force it.

Scope is chosen at definition time and is effectively permanent: changing it later leaves the values written under the old scope exactly where they were. Decide global versus per-scope before creating, not after.

## Options

- **Reference options by identifier. Labels are display data.** Keep an external-value-to-identifier map on your side and treat it as durable; rebuilding it from labels breaks the first time someone renames an option. Nothing verifies that map when a product is written: an identifier matching no option is accepted and stored verbatim, so the map has to be validated on your side — see the enumerated-value section of `magento-integration-catalog-structure`.
- **Per-store labels are the translation mechanism** and they work cleanly — one write can carry the default label plus a label per store view, and each scope then resolves its own.
- **The label set is replace-all, and this is where translations get destroyed.** Sending labels for one store view on an option update *deletes every store view you omitted*, and the call succeeds. Updating, adding and removing a translation are therefore the same operation with the same rule: **read the option's current label set, change it, and send it back whole.** Removing one translation means sending the others without it; an empty label removes the row rather than blanking it. Never assemble that set from what the feed happens to know — that is exactly how one language disappears while another is updated.
- **Creating an option that already exists fails.** Duplicate labels are rejected rather than silently accumulating, which protects the option set but makes option creation **non-idempotent**: a retried batch fails on everything that already landed. Treat "already exists" as the success case on a re-run.
- Option creation on a swatch-style attribute produces an option with no swatch value — structurally present, visually blank, with no error. Detecting this needs a check for empty swatch data, not for missing records.
- **The text shown on a text swatch is a different per-store row from the option's label set.** Setting the labels alone leaves the swatch itself showing the admin value, in every store view.
- **Changing an attribute's swatch input type on a populated attribute orphans the swatch rows it already has.** That is a migration, not a configuration toggle — the same class of decision as scope, and equally permanent.
- A swatch attribute used for variants must be globally scoped *and* flagged for use in listings. Miss the second and the swatch renders on the product page but not on category pages, which reads as a theme bug.

## Updating the attribute itself

Two traps sit on the attribute-level update rather than the option one:

- **Naming an option inside an attribute update rewrites that option's labels.** The option survives, but its translations are replaced by whatever the payload carried — usually nothing. Options *not* named are untouched. If the intent is to rename the attribute or change a flag, omit the option collection entirely.
- **An attribute update that omits the attribute's own identifier is treated as a create**, and fails complaining that an attribute with that code already exists. The message describes a duplicate; the cause is a missing field.

## Attribute sets

An attribute the entity's set does not contain is **dropped on write, not hidden**. Nothing fails at the time. Validate set membership as a pre-flight for every attribute the feed intends to write.

## Verification

- Re-run and confirm the second run changes nothing except expected "already exists" responses.
- Check that per-store labels resolve differently per scope, rather than assuming the write took.
- Sweep for options on swatch-style attributes that carry no swatch value.
- Confirm the properties a third-party module added are actually set, since the API cannot set them.

## Anti-patterns

- Letting a feed create options as a side effect of importing a product.
- Blind retries on option creation.
- Expecting search, facet or swatch properties to be settable through the API.
- Treating the exposed field list as the attribute model.
