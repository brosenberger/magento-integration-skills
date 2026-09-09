---
name: magento-integration-catalog-structure
description: >-
  Use when an external system creates or updates Magento 2 products — the structural half of a catalog feed. Covers scope fallback, partial-update semantics, variant sequencing, product types, link replacement, a non-unique business key, rewrite bloat, reproducing a category listing, unvalidated enumerated values, and the writes that report success and store nothing. Part of the `magento-integration-*` group.
---

# magento-integration-catalog-structure — products, variants and the silent writes

Group skill under `magento-integration-flow`. Build this first: a catalog that is loaded but not yet priced, stocked or categorised already unblocks layout, content and search work. Agnostic of client and transport.

## Scope is the first decision, and the default is wrong

The route decides which scope a write lands in, and the unscoped form is not "global". On creation it behaves globally; **on update it writes a store-level override** that shadows the global value permanently. Nothing in the response says so.

- Write untranslated data through the explicitly global route.
- Write translated data only through a specific scope, and only for attributes that are genuinely scope-dependent.
- Never let the client fall back to an unscoped route because a scope lookup returned nothing. Fail the entity instead.
- Know which attributes are scope-dependent before you start. The grouping is not intuitive — display text is usually per store view, commercial values usually global, and enablement is often per website rather than per store view, so "disable in one store view" may not be expressible at all.

**Restoring inheritance means deleting the scoped record, not writing over it.** Repeating the global value creates a permanently divergent copy, and sending an *empty* value writes an empty value — which pins "no value" on that scope rather than clearing it. The write that actually deletes is an explicit **null**, and it is the API's equivalent of the admin's *use default* control. Measured on 2.4.8-p5: `null` on a scoped route removed the scoped row for a numeric attribute, an optional text attribute and a required one alike, while `""` on the same text attribute left a row behind holding a database NULL.

**Send that null only on a scoped route.** At default scope the same payload targets the *default* record. A required attribute is protected — the save is rejected because the value would be empty — but an optional one is not, and deleting its default record leaves the entity with no stored value at all. What follows is a read/index split: entity reads fall back to the attribute's declared default and report a perfectly normal value, while indexers that join the default record directly drop the entity outright. Nothing reports an error, and the next ordinary save writes the record back and erases the evidence.

Better still, avoid creating the override at all: keep an explicit allowlist of scope-dependent attributes and refuse to write anything else through a scoped route. A reset you never need is one you cannot get wrong. Note that other transports express the reset differently — the platform's file-import tooling uses a sentinel string meaning "no value" rather than a null, the sentinel is **not the same for every entity type**, and sending the wrong one writes an empty record instead of deleting. Confirm the reset token per transport before relying on it.

### Two scope-shaped write hazards, now measured — and both reports are half wrong

Both were long-standing upstream reports carried here unverified. A pass on 2.4.8-p5 with two websites reproduced one of them in a narrower form than reported and failed to reproduce the other at all. Where a report and the install disagree, the install wins — but check your own version, because these are exactly the defect-shaped claims that flip between releases.

- **The all-scope route assigns a product to every website — on create, not on update** ([magento/magento2#11324](https://github.com/magento/magento2/issues/11324), root cause reported still present in [#30316](https://github.com/magento/magento2/issues/30316)). Measured across every route on a two-website install: a create through the all-scope route with no website list in the payload landed in **both** websites, while the same create through the scopeless route or a store-view route landed only in that route's website. An explicit website list on the all-scope create was respected. The **update** half of the report did not reproduce — a name-only update through the all-scope route left an existing single-website assignment untouched, as did the scopeless one.

  So the hazard is real and narrower than reported: it is a **create-time** fan-out on one route. Invisible on a single-website store; on a store where catalogues are deliberately split, an importer that creates through the all-scope route publishes every new product everywhere. **Send the website list explicitly on every create** — that is the whole fix, and it is cheaper than the read-before-write the broader reading of this report implies.
- **A store-scoped update pinning *every* attribute at that scope did not reproduce** ([#39498](https://github.com/magento/magento2/issues/39498), reported December 2024 at the highest severity). The mechanism described is real in outline — the entity is hydrated from storage before saving — but on 2.4.8-p5 a name-only update through a store-view route wrote **exactly one** scoped record, for the attribute sent. Sixteen populated attributes across four value tables stayed global. Measured on a simple product with no pre-existing store overrides, one attribute in the payload; a product type, attribute set or payload shape not covered by that could still trigger it, so treat this as *not reproduced here* rather than *fixed*.

  One real artifact did surface, and it is not the reported one: **date-typed attributes gain empty records at every store view on any update**, including store views the route never addressed. It happens identically on the scopeless route, so it is a property of the save rather than of the scope in the route — harmless in itself, but it means the presence of a store-level record is not evidence that anything was scoped deliberately. Which matters when reading scope state back: per the reset rule above, an empty record and an absent record are not the same thing.

## Enumerated attributes are not validated on the way in

**A select attribute's option list is documentation, not a constraint.** Values that correspond to no option are accepted, return success, and are stored verbatim — measured on 2.4.8-p5 with an out-of-range enablement value, an out-of-range visibility, and a country code that is not a country. This holds whether the field is a typed scalar on the product interface or a generic attribute in the custom-attribute bag; nothing on this route consults the source model.

The damage is not evenly distributed. It concentrates on **enablement**, because three things line up:

- **The value most integrations reach for is the invalid one.** Enablement is `1` for on and `2` for off. There is no `0`. An external system carrying an `active` boolean, cast rather than mapped, emits `0` for inactive — which is neither of the two legal values.
- **Enablement is website-scoped, so the mistake fans out.** One scoped write does not write the store view in the route; it writes every store view of that store view's website. A single request plants the invalid value across the whole website.
- **Only `1` counts as enabled, so the mistake looks like it worked.** The invalid value and the legitimate "off" value are indistinguishable on the storefront and in the price index. The feed reports success, the product disappears, and the disable half of the integration passes acceptance.

**The failure surfaces on the way back up.** Writing the enabled value at *default* scope does not repair it, because the scoped records still shadow it — so "activate this product for the website" runs clean and changes nothing a customer can see, indefinitely. The scoped records have to be deleted, per the reset rule above.

And it is invisible where people look for it. The admin renders an unmatched select value as a **blank cell**, not as the value and not as a label — there is no "Disabled" to spot, and no clue an override exists. The admin also cannot *create* the state: its form is built from the same source model and can only ever offer the legal values. This is an API-only condition, which is why nobody on the merchant side recognises it.

In the client:

- **Map, never cast.** `active ? 1 : 2`. An integer cast of a boolean is the bug.
- **Validate every enumerated value against its option list before sending**, since the API will not.
- **Reconcile against storage, not against a read.** Select the attribute's value rows where the value is outside the legal set. A read at default scope will report the healthy default and tell you nothing.

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
- Select the value rows for every enumerated attribute you write and assert each value is in its option list. Out-of-range values are stored without complaint and are invisible to a read at default scope.
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
- Casting a source-system boolean into an enumerated attribute instead of mapping it to a declared option.
- Trying to undo a scoped override by writing the desired value at default scope.
