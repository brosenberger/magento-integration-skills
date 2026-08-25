# Change Log

## 2026-08-25

### Initial set

- Six skills: `magento-integration-flow` plus `-catalog-structure`, `-attributes`, `-media`, `-prices-stock`, `-categories`
- Scope decision: flow and pitfalls only — no routes, payloads, field names or client code
- Concrete calling delegated to exporting the target install's schema into a collection driven over MCP
- POSIX `sh` symlink installer, idempotent, refuses to overwrite an existing local skill
- MIT licence

### Documentation

- OKF v0.2 bundle under `docs/`: skill set, concrete calls, verification, version sensitivity
- Trust fields used as intended: `generated` on every concept, `verified` on the two backed by execution against a running install, `stale_after` on all
- Verification record pinned to Magento Open Source 2.4.8-p5 with OpenSearch 2.19.1 and Elasticsuite 2.12.1.1
- Not-tested list recorded explicitly: customer and order behaviour, deadlocks under load, catalog-scale effects, reservations, single-scope topologies
