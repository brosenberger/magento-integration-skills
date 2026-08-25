---
name: magento-integration-media
description: >-
  Use when an external system pushes Magento 2 product images. Covers unbounded duplication on repeated runs, the global-gallery versus per-store-view-role split, and why deleting an image another store view depends on is refused. Part of the `magento-integration-*` group.
---

# magento-integration-media — duplication and the role scope split

Group skill under `magento-integration-flow`. Agnostic of client and transport.

## Media belongs on its own cadence

Prices change nightly; photographs do not. Media is the part of a catalog sync that should run as a separate, less frequent job — and the part that grows without bound if it does not.

## Nothing is deduplicated

The platform does **not** deduplicate by content, by filename, or by any label you attach. Re-sending the same photograph on every run produces a new file, a new gallery record and a fresh set of cached derivatives each time, indefinitely.

Deduplication is entirely the client's job:

- Keep a mapping of external asset to gallery entry, or record a content hash somewhere on the entry that you can read back.
- Read the existing gallery and skip the upload when the hash is already present. Two calls to avoid an unnecessary write is a good trade here, unlike for product data.
- Keep image bytes out of the product write itself; inline content inflates the payload substantially and holds it in memory for the whole operation.

## The gallery is shared; the roles are not

This is the trap that only appears once a store has more than one store view.

**The image files and gallery are global. The decision about which image fills which role — the main image, the thumbnail, the listing image — is per store view.** So the picture is shared by everyone and the choice of picture is not.

Writing a role through a scoped route therefore creates a per-store-view override exactly like any other scoped attribute, with the same permanence.

## Deleting an image another store view still uses

Refused, not silently broken — which is the good news. The bad news is the refusal **names neither the store view nor the role**, so a feed removing a discontinued photograph gets a failure it cannot act on, because the blocking role lives in a scope the external system does not model. Resolving it means querying which scopes pin a role to that file.

**The workaround is worse than the problem.** Clearing the role to free the image for deletion succeeds — and writes an explicit "no image" value rather than removing the override. That store view then shows a placeholder permanently while every other scope resolves correctly, with no error and nothing in any log. An explicit empty value is a value, not an absence, so inheritance never resumes.

Correct move: **reassign the role to the replacement image**, which overwrites the override, rather than blanking it.

Note also that the protective refusal may be conditional on the product being visible in more than one scope. Do not assume it always fires; verify on your own store topology.

## Verification

- Re-run and confirm no new files, no new gallery records.
- Count gallery records per product and alert on growth — unbounded growth is the duplication failure in progress.
- Sweep for scopes pinned to an explicit "no image" value; each is a permanent placeholder.
- Confirm role assignments resolve per scope as intended rather than assuming the write took.

## Anti-patterns

- Media in the product write.
- Re-uploading without checking the existing gallery first.
- Writing roles through a scoped route when the feed has no per-store-view photography.
- Clearing a role to make a deletion succeed.
