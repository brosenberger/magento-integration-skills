---
name: magento-integration-catalog-structure
description: >-
  Use when an external system creates or updates Magento 2 products — the structural half of a catalog feed. Covers scope fallback, what "partial update" really means, variant sequencing, product types, link replacement, and the writes that report success and store nothing. Part of the `magento-integration-*` group.
---

# magento-integration-catalog-structure — products, variants and the silent writes

Group skill under `magento-integration-flow`. Build this first: a catalog that is loaded but not yet priced, stocked or categorised already unblocks layout, content and search work. Agnostic of client and transport.

## Scope is the first decision, and the default is wrong

The route decides which scope a write lands in, and the unscoped form is not "global". On creation it behaves globally; **on update it writes a store-level override** that shadows the global value permanently. Nothing in the response says so.

- Write untranslated data through the explicitly global route.
- Write translated data only through a specific scope, and only for attributes that are genuinely scope-dependent.
- Never let the client fall back to an unscoped route because a scope lookup returned nothing. Fail the entity instead.
- Know which attributes are scope-dependent before you start. The grouping is not intuitive — display text is usually per store view, commercial values usually global, and enablement is often per website rather than per store view, so "disable in one store view" may not be expressible at all.

**There is no way to un-set a scoped override through a normal write.** Sending an empty value writes an empty value; repeating the global value creates a permanently divergent copy. Restoring inheritance requires deleting the scoped record, which is a distinct operation. Avoid creating the override in the first place: keep an explicit allowlist of scope-dependent attributes and refuse to write anything else through a scoped route.

## "Partial update" is partial only for scalars

Omitted scalar attributes keep their previous value. **Collection-shaped fields do not follow that rule** and each behaves differently — some are replaced wholesale, some merge, some clear only when explicitly emptied. Establish the behaviour per field before relying on it, and never assume that omitting a collection and sending a shorter one mean the same thing.

The practical consequence: **you cannot clear an attribute by omitting it.** A feed that stops exporting a field does not clear it; the stale value persists indefinitely.

Linked products deserve specific care: the link collection is typically **replaced as a whole across every link type at once**, so a feed that owns one link type and sends only that will delete the others. If the external system owns a subset, read the current links, preserve the types it does not own, and write the union.

## Variants: sequence or fail silently

Order is not negotiable, and getting it wrong mostly does not raise an error:

1. The differentiating attribute must exist, be globally scoped, and be usable for variants.
2. Its options must exist, and you must reference them by **identifier, not label**.
3. Every child must exist and already carry its attribute value.
4. Only then create the parent and attach options and children.

Creating a parent with options and no children succeeds and produces an unbuyable product page with no exception anywhere. Referencing an option identifier that does not exist may also succeed and store nothing.

Attaching a child that is already attached fails — the attach operation is not idempotent, unlike its category counterpart. Retry logic must be written per call.

## A success response is not proof of storage

The recurring failure mode in this family. Writes that report success and store nothing include: an attribute value for an attribute that is not in the entity's attribute set; an option reference that does not resolve; and type-inappropriate values on certain product types, which are dropped without comment.

**Attribute-set membership is the one that costs the most time.** The value is discarded on the way in, so nothing fails at write time — and the failure surfaces requests later, on an unrelated call, with a message that names the wrong thing. Validate that every attribute you intend to write belongs to the target attribute set as a pre-flight, not as a support ticket.

Product types also differ in what they accept: some silently drop a price they do not own, some coerce it, and at least one refuses to be created without extra structure. Read back what you wrote for each type once, then encode it.

## Throughput

- Batched and queued submission trades immediate per-item errors for request count. That is usually right for imports and wrong for anything user-facing.
- Acceptance of a batch is a receipt, not a result. Poll for terminal status and treat unfinished work as an incident.
- Switch indexers to scheduled mode for the duration of a large run; update-on-save turns every write into a reindex.
- Long-lived tokens matter: a short-lived interactive token will expire mid-run and the resulting failures look like a permissions problem.

## Verification

- Re-run and confirm the second run changes nothing.
- Read back a sample per product type, not just per product.
- Check for scoped overrides on attributes that should be global — those are the silent fallback in action.
- Confirm variant parents actually have children attached and are buyable.

## Anti-patterns

- Unscoped routes as a default.
- Assuming omitting a collection and sending a shorter one are equivalent.
- Referencing options by label.
- Trusting a success response instead of reading back.
