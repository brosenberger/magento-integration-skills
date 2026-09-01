---
name: magento-integration-customers
description: >-
  Use when an external system creates or updates Magento 2 customers, addresses or group assignment. Covers the unauthenticated create endpoint that also sends mail, mail that can only be discarded rather than deferred, an address update path that destroys the row and everything referencing it, and group assignment that a later address save silently reverses. Part of the `magento-integration-*` group.
---

# magento-integration-customers — writes that succeed and undo themselves

Group skill under `magento-integration-flow`. Agnostic of client and transport.

## The one rule

**A customer write is not one write.** Creating a customer sends mail, may reassign the group you just set, and may replace address rows that other tables point at — all under a `200`, all without an error to notice. Every failure mode here is a successful call with a consequence somewhere else.

## Account creation

**The create endpoint is unauthenticated.** The route is declared `anonymous`, so it works with no credentials at all. Two consequences: anyone can create accounts and make the shop send mail to an address of their choosing, and any hardening you assume is present is not.

Closing it is a small module that redeclares the route with a management ACL. Verified to work: anonymous is refused afterwards, an authenticated integration is not. Resources merge rather than replace, so the refusal names both the old and new requirement.

It is not the only unauthenticated route on this entity. **The password-reset trigger is also anonymous**, so an unauthenticated caller can make the shop mail any address it holds — that one core does throttle, by address and origin within a window, so the mail vector is capped where account creation is not. Know which of the two you are looking at before concluding the surface is hardened.

**Creation always notifies.** Omitting the password does not silence it — it selects a "set your password" variant instead of the welcome one. There is no quiet-create path: the only method that saves a customer without notifying is the repository save, whose sole route is the update for a customer that already exists.

**Setting a group requires authentication**, even though creation does not. Supplying a group id flips the same route to demanding a management ACL — sensible, or anyone could self-assign into a wholesale group. So any real integration authenticates, and "the create endpoint needs no token" is only true for the trivial case.

## Scope is validated in one direction only

- A store view belonging to a **different website** is rejected with a clear error.
- The **admin scope**, and an **omitted** scope, are silently rewritten to the default.

The asymmetry matters more than the rule: the loud failure is the one you catch in testing, and the silent one is the one that reaches production with every customer on a website nobody chose.

This is not cosmetic. **The account email resolves from the customer's own store** — template, locale and sender all follow it. An integration that omits the store mails everyone in the default store view's language, and the only symptom is complaints.

**Email uniqueness is per website by default.** The same address creates two distinct customer records on two websites, each with its own identifier. A sync keyed on email alone will collide or update the wrong record. The error text is identical under both global and per-website configuration while meaning different things, so it cannot be used to detect which install you are on.

## Passwords

**Legacy hashes cannot be imported.** The method that accepts a pre-hashed password exists but has no route. The only create route takes plaintext or nothing.

Plaintext works and is the trap: it crosses the integration boundary, sits in the export, and lands in request logging. Server-side rules still apply (minimum length, a minimum number of character classes) and their messages carry unresolved placeholders with the real values in a separate parameters array, so logging the message alone yields a string with `%1` in it.

**Create with no password and let each customer set their own.** That is the only shape that does not move credentials around — and it is the reason the mail problem below is unavoidable rather than incidental.

## Mail cannot be deferred, only discarded

The obvious migration plan — silence mail during the load, send it afterwards — is not supported.

The global mail switch is implemented as a plugin that does not proceed. The message is **discarded, not queued**. There is no spool to flush, no command to send them later, and asynchronous sending exists only for sales mail. The same switch also silences order confirmations, which matters when customers are loaded into a shop that is already trading.

So the decision is: accept a mail-out at import time, or silence account mail and drive password setup deliberately at go-live. **Password policy and mail policy are one decision**; an integration that treats them separately makes one of them by accident.

If you take the second path, a bulk run of password resets meets core's own throttling. A CLI process has no remote address, so every send is recorded with an empty one and the quantity cap applies to the whole batch rather than per customer — a batch of six sent one and failed five. Switching the reset protection to by-email for the duration fixes it; sleeping between sends does not, because the limit is a count inside a window rather than a rate.

