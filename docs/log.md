# Change Log

## 2026-08-25

### Initial set

- Six skills: `magento-integration-flow` plus `-catalog-structure`, `-attributes`, `-media`, `-prices-stock`, `-categories`
- Scope decision: flow and pitfalls only — no routes, payloads, field names or client code
- Concrete calling delegated to exporting the target install's schema into a collection driven over MCP
- POSIX `sh` symlink installer, idempotent, refuses to overwrite an existing local skill
- MIT licence

### Read paths

- Added reading coverage: reproducing a category listing, and reads as a cross-cutting concern
- Three silent read failures recorded: variant children inflating category membership (347 against 32 on one sample category), the plural category-link field failing hard rather than filtering, and a sort on position being accepted and ignored
- Filter-combination limit recorded: AND across groups, OR within a group, and `(A AND B) OR (C AND D)` not expressible

### Querying extracted

- New `magento-integration-querying`: filter combination and the `(A AND B) OR (C AND D)` limit, reads that silently do nothing, paging safely while writing, read cost
- Removed the read-mechanics duplication introduced across flow, catalog-structure and categories; family-specific read facts stayed with their family
- Access preconditions — credential choice, token lifetime, permission scoping, the unauthenticated surface — added to the flow skill rather than becoming a skill, on the grounds that the material is a precondition and is not yet fully verified

### Access and a correction

- Recorded that using an integration credential as a plain bearer token is deprecated, disabled by default, and fails with an error that blames permissions rather than the toggle
- Recorded that the API description the install produces is permission-scoped, so generating it against the client's own credential yields exactly that client's reachable surface
- **Corrected** the earlier claim that the schema export covered 45 paths regardless of credential: it is 325 paths and 410 operations with a valid administrator credential, against 344 declared URL templates. The original measurement was served anonymously because the credential had expired, and returned a valid-looking smaller schema rather than an error

### Documentation

- OKF v0.2 bundle under `docs/`: skill set, concrete calls, verification, version sensitivity
- Trust fields used as intended: `generated` on every concept, `verified` on the two backed by execution against a running install, `stale_after` on all
- Verification record pinned to Magento Open Source 2.4.8-p5 with OpenSearch 2.19.1 and Elasticsuite 2.12.1.1
- Not-tested list recorded explicitly: customer and order behaviour, deadlocks under load, catalog-scale effects, reservations, single-scope topologies

## 2026-08-26 — corrected parent stock mechanism

`magento-integration-prices-stock`: replaced the parent-stock explanation. The
previous version claimed the multi-source module's observer replacement dropped
parent re-evaluation entirely, so nothing in the stock path maintained a parent
flag. That is wrong — the logic was moved down a level, not dropped, and both
stock paths reach it.

The real mechanism is an asymmetric rule: a parent always follows its children
*out* of stock, but returning requires a marker saying the current status was set
automatically. A product created without stock data is stored out of stock with
that marker cleared, so a parent created before its stock exists is born in the
one state the platform never moves it out of. Verified A/B on 2.4.8-p5 and 2.4.9.

Also recorded: the marker is a writable field on the public stock DTO, and parent
maintenance is gated on *fewer than two enabled sources* — a second enabled
source assigned to nothing still disables it.

`magento-integration-catalog-structure`: added the ordering consequence — stock
before parent creation — since that is decided when the structure is written.

## 2026-08-31 — customers, and the multi-source pair

- New `magento-integration-customers` from the 2.4.8-p5 customer verification pass: the anonymous create that also sends mail, mail that can only be discarded rather than deferred, scope validated in one direction only, the address update that destroys the row and everything referencing it, and automatic group assignment reversing a group the integration just set
- `magento-integration-prices-stock`: the real trigger for the stuck composite parent is whether the parent carries its children at the moment it is created, not whether stock exists yet; both payload shapes that avoid it; the multi-source pair — the maintenance gate and the default-stock veto — recorded as the severe case rather than the mild one, with the upstream trade-off
- `magento-integration-flow`: payload types are per field rather than per API, with the two boolean-looking flags on one entity that disagree

## 2026-09-01 — orders, and the gaps the article set had outrun

Audited all eight skills against the article cluster they were written from. The catalog wave and customers were current; the order wave had no skill at all and several earlier articles had never been harvested.

### The order wave

- New `magento-integration-orders`: the second-resolution change cursor that silently drops rows and the two cursors that do not, the order feed's columns not being the admin grid's, an unknown field name being a 500 rather than a 400, state that only moves as a side effect of documents, a comment that cannot cross states, hold and unhold and cancel writing no history at all, and the order lines that carry money — parent-only for totals and quantity, **every row** for discount
- New `magento-integration-fulfilment`: the route-shape rule (a collection-named route is a repository save that validates nothing; an entity-scoped action route is the service that does), documents keyed on the order line, the whole shipping cost landing on the first partial invoice, an over-ship that is silently clamped, an invoice validator that names the wrong field, the invoice-level refund that crashes on a full refund, tracking that moves no change timestamp and is therefore invisible to every poller, payment behaviour configured per method, the capture flag that books money without calling the provider, cancel and void reporting success while doing nothing, and order injection corrupting the append-only reservation ledger permanently
- `magento-integration-flow`: build order now names the skill for each wave, and the route-shape rule is restated as one cross-cutting line

### Gaps closed in the existing set

