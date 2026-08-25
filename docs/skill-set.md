---
type: Skill Set
title: The Skill Set — one skill per endpoint group
description: What each of the six skills covers, how they relate, and the reasoning behind excluding routes and payloads.
resource: https://github.com/brosenberger/magento-integration-skills/tree/main/skills
tags: [magento2, agent-skills, integration, scope]
generated:
  by: claude-opus-5
  at: 2026-08-25T00:00:00Z
status: draft
stale_after: 2027-08-25T00:00:00Z
---

# The set

| Skill | Covers | Ships with |
|---|---|---|
| `magento-integration-flow` | Build order, cross-cutting failure modes, when to verify | the *Magento ERP Integration* pillar |
| `magento-integration-catalog-structure` | Products and variants; scope fallback; silent writes | `magento2-rest-product-import-pitfalls` |
| `magento-integration-attributes` | Types, options, per-store labels, swatches, third-party properties | `magento2-rest-product-attributes` |
| `magento-integration-media` | Duplication, gallery-vs-role scope split, deletion refusals | `magento2-rest-product-media` |
| `magento-integration-prices-stock` | Narrow endpoints, opposite error models, salable vs source | `magento2-rest-price-stock-endpoints` |
| `magento-integration-categories` | Missing natural key, assignment asymmetry, removal | `magento2-rest-category-integration` |

`magento-integration-flow` is the entry point and delegates to the rest. It restates the cross-cutting pitfalls the group skills also touch — right for standalone use, a maintenance cost when a shared claim changes. That duplication is deliberate and should be reviewed if the set grows.

# Why no routes or payloads

The skills contain no endpoint paths, no field names, no request bodies and no client code. Three reasons, in order of weight:

1. **Concrete shapes rot.** They are specific to a Magento version and to the modules a given install carries. A skill that names fields is wrong after an upgrade and gives no signal that it has become wrong.
2. **The install already knows.** Route declarations and payload interfaces ship inside every Magento installation. Duplicating them into a skill adds a second, worse copy — see [Concrete Calls](concrete-calls.md).
3. **Behaviour is the part nobody writes down.** That a success status is not proof of storage, that idempotency differs between adjacent endpoints, that two similar-looking families have opposite error models — none of this appears in any declaration, and all of it survives a field rename.

# What is deliberately missing

**Customer and order coverage.** Both are planned and neither has been executed against a running install. An unverified skill is worse than no skill: it reads with the same confidence as a verified one and there is no way for a reader to tell them apart. See [Verification](verification.md).
