# Project creation and activity deletion fixes — 25 October 2026

Project creation now prepares its display response before writing and commits
the project, first module, permission rosters and Project ID reservation in
one Firestore transaction. Response hydration or roster failures therefore do
not leave a saved project behind a failed response. On older backends, a failed
secondary module detail read no longer changes an acknowledged creation into
a failed submission. The wizard also ignores repeat submission after success.

Project IDs are compared after trimming surrounding whitespace and ignoring
case. Reservations reject simultaneous duplicate submissions. A projected
legacy-project check protects existing IDs, including inactive/deleted records.
Existing duplicate records are retained; the fix does not rename historical
projects or rewrite their references. New codes currently require a scan of
projectCode fields to cover records created before reservations existed. That
legacy compatibility read grows with the project count and should be replaced
with a verified reservation backfill before scaling to large collections.

Activity deletion checks both billable and non-billable module assignments on
the trusted backend. Assigned activities return HTTP 409 with instructions to
remove their assignments first; inactive, retained modules also count. Unused
activities are soft-deleted with active=false. Firestore rules require this
authoritative path for deletion, while list reads and activity creation keep
using the Firestore SDK. Assignment validation reads activities inside write
transactions to conflict safely with simultaneous deletion.

Cache revisions reject stale in-flight read results after mutations. Successful
backend writes invalidate cached data again after acknowledgement. Activity
reads use the server when refreshing, and view-model revisions stop older
fetches replacing confirmed mutations. The existing list remains visible while
refreshing, and deletion updates the list without a full refetch.

## Validation

- All 119 backend tests passed against isolated Auth and Firestore emulators.
- Flutter full suite: 48 passed, four existing lock-screen pixel-comparison
  failures (also documented in project-performance.md). Project/activity/cache
  regressions passed, including failed post-creation detail reads, repeat
  submission, stale reads and assigned-activity rejection.
- Firestore rules: 15 passed, one existing timesheet test fails because the
  current day is Sunday and the unchanged rules reject Sunday submissions.
  The new activity deletion / reservation access test passed.
- Flutter analysis and git diff --check passed.
- Three finite local runs with 10 employees: project creation median 148.3 ms,
  maximum 205.2 ms. These timings include TestClient and real Firebase emulators,
  but exclude phone rendering, hosted cold starts and internet latency.

Rollout requires the backend, Firestore rules and rebuilt mobile application
together. No hosted deployment, historical-data cleanup or installed-app
replacement was performed by this change.