## Addresses — the hazard

**Send an address on an update without its identifier and the row is destroyed, not duplicated.** Magento deletes it and creates a replacement with a new identifier. There is no visible duplicate to notice, and two things happen silently:

- **Quote and order tables hold the address identifier with no foreign key behind it.** Open carts and historical orders are left pointing at a row that no longer exists. Nothing fires, nothing logs, and the symptom surfaces later somewhere else entirely.
- **Every custom attribute on that address is destroyed by cascade.** The attribute value tables are the only things with foreign keys to the address, all cascading.

**Always send the address identifier.** Read the customer, carry the existing identifiers into the update, and the row is updated in place. An integration that only ever pushes will churn identifiers indefinitely and leave a widening trail of dangling references, without a single error.

Addresses are EAV, so carrying your own key as a custom attribute needs no code and is worth doing — but it protects your bookkeeping only. It does nothing for Magento's internal references, which cannot be repaired from outside afterwards. It is a complement to not churning, never a substitute.

Two smaller ones: several addresses flagged default resolve last-one-wins with no error, and an address supplied at creation does not become the default unless flagged.

## Groups and tax classes

**There is no address search.** Core exposes no endpoint that queries addresses, and address fields are not top-level on the customer, so they cannot be filtered on either — reconciling an external key means fetching the customer and matching client-side. Plan the reconciliation around customer-level reads, not around a lookup that does not exist.

**Discover them, do not hardcode.** Group search returns every group with its tax class identifier and name, and the default group is readable per store. Identifiers are conventional on a fresh install and wrong on a real one.

**The tax class belongs to the group, not the customer.** There is no tax-class field on a customer — only the VAT number, which is a different thing. An integration assigns a group and the tax class follows. Setting a customer's tax class directly is a category error and a common request.

**Automatic group assignment will reverse your work.** Off by default and enabled by merchants for EU VAT, it runs on **address save** and the damaging branch has no VAT number in it: a default billing address without one moves the customer back to the default group. Created in a wholesale group, landed in the default, no warning.

The guard is a disable-auto-group-change field on the customer, and it works — but it is typed as an integer and rejects a boolean with a type error. Only the **default billing** address is processed (or default shipping, depending on the tax-calculation address type), which is why this reproduces intermittently for anyone testing casually.

## Extending the entities

Three different answers for three entities, and assuming one generalises will plan the wrong work:

| Entity | How to add a field |
|---|---|
| Customer, address | EAV — add an attribute, no code |
| Customer group | **Code**: an extension attribute declaration, a side table, and read/write plugins on the repository |

A group is a flat table and its interface is not custom-attribute capable, so there is no admin route to extending it. Core's own website-exclusion field is a complete worked precedent to copy.

An EAV attribute that is **not assigned to an attribute set** is accepted, returns `200`, and is silently discarded. That is the same silence the catalog side has. Empty extension attributes are omitted from responses entirely, so support cannot be detected by inspecting a read.

## Two that are easy to miss

- **Newsletter consent has no endpoints.** The newsletter module ships no web API at all; the only route is an extension attribute on the customer. For a migration this is marketing consent, so getting it wrong either drops an opted-in base or subscribes people who never agreed. Note it is declared boolean and accepts one, unlike the group guard above — **types come from each field's declaration, not a convention.**
- **A created customer is absent from the admin grid until its indexer runs.** On update-by-schedule that waits for cron. It is a display problem rather than a data one, but anyone verifying a migration by looking at the grid will under-count and conclude the import failed.

Out of scope in Open Source: company/B2B, customer segments and store credit are Commerce; wishlist and review have no web API.

## Verification

Executed against Magento Open Source 2.4.8-p5 with a second website added, single MSI source, with source cross-checks against a 2.4-develop checkout. Measured rather than read: the anonymous create and its mail, the three scope payloads, per-website uniqueness across two websites, both password validation errors, the address replace-and-recreate, group and tax-class discovery, group assignment requiring authentication, automatic group assignment reversing it, the extension-attribute round trip on a group, newsletter consent both directions, and the customer grid before and after reindex.
