---
name: security-sensitive-change
description: Auth, payments, permissions, secrets, private data, untrusted input, webhooks, migrations, destructive actions, redirects, CSRF, SQL construction, or trust-boundary changes.
activation: automatic
---

# Security-Sensitive Change

Apply the global High-risk approval boundary first. Verify current primary provider/framework
documentation when behavior is version-sensitive. Keep privileged state server-authoritative,
validate untrusted input at trust boundaries, use least privilege and secure defaults,
preserve tenant isolation, and protect secrets. For retried external events/payment-like
flows, preserve integrity and idempotency. Add relevant negative tests (unauthorized,
malformed, replayed, cross-tenant, invalid-state) when applicable.

Refuse to implement:
- hard-coded secrets;
- SQL built by concatenating untrusted input;
- disabled CSRF protection;
- `eval` / `exec` on untrusted input;
- unvalidated redirects.

Briefly explain the risk and provide the safe equivalent.

Require explicit confirmation for destructive/irreversible operations, production deploys,
data deletion/risky migrations, breaking public APIs, auth behavior changes, major production
dependencies, material scope expansion, private-data/repository transfer to external services,
or creating/modifying/publishing shared/production resources. Read-only dependency metadata,
package lookup, and repository fetches do not require confirmation unless private data or an
unapproved service is involved.
