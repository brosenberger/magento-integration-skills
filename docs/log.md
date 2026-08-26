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

### Documentation

- OKF v0.2 bundle under `docs/`: skill set, concrete calls, verification, version sensitivity
- Trust fields used as intended: `generated` on every concept, `verified` on the two backed by execution against a running install, `stale_after` on all
- Verification record pinned to Magento Open Source 2.4.8-p5 with OpenSearch 2.19.1 and Elasticsuite 2.12.1.1
- Not-tested list recorded explicitly: customer and order behaviour, deadlocks under load, catalog-scale effects, reservations, single-scope topologies
