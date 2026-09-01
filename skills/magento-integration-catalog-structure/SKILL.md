---
name: magento-integration-catalog-structure
description: >-
  Use when an external system creates or updates Magento 2 products — the structural half of a catalog feed. Covers scope fallback, what "partial update" really means, variant sequencing, product types, link replacement, a business key with no unique constraint, rewrite bloat, reproducing a category listing, and the writes that report success and store nothing. Part of the `magento-integration-*` group.
---

# magento-integration-catalog-structure — products, variants and the silent writes

Group skill under `magento-integration-flow`. Build this first: a catalog that is loaded but not yet priced, stocked or categorised already unblocks layout, content and search work. Agnostic of client and transport.

## Scope is the first decision, and the default is wrong

The route decides which scope a write lands in, and the unscoped form is not "global". On creation it behaves globally; **on update it writes a store-level override** that shadows the global value permanently. Nothing in the response says so.

- Write untranslated data through the explicitly global route.
- Write translated data only through a specific scope, and only for attributes that are genuinely scope-dependent.
- Never let the client fall back to an unscoped route because a scope lookup returned nothing. Fail the entity instead.
- Know which attributes are scope-dependent before you start. The grouping is not intuitive — display text is usually per store view, commercial values usually global, and enablement is often per website rather than per store view, so "disable in one store view" may not be expressible at all.

**There is no way to un-set a scoped override through a normal write.** Sending an empty value writes an empty value; repeating the global value creates a permanently divergent copy. Restoring inheritance requires deleting the scoped record, which is a distinct operation.

Avoid creating the override in the first place: keep an explicit allowlist of scope-dependent attributes and refuse to write anything else through a scoped route. Where a reset is genuinely needed, it can be added — the platform's own import tooling already defines a sentinel meaning "no value", and a small extension can make a write carrying that sentinel delete the scoped record the way the admin's *use default* control does. Two things to know before building it: the value that triggers the delete is **not the same for every entity type**, and sending the wrong one writes an empty record instead of deleting, which pins "no value" on that scope silently. And the obvious extension point is sometimes wrong — some repositories serialise the entity they are handed, discard it, and repopulate a freshly loaded one, so anything set at that layer is thrown away.

### Two scope-shaped write hazards, reported rather than measured here

Both are long-standing upstream reports rather than findings from this verification pass, and both are silent. Treat them as reasons to write defensively, and confirm on your own version before designing around them.

