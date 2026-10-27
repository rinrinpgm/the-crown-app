# CROWN Members App — implementation plan

## Non-destructive requirements
- Preserve existing Supabase project, auth users, tournament and ring ratings, rankings, gacha, and histories.
- Do not rename or drop existing database tables or columns.
- Do not change production branch until tested and approved.
- Keep existing URLs and current flows operational.

## Phase 1: repository audit
- Identify framework, routing, deployment configuration, Supabase client and existing auth.
- Map current routes and UI components.
- Identify existing tournament calendar, rating, ranking, gacha and history screens.
- Verify RLS and permissions before adding any tables.

## Phase 2: mobile app shell
- Responsive home dashboard with today's tournaments, rating card, daily gacha entry and quick links.
- Bottom navigation: Home / Tournaments / Results / My Page.
- Reuse existing components and data sources; no new rating calculation implementation.

## Phase 3: PWA
- Manifest, app icons, installability, safe service-worker strategy if needed.
- Test iOS Safari Add to Home Screen and Android installation.

## Phase 4: optional enhancements
- Tournament detail and booking with conflict checks.
- Push notifications (opt-in).
- Poker Club integration only after API permission and documentation verification.

## Acceptance criteria
- Existing accounts can log in unchanged.
- Existing ratings, rankings, gacha and history display the same values.
- No database data loss or duplicate rating calculations.
- Mobile navigation works on iOS and Android.
- Production deployment occurs only after review and smoke tests.
