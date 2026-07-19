# Earn Chat architecture

## Product boundary

The live `earn-chat.com` interface and the archived source define the product identity. ChatEarn contributes architectural lessons only; none of its versioned source files, SQL, hotfixes, reward implementations, or branding are copied.

## Required journey

1. Register or resume an existing Supabase account.
2. Load the authoritative profile, wallet, current day, and task state.
3. Complete guided, coherent chat sessions.
4. Complete server-configured daily tasks and eligible sharing actions.
5. Reach daily progression requirements without exceeding server limits.
6. Complete the five-day first-withdrawal journey.
7. Complete KYC and submit a withdrawal.
8. Enter admin review and later resume from the same state.

## Source of truth

| Concern | Canonical owner | Browser authority |
|---|---|---|
| Identity | Supabase Auth | Submit credentials and manage session |
| Profile | Canonical profile table | Read only |
| Balance | Immutable wallet ledger | Read only |
| Reward amount | Server configuration and functions | None |
| Daily limits | Server progression rules | Read only |
| Chat state | Conversation session and messages | Submit text or intent |
| Tasks | Server task opportunities | Request actions only |
| Sharing | Server-recorded eligible attempts | Initiate share only |
| KYC | Submission and admin review state | Submit approved fields/documents |
| Withdrawal | Withdrawal state machine | Submit request only |
| Admin | Protected RPCs with role checks | Render paginated responses |

## Runtime ownership

Each feature has one module and one event-registration boundary. Modules communicate through explicit service methods and application events. There is no global DOM observer, competing reward system, or browser balance calculation.

## Financial transaction pattern

1. Authenticate.
2. Acquire a per-user lock.
3. Load current eligibility.
4. check the request idempotency key.
5. Calculate the amount from server data.
6. Append one immutable ledger entry.
7. Update related progression state in the same transaction.
8. Return the authoritative balance and state.

## Performance contract

- One application bootstrap request after authentication.
- Event-driven updates instead of repeated polling.
- Admin tabs load only when selected and use indexed pagination.
- Listeners are installed once and removed when their owner unmounts.
- Mobile Safari and Chrome are first-class targets.
