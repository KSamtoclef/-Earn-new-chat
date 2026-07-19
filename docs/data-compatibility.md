# Existing Supabase compatibility plan

## Commitments

- Keep the current Supabase project.
- Preserve Auth user UUIDs.
- Never expose a service-role key in browser code.
- Do not overwrite or delete legacy financial records during discovery.
- Reconcile displayed balances against canonical credits and debits before cutover.
- Preserve user day, chat, task, sharing, KYC, withdrawal, and admin-review state when mappings are reliable.
- Route ambiguous records to explicit review instead of silently changing them.

## Discovery before migration

The next database step is read-only inventory of:

1. Tables, columns, constraints, indexes, triggers, functions, and RLS policies.
2. Auth/profile coverage and orphan records.
3. Balance sources and reconciliation differences.
4. Duplicate reward and withdrawal identifiers.
5. Day/task/share/KYC/withdrawal status distributions.
6. Admin roles and protected function privilege boundaries.
7. Analytics and presence volume, retention, and indexes.

## Migration strategy

New canonical tables are additive. Compatibility readers map legacy records without mutating them. Dual-read verification compares old and new state. Cutover occurs only after blocking checks pass. Legacy tables remain read-only during the rollback window.