- `catalog-structure`: the business key has no unique constraint, so two overlapping creates both succeed — with the recovery trap, the prevention rules and the upstream position; URL keys and rewrite bloat; and the two reported-not-measured scope hazards from the API-gaps article, marked as such
- `flow`: the queued path needs no message broker (the most repeated wrong thing about it), the scopeless queued route carrying the scope trap at bulk scale, deadlocks and the concurrency rules, the API sharing the storefront's process pool, and a section on what has no API at all — control-plane operations, catalog price rules, and scoped configuration that cannot be reset
- `querying`: camel-cased criteria names in a URL silently returning everything, a collection read needing at least one criteria key, EAV filtering and the flat-form condition, and the response projection — not part of the filter model, and needing the collection wrapper on a list endpoint
- `categories`: the two folklore corrections recorded as explicit anti-facts, the listing endpoint's two long-standing defects being fixed on the tested version, and index latency after an assignment change
- `attributes`: text-swatch labels being separate rows from the option's label set, swatch input type as a migration, and the listing flag a variant swatch needs
- `customers`: the anonymous password-reset route and its throttle, and the absence of any address search
- `prices-stock`: the upstream issues and pull requests for both halves of the composite latch, and an entity created with no stock data disappearing entirely where out-of-stock products are hidden
- `media`: recorded explicitly that this family's success response can be trusted, which is the exception in the set

### Documentation

- Skill set, README and verification updated: eight skills became ten, and the "customer and order coverage is deliberately absent" caveat is retired

## 2026-09-07 — the enablement value that is not an option

A field report rather than an audit: an integration writing `0` for "inactive" through the product endpoint. Reproduced on the same 2.4.8-p5 sandbox, on a two-website install.

- `catalog-structure`: new section on enumerated attributes not being validated on the way in — out-of-range values for enablement, visibility and a country code were all accepted and stored. Recorded with the three-way pile-up that makes enablement the expensive case: the invalid value is the one an unmapped boolean produces, website scope fans a single scoped write across every store view of that website, and only the enabled value counts as enabled, so the disable half of a feed passes acceptance while the enable half silently stops working. Plus the blank admin cell that hides it and the fact that the admin cannot produce the state at all.
- `catalog-structure`: **corrected** the scope-reset rule. It said inheritance could not be restored through a normal write. An explicit `null` on a scoped route deletes the scoped record — measured on a numeric attribute, an optional text attribute and a required one — while an empty string writes a record holding a database NULL. The sentinel-and-extension advice that stood in for a reset is now scoped to file-import transports, where it is still true. Added the matching hazard: the same `null` at *default* scope is rejected for a required attribute but not for an optional one, and deleting an optional attribute's default record splits reads from indexers — reads report the attribute's declared default, indexers that join the default record drop the entity.
- `attributes`: one line, since the identifier-not-label rule now has a consequence — nothing verifies the identifier when a product is written, so the external-value-to-identifier map has to be validated client-side.

## 2026-09-09 — the queued path had infrastructure and no result contract

An audit prompted by a question rather than a field report: the set covered whether the queued path *runs* and said almost nothing about what it *returns*.

### The new skill

- New `magento-integration-async-bulk`: the receipt that replaces the entity response — a batch identifier and per-item entries carrying only a positional index, a content hash and an accepted flag, with correlation therefore positional and the caller's to maintain; the content hash not being an idempotency key, so a byte-identical batch replays; **structural validation still synchronous and all-or-nothing for the whole batch** while business validation defers per item, which is the half of this most descriptions get backwards in both directions; the four status routes and what each is actually for, including the operation-search route listing operations rather than batches and the detailed view being the only place the created entity comes back; the two correlation fields that stay empty on every create; **the status routes guarded by an action-log resource unrelated to the write**, so a catalog-scoped credential pushes a batch and is then refused its own receipt; the error code being zero on every failure cause; nothing retrying a failed operation and no route to ask for one; an operation with no consumer staying open forever while the sweeper that exists only touches interrupted work; and batch records expiring on a timer that ignores state, taking the evidence with them.

### The set around it

- `magento-integration-flow`: the queued bullets now delegate rather than summarise — acceptance-is-not-completion gained the missing half (the receipt carries no entity), and a new line records that queued routes are declared separately from their synchronous originals, so the existence check has to run against the async declaration
- `docs/skill-set.md`: the reasoning for the split, on the same test that produced `magento-integration-querying`; the deliberate exclusion of transport and encoding narrowed to encoding only, now that the queued path's behaviour is covered
- README and skill-set tables: ten skills became eleven

### Verification

- Queued-write-path pass recorded against 2.4.8-p5 on two websites, database queue, no broker
- Two claims marked source-read rather than executed: the two cron jobs and the retention default
- Not-tested list gained the retriably-failed and rejected states in normal operation, and batch expiry observed end to end

### The two scope hazards, harvested in the same pass

The queued-path work surfaced one of them incidentally, so both were run rather than left recorded.

- `magento-integration-catalog-structure`: **corrected** both. The website fan-out is real but **create-only and route-specific** — the all-scope create with no website list lands in every website, while the scopeless and store-view creates each land in one, an explicit list is respected, and the *update* half of the report did not reproduce at all. The fix therefore shrinks from read-before-write to sending the website list on every create. The store-scoped attribute pinning **did not reproduce**: a name-only store-scoped update wrote one scoped record where sixteen attributes were populated globally, and is now recorded as not reproduced rather than fixed, with the shape tested stated
- `magento-integration-catalog-structure`: new artifact recorded in its place — date-typed attributes gain empty records at every store view on any update, isolated with a scopeless control, so a store-level record is not evidence of a deliberate scoped write
- `docs/verification.md`: the scope-hazard pass recorded; the not-tested entry for these two hazards replaced with the narrower limit that actually remains
