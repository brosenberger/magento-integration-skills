---
okf_version: "0.2"
type: Knowledge Bundle
title: magento-integration-skills — Knowledge Bundle
description: Agent skills for building a data integration against Magento 2, covering flow and pitfalls rather than concrete calls.
resource: https://github.com/brosenberger/magento-integration-skills
tags: [magento2, integration, rest-api, agent-skills, erp]
generated:
  by: claude-opus-5
  at: 2026-08-25T00:00:00Z
status: draft
stale_after: 2027-08-25T00:00:00Z
---

# magento-integration-skills — Knowledge Bundle

Documentation for a set of agent skills covering Magento 2 data integration — an ERP, PIM or OMS feed pushing catalog, customer or order data.

The skills themselves live in [`skills/`](../skills). This bundle explains what they are, how their claims were established, and when to stop trusting them.

Frontmatter follows [OKF v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md). The trust and lifecycle families earn their place here: this content is pinned to a Magento version, so `verified` records what was actually executed and `stale_after` gives it an explicit expiry rather than an implicit one.

# Scope

* [The Skill Set](skill-set.md) — What each skill covers, and why they carry no routes or payloads
* [Concrete Calls](concrete-calls.md) — Getting real requests without baking them into a skill
* [Verification](verification.md) — How the behavioural claims were established, and what was not tested
* [Version Sensitivity](version-sensitivity.md) — What ages, how fast, and when to re-test

# Meta

* [Change Log](log.md) — What changed and when
