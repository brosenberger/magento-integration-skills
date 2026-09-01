---
type: Skill Set
title: The Skill Set — one skill per endpoint group
description: What each skill covers, how they relate, and the reasoning behind excluding routes and payloads.
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
| `magento-integration-flow` | Build order, access preconditions, cross-cutting failure modes, when to verify | the *Magento ERP Integration* pillar |
| `magento-integration-querying` | Reading data out: filter model, silent no-ops, paging while writing | the *Magento ERP Integration* pillar |
| `magento-integration-catalog-structure` | Products and variants; scope fallback; silent writes | `magento2-rest-product-import-pitfalls` |
| `magento-integration-attributes` | Types, options, per-store labels, swatches, third-party properties | `magento2-rest-product-attributes` |
| `magento-integration-media` | Duplication, gallery-vs-role scope split, deletion refusals | `magento2-rest-product-media` |
| `magento-integration-prices-stock` | Narrow endpoints, opposite error models, salable vs source | `magento2-rest-price-stock-endpoints` |
| `magento-integration-categories` | Missing natural key, assignment asymmetry, removal | `magento2-rest-category-integration` |
| `magento-integration-customers` | Accounts, addresses, groups; mail that cannot be deferred; writes that undo themselves | `magento2-rest-customer-integration` |
| `magento-integration-orders` | The poll loop and cursor, state and history write-back, reading order lines for money | `magento2-rest-order-sync`, `magento2-rest-order-prices` |
| `magento-integration-fulfilment` | Documents, payment state, stopping an order, creating orders at all | `magento2-rest-order-fulfilment`, `-order-payments`, `-order-creation` |

`magento-integration-flow` is the entry point and delegates to the rest. It restates the cross-cutting pitfalls the group skills also touch — right for standalone use, a maintenance cost when a shared claim changes. That duplication is deliberate and should be reviewed if the set grows.

# Why querying is its own skill and access is not

Read mechanics were originally written into three skills at once, which is the exact drift risk the note above warns about. They are also genuinely cross-cutting: filter combination, paging and sort behaviour are identical whatever entity is being read. Extracting `magento-integration-querying` removes the duplication and gives reading its own trigger, which is a different moment from importing.

Family-specific read *facts* stayed with their family — that a category's membership includes never-listed variant children is catalog semantics, not query mechanics.

# Why orders are two skills

The order wave splits along the direction of the work rather than along the endpoint families. `magento-integration-orders` is the loop — pulling changes out, understanding state, writing progress back — and it is what almost every integration needs. `magento-integration-fulfilment` is what an integration *writes*: documents, payment decisions, stops, and the uncommon case of creating orders inside Magento. The split holds because the first is needed by every project and the second by projects that own fulfilment, and because the reading rules (which rows carry money) and the writing rules (which routes validate) have nothing to do with each other.

The route-shape heuristic — a collection-named route is a repository save that validates nothing, an entity-scoped action route is the service that does — lives in `fulfilment` in full and as one line in `flow`, because it is worth checking wherever two routes look like alternatives for the same job.

**Access deliberately did not become a skill.** Credential choice, token lifetime, permission scoping and the unauthenticated surface are a precondition for every call rather than a mode of operation, so they sit at the top of the flow skill. The material is also thin: token lifetime and the size of the anonymous surface are verified, but permission scoping for an integration account and the security consequences of the unauthenticated endpoints have not been exercised. That work belongs with the customer wave, which is where it is actually reached — and a skill padded out ahead of its verification would be exactly what this set is trying not to be.

# Why no routes or payloads

The skills contain no endpoint paths, no field names, no request bodies and no client code. Three reasons, in order of weight:

1. **Concrete shapes rot.** They are specific to a Magento version and to the modules a given install carries. A skill that names fields is wrong after an upgrade and gives no signal that it has become wrong.
2. **The install already knows.** Route declarations and payload interfaces ship inside every Magento installation. Duplicating them into a skill adds a second, worse copy — see [Concrete Calls](concrete-calls.md).
3. **Behaviour is the part nobody writes down.** That a success status is not proof of storage, that idempotency differs between adjacent endpoints, that two similar-looking families have opposite error models — none of this appears in any declaration, and all of it survives a field rename.

# What is deliberately missing

**A payment-provider matrix.** The payment behaviour in `magento-integration-fulfilment` was measured against a stand-in gateway, so it describes Magento's own bookkeeping and not any real provider. A module can place an order into review, capture from a webhook, or create the invoice itself, and no skill can predict which — the skill therefore carries the *test pass* to run per method rather than a table of answers.

**Transport and format concerns.** Content negotiation, the alternate request encoding and its quirks on the queued path are documented in the article series and deliberately not here: they are client-shaped rather than behaviour-shaped, and a client that has chosen its encoding has already answered them.

**Anything not executed.** See [Verification](verification.md) for what was measured and what was not.
