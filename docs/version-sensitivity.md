---
type: Practice
title: Version Sensitivity — what ages and how fast
description: Which classes of claim survive a Magento upgrade, which do not, and how to re-test the ones that matter.
resource: https://experienceleague.adobe.com/en/docs/commerce-operations/release/versioning
tags: [magento2, upgrade, maintenance, testing]
generated:
  by: claude-opus-5
  at: 2026-08-25T00:00:00Z
status: stable
stale_after: 2027-02-25T00:00:00Z
---

# The half-life problem

These skills describe behaviour, and behaviour changes between versions without announcement. Several claims here exist specifically because widely repeated advice was correct when written and silently stopped being correct.

That will happen to these claims too. Treat the version in [Verification](verification.md) as a pin, not a footnote.

# What ages, in order of speed

1. **Defect-shaped behaviour** — anything that is "broken" is a candidate for being fixed. Two such claims flipped between the version this advice originally targeted and the version tested. Fastest to rot, and rots in the harmless direction: you stop needing a workaround.
2. **Silent-acceptance behaviour** — an endpoint that accepts bad data today may validate it tomorrow. Rots in the *harmful* direction if you removed the client-side check that was compensating.
3. **Error-model and idempotency behaviour** — more stable, because changing it breaks existing integrations. Still not guaranteed.
4. **Scope and inheritance semantics** — the most stable layer, being tied to the data model rather than to a controller.
5. **Sequencing and ownership rules** — effectively version-independent. Which subtree a feed owns is a project decision, not an API fact.

Layers 1 and 2 are why re-testing matters. Layer 5 is why these skills are worth having at all.

# When to re-test

- Before trusting these skills on a **major or minor upgrade**. A patch release is lower risk but not zero — the tested version is itself a patch release, and it differs behaviourally from its predecessors.
- When a claim here contradicts what the install actually does. The install wins, always.
- When a third-party module that touches the same subsystem is added or upgraded.

# How to re-test cheaply

The decisive test for most of these is the same: **execute it against a disposable install and read back the stored state**, rather than trusting the response. A sandbox with sample data and more than one store view covers the large majority of what these skills assert.

The single most valuable check needs no fixtures: **run the integration twice and diff**. A correct integration's second run is a no-op. If it is not, something is non-idempotent regardless of what it reported — and that is true on every version.
