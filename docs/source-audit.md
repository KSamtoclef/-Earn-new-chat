# Original Earn Chat source audit

## Snapshot

- Source: `archive/original-earn-chat.html`
- Size: approximately 280 KB and 4,513 lines.
- One inline stylesheet.
- Four inline JavaScript blocks.
- Approximately 179 named functions.
- Approximately 100 event-listener registrations.
- Five interval registrations and forty timeout registrations.
- No duplicate HTML IDs were detected.
- All extracted inline JavaScript passed syntax parsing during the initial audit.

## Preserve

- Brand colors, typography character, mobile card system, and navigation.
- Registration and login presentation.
- Five-day progress model and daily dashboard hierarchy.
- Guided chat, task, sharing, KYC, withdrawal, leaderboard, profile, and admin concepts.
- Existing Supabase Auth users and compatible business records.
- Current public wording unless a security, accuracy, or compliance review requires a correction.

## Rewrite into named owners

| Current responsibility | Destination |
|---|---|
| Supabase initialization | `assets/js/services/supabase.js` |
| Authentication/session | `assets/js/features/auth.js` |
| Screen navigation | `assets/js/core/router.js` |
| Dashboard | `assets/js/features/dashboard.js` |
| Guided conversations | `assets/js/features/chat.js` |
| Wallet/rewards | `assets/js/features/wallet.js` |
| Daily tasks | `assets/js/features/tasks.js` |
| Sharing | `assets/js/features/sharing.js` |
| KYC | `assets/js/features/kyc.js` |
| Withdrawals | `assets/js/features/withdrawals.js` |
| Leaderboard/profile | Dedicated feature modules |
| Notifications | One consent-aware notification module |
| Analytics/presence | One event service |
| Admin | Separate `admin.html` and lazy modules |

## Archive candidates after parity

- The original monolithic HTML runtime.
- Browser-side balance and reward calculations.
- Direct sensitive-table access from admin code.
- Inline configuration containing operational offer URLs.
- Duplicate notification loaders or permission diagnostics.
- Inline onclick handlers after equivalent module listeners pass parity tests.
- Timer-based behavior that can be replaced by server timestamps or events.

Nothing is deleted merely because it appears old. Removal requires a mapped replacement, a passing test, and a documented rollback route.
