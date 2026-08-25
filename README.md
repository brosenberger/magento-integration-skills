# magento-integration-skills

Agent skills for building a data integration against Magento 2 — an ERP, PIM or OMS feed pushing catalog, customer or order data.

**Flow and pitfalls, not calls.** No routes, no payloads, no field names, no client code. Concrete shapes are version- and install-specific and rot on the first upgrade; the failure modes are the part that transfers between projects, and the part nobody writes down.

## The set

| Skill | Covers |
|---|---|
| `magento-integration-flow` | Build order, the failure modes every endpoint family shares, when to stop and verify. Start here |
| `magento-integration-catalog-structure` | Products and variants: scope fallback, partial-update semantics, sequencing, writes that report success and store nothing |
| `magento-integration-attributes` | Types, options, per-store labels, swatches, and why third-party attribute properties are usually unreachable |
| `magento-integration-media` | Unbounded duplication, the global-gallery vs per-store-view-role split, deletion refusals |
| `magento-integration-prices-stock` | Why these never belong in a product save, the opposite error models, salable vs source quantity |
| `magento-integration-categories` | The missing natural key, asymmetric assignment paths, removal, rewrite bloat |

## Install

```sh
git clone https://github.com/brosenberger/magento-integration-skills.git
cd magento-integration-skills
bin/install-symlinks.sh              # -> ~/.claude/skills
bin/install-symlinks.sh ~/.cursor/skills
```

Per-folder symlinks, idempotent, and it never overwrites something already there. Pull to update; the links follow.

## When you need concrete calls

These skills deliberately stop short of request shapes. Export the API description from the install you are integrating with, import it into a collection, and drive that over MCP — generated from the real system, regenerating when it changes.

Two caveats measured on Magento Open Source 2.4.8-p5:

- The published schema is **not** the full surface: `/rest/all/schema?services=all` returned 45 paths against 432 routes declared in the install's own `webapi.xml`, identical with and without an admin token. Confirm the endpoints you need are in the export.
- `webapi.xml` in the install is the authority on whether a route exists. If it is not declared there it does not exist, whatever any documentation says.

## Documentation

An [OKF v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) knowledge bundle lives in [`docs/`](docs/index.md) — what the set covers, how the claims were established, what was not tested, and how fast each class of claim ages.

## Provenance

Every behavioural claim traces to something executed against a running Magento install — not to documentation and not to reading source, both of which have been wrong about several of these. Verified on **Open Source 2.4.8-p5** with sample data, and where a claim contradicts widely repeated advice, that is usually because the advice was true in an earlier version.

Written alongside a series on [brocode.at](https://brocode.at/blog/) that carries the measurements and the verification records.

## Caveats

- Behaviour is current as of 2.4.8-p5. Several claims here contradict what was true in 2.3.x, and these claims will age the same way. Re-test after a major upgrade.
- Customer and order coverage is deliberately absent: it has not been verified against a running install yet, and an unverified skill is worse than no skill.

## Licence

MIT — see [LICENSE](LICENSE).
