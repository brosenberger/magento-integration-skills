---
type: Practice
title: Concrete Calls — getting real requests without baking them into a skill
description: Export the API description from the target install and drive it as a tool, with the measured limits of that export.
resource: https://developer.adobe.com/commerce/webapi/rest/
tags: [magento2, rest-api, mcp, tooling, postman]
generated:
  by: claude-opus-5
  at: 2026-08-25T00:00:00Z
verified:
  - by: magento2-sandbox (Magento Open Source 2.4.8-p5)
    at: 2026-08-25T00:00:00Z
status: stable
stale_after: 2027-02-25T00:00:00Z
---

# The approach

When an actual request is needed, generate it from the system being integrated with — not from memory, not from a skill, and not from a hand-maintained index.

Magento publishes a machine-readable API description. Import it into a collection and expose that collection as a tool over MCP. The calling layer is then generated from the same install the integration targets, and regenerates when that install changes.

This keeps the skills free of anything a version bump invalidates, and removes the main reason a model invents endpoints — it no longer has to remember them.

# Measured limits

Both measured on Magento Open Source 2.4.8-p5 with sample data.

| Observation | Value |
|---|---|
| Routes declared in the install's own `webapi.xml` | 432 |
| Paths in the published schema (`?services=all`) | **45** |
| Definitions in that schema | 120 |
| Same request with an admin bearer token | identical — not an authorization effect |
| Explicit service list (`?services=<name>,<name>`) | 0 paths — that parameter takes some other naming form |

**The export is a starting point, not a manifest.** Confirm the endpoints an integration needs are actually present before relying on it.

# The authority on existence

The route declarations inside the install are authoritative. If a route is not declared there, it does not exist — whatever documentation, a forum answer, or a model asserts.

That single check is what makes an invented endpoint impossible, and it costs one search. It is worth wiring into any workflow that generates integration code.