- **A global-scope update can assign the product to every website in the installation** ([magento/magento2#11324](https://github.com/magento/magento2/issues/11324), root cause reported still present in [#30316](https://github.com/magento/magento2/issues/30316)) — with no website list in the payload, and regardless of what the product was scoped to before. Invisible on a single-website store; on a store where catalogues are deliberately split it turns a routine bulk metadata update into a live incident. **Read the product first and re-send its current website assignment on every write**, whether or not the assignment is changing.
- **A store-scoped update may pin *every* attribute at that scope, not the one you sent** ([#39498](https://github.com/magento/magento2/issues/39498), reported December 2024 at the highest severity). The entity is hydrated from storage before saving and cannot distinguish "this came in the payload" from "this came from the database", so the whole object is written at the scope in the route and every inherited value silently becomes an override. That makes a partial store-scoped write structurally unsafe: send everything explicitly, or keep translated writes out of the integration and let a migration own them.

## "Partial update" is partial only for scalars

Omitted scalar attributes keep their previous value. **Collection-shaped fields do not follow that rule** and each behaves differently — some are replaced wholesale, some merge, some clear only when explicitly emptied. Establish the behaviour per field before relying on it, and never assume that omitting a collection and sending a shorter one mean the same thing.

The practical consequence: **you cannot clear an attribute by omitting it.** A feed that stops exporting a field does not clear it; the stale value persists indefinitely.

The same replace-all shape turns up wherever a collection is nested inside an entity — links, media, option labels. Treat every collection field as "whatever I send becomes the whole set" until proven otherwise, and prove it per field rather than per API.

Linked products deserve specific care: the link collection is typically **replaced as a whole across every link type at once**, so a feed that owns one link type and sends only that will delete the others. If the external system owns a subset, read the current links, preserve the types it does not own, and write the union.

## Variants: sequence or fail silently

Order is not negotiable, and getting it wrong mostly does not raise an error:

1. The differentiating attribute must exist, be globally scoped, and be usable for variants.
2. Its options must exist, and you must reference them by **identifier, not label**.
3. Every child must exist and already carry its attribute value.
4. Every child should already have its stock, before the parent exists — see below.
5. Only then create the parent and attach options and children.

Creating a parent with options and no children succeeds and produces an unbuyable product page with no exception anywhere. Referencing an option identifier that does not exist may also succeed and store nothing.

Step 4 looks like a throughput preference and is not. A parent created while its children have no stock is stored in a state the platform will never move it out of, so it stays unbuyable permanently no matter how much quantity arrives later. The mechanism is in `magento-integration-prices-stock`; the ordering consequence belongs here, because it is decided when the structure is written.

Attaching a child that is already attached fails — the attach operation is not idempotent, unlike its category counterpart. Retry logic must be written per call.

## A success response is not proof of storage

The recurring failure mode in this family. Writes that report success and store nothing include: an attribute value for an attribute that is not in the entity's attribute set; an option reference that does not resolve; and type-inappropriate values on certain product types, which are dropped without comment.

**Attribute-set membership is the one that costs the most time.** The value is discarded on the way in, so nothing fails at write time — and the failure surfaces requests later, on an unrelated call, with a message that names the wrong thing. Validate that every attribute you intend to write belongs to the target attribute set as a pre-flight, not as a support ticket.

Product types also differ in what they accept: some silently drop a price they do not own, some coerce it, and at least one refuses to be created without extra structure. Read back what you wrote for each type once, then encode it.

## The business key is not unique, and two writers can prove it

**The product's business key carries an ordinary index, not a unique constraint.** Uniqueness is enforced in application code: the save reads for an existing entity, finds nothing, and creates. Nothing underneath rejects the second row, so **two creates for the same key that overlap inside that window both succeed** — two success responses, two identifiers, one key. Reproduced on every attempt across fourteen races on 2.4.8-p5, through the repository and over the API alike.

What happens next is decided by which of the two won the rewrite table, which *does* have a real unique constraint:

- **The later entity won it.** Every subsequent write for that key fails permanently, because the key resolves to the *lowest* identifier and that entity can never claim a path the other one holds. The error complains about a duplicate URL key, which sends everyone hunting for a slug collision on a product whose name never changed.
- **The earlier one won it.** Nothing surfaces at all. What you have is an orphan on a live key: unreachable through every key-addressed route, uncounted by any reconciliation that groups by key, and visible to a customer only if it later acquires a URL of its own.

**Recovery has a trap in it.** Delete-by-key removes the *lowest* identifier — the only one a key-addressed route can reach. In the broken case that is exactly the row to remove; in the silent case the same call deletes the live product and promotes the orphan. Check which entity owns the rewrite before firing it.

The constraint is not coming — the schema is shared with an edition where several rows per key are legitimate, so the obvious fix cannot ship there ([#31125](https://github.com/magento/magento2/issues/31125), open and reconfirmed since 2020; [PR #33191](https://github.com/magento/magento2/pull/33191) closed unmerged over exactly that objection). A lock around the read-then-create window can ship on both editions and is proposed in [PR #41181](https://github.com/magento/magento2/pull/41181). [BroCode_UniqueSku](https://github.com/brosenberger/module-unique-sku) packages both layers for installing today; read its compatibility note first, because the schema half must not go onto an install with content staging.

Until something lands, prevention is the client's job:

- **Partition the feed by the entity key, not round-robin.** Hash the key to a worker so one key is only ever held by one process. Round-robin over a feed that mentions a key twice is the exact reproduction.
- **A retry is a second writer.** A timeout that leaves the first call running and fires a retry produces the same overlap from a single-threaded importer. Make creates idempotent by reading first, and treat a timeout as *unknown* rather than as failed.
- **The queued path does not save you** — same repository, several consumers.
- **Reconcile after every full import** by grouping on the key and counting. It is seconds of work and it is the only thing that catches the silent half.

## URL keys and rewrite bloat

The most common hard failure on import names the URL key, and it has four unrelated causes: two source names normalising to the same slug, a deleted product whose rewrite rows survived, rewrite history being kept so every name change adds a permanent redirect row, and the duplicate above — which is the only one of the four that makes a key permanently unwritable.

- **Generate the URL key yourself from something stable** — derived from the business key, or the name with the key appended — rather than letting the platform derive it from a name the external system will change.
- **Decide deliberately whether to keep rewrite history for import-driven changes.** On a large catalog with frequent name changes the rewrite table grows into millions of rows and starts dominating save time. If the redirects are not wanted, turn the setting off and prune.
- Rewrite rows also multiply with category assignments; that side is in `magento-integration-categories`.

## Reading a category listing back

Integrations read as well as write, and reproducing "the products in this category, as the shop shows them" is where the three silent read failures live.

- **Visibility.** A category's membership includes variant children that are never shown individually. Filtering on the category alone can return an order of magnitude more than the storefront does — measured at 347 against 32 on one sample-data category. Restrict to the visibility values that mean catalog-visible, and to enabled products, remembering that enablement may be scoped per website rather than per store view.
- **The link field.** The singular category-link field is the one that filters. The plural field that appears in read responses — the one most people try first — does not filter; on the tested version it returns a server error rather than an empty or unfiltered result.
- **Merchandised order cannot be expressed on the product collection.** A sort on position is accepted and silently ignored, because position belongs to the category-to-product relation rather than to the product. Requesting ascending and descending returns identical order. Read the ordering from the category side, which carries position per assignment, and join it to product data client-side.

And an honest limit: this reproduces a listing's contents and order, not its behaviour. Layered navigation, price rules and stock-based exclusions are applied on top and are invisible to this query.

Query mechanics — filter combination, paging while writing, detecting a sort that did nothing — are in `magento-integration-querying`.

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
- Group by the business key and count. Anything above one is the concurrent-create race, and it is the only check that finds its silent half.
- Watch rewrite row counts across runs; unbounded growth means names or assignments are churning.

## Anti-patterns

- Unscoped routes as a default.
- Assuming omitting a collection and sending a shorter one are equivalent.
- Referencing options by label.
- Trusting a success response instead of reading back.
- Round-robin partitioning of a feed that can mention one entity twice.
- Treating a timed-out write as failed rather than as unknown.
- Letting the platform derive the URL key from a name the external system owns.
