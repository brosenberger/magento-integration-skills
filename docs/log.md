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
