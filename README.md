# Earn Chat

Clean, production-oriented rebuild of `earn-chat.com` that preserves the current product identity and existing Supabase data.

## Status

Foundation and compatibility-audit stage. The archived original is reference-only and is never deployed or executed by the rebuilt application.

## Non-negotiable rules

- Preserve the current Earn Chat visual identity and five-day journey.
- Keep existing Supabase Auth UUIDs and compatible user data.
- All financial state changes happen through protected server functions.
- Use one wallet ledger, one reward engine, and one journey state machine.
- Do not introduce version, hotfix, final, patch, or stabilizer filenames.
- Archive legacy behavior only after parity, reconciliation, and rollback checks pass.

See `docs/architecture.md`, `docs/source-audit.md`, `docs/ui-contract.md`, and `docs/data-compatibility.md`.
