# CROWN Tournament Clock — implementation specification

Status: design only, not deployed. Branch: feature/crown-members-app.

## Scope and isolation
New tables use crown_clock_ prefix. No existing rating, gacha, user, tournament or ring tables are modified. Initially clock tournaments use independent UUIDs; an optional mapping to an existing tournament is added only after its schema is inspected.

## Tables
- crown_clock_events: id UUID PK, title text, event_date date, starting_stack integer, status (draft/running/paused/finished), current_segment integer, remaining_ms_at_pause bigint, segment_ends_at timestamptz nullable, version bigint, created_at, updated_at.
- crown_clock_segments: id UUID PK, event_id FK, position integer, kind (level/break), duration_seconds integer, small_blind integer nullable, big_blind integer nullable, bb_ante integer nullable; unique(event_id, position).
- crown_clock_counts: event_id PK/FK, unique_players integer, total_entries integer, remaining_players integer, total_chips bigint nullable, updated_at. Validate 0 <= remaining_players <= unique_players <= total_entries. Total chips should be explicitly computed from initial and added stacks, not inferred from entries when reentries have variable stacks.
- crown_clock_prizes: id UUID PK, event_id FK, place_from integer, place_to integer, display_text text, display_order integer.

## Clock state machine
- Start: transaction locks event, loads current segment, sets segment_ends_at = database now() + remaining duration, status=running, increments version.
- Pause: remaining_ms_at_pause = greatest(0, segment_ends_at - database now()), segment_ends_at=null, status=paused, increments version.
- Resume: segment_ends_at = database now() + remaining_ms_at_pause, status=running, increments version.
- Skip/back/reset: authenticated staff only, transaction with row lock; update current_segment and deadline atomically. Do not mutate segment structure while running without explicit reset.
- Natural expiration: server RPC resolves elapsed segments and breaks from the persisted deadline, even when no client is connected. Client displays a predicted countdown from the server timestamp but always reconciles to authoritative state. An idempotent scheduled reconciler or RPC triggered by subscribed clients advances state.
- All writes must be transactional and idempotent where practical; use version checks to reject conflicting staff commands.

## Authorization
- Enable RLS on all new tables before production use.
- Read policy: only publicly designated events and fields; private drafts restricted to staff.
- Write policy: staff role verified server-side using an existing trusted staff mapping, after inspecting current auth implementation. Never trust a client-supplied is_admin flag.
- Use SECURITY DEFINER RPC only with explicit auth checks and safe search_path; do not expose service-role keys in browser.
- No direct public UPDATE/DELETE on clock state.

## UI
- Staff: event selector, start/pause/resume, +/- 1 min, next/previous, reset confirmation, level editor, counts editor, prizes editor, late registration configuration.
- TV: fullscreen, high-contrast large MM:SS, current and next blinds, break, remaining players, total entries, average stack if valid, late-reg status, prize panel.
- Player: read-only mobile live view, event selection, late-reg status, upcoming structure.
- Audio notifications triggered once per transition on designated staff/TV device; browser autoplay restrictions require user activation.

## Late registration
Configure a cutoff segment and optional cutoff time; derive deadline from segment schedule and pause-adjusted event clock. Do not infer that the tournament is open for entry solely from timer state.

## Release checks
1. Identify actual source repository and current frontend framework before implementation.
2. Backup schema/data and confirm recovery method.
3. Apply additive migrations in staging first.
4. Simulate two simultaneous events and multiple staff operators.
5. Test browser reload, offline/online transitions, device clock skew, break transitions, manual overrides and late-reg cutoff.
6. Confirm existing rating, ranking, gacha and authentication regression tests pass.
7. Merge and deploy only after approval.

## Poker Club integration
Not assumed. Separate integration module pending verified API documentation and authorization.