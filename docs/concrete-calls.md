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

# What the export actually covers

Measured on Magento Open Source 2.4.8-p5 with sample data and one third-party vendor.

| Credential used for the schema request | Paths | Definitions |
|---|---|---|
| None (anonymous) | 45 | 120 |
| Admin bearer token | **325** | 399 |
| Integration token scoped to catalog only | 71 | 158 |

Against the install's own declarations — 432 declared routes across 344 distinct URL templates — the admin-token export carries **410 operations across 325 paths**. That is roughly 95% of the surface, not a fragment.

**The export is permission-scoped, and that is a feature.** The schema reflects what the requesting credential is allowed to call. Request it with the integration token the client will actually use and the resulting collection describes exactly that client's reachable surface — it cannot generate a call the token would be refused for.

An earlier version of this document reported the anonymous figure for all three cases and concluded the export was a fragment. That was a measurement error: the request believed to carry an admin token was unauthenticated, most likely because the token had passed its short lifetime. The correction matters because it changes the recommendation from "treat the export as a starting point" to "generate against the credential you will use".

# The authority on existence

The route declarations inside the install are authoritative. If a route is not declared there, it does not exist — whatever documentation, a forum answer, or a model asserts.

That single check is what makes an invented endpoint impossible, and it costs one search. It is worth wiring into any workflow that generates integration code.
