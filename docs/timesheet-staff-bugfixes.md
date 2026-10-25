# Module status, timesheets and employee directory — 25 October 2026

Completed modules reject a Team Leader's WIP change immediately in the app.
The existing backend transaction also rejects it, including when the app's
module list is stale. Both paths use: “This module is already completed and
cannot be moved back to WIP.” The screen displays the returned message through
its existing error notification. Open modules retain their WIP/Billing flow.

My Timesheets accepts additional modules while earlier entries are pending.
There was no intentional pending-entry restriction in the current rules.
Regression coverage now submits two different modules through real Firestore
transactions with both entries pending, checks that both are readable by the
employee, checks duplicate retries, and retains cumulative attendance limits.
This test freezes only its copy of the work-week clock to Monday, allowing
the regression to run on Sunday without changing application rules.

The app returns the confirmed timesheet write without a second database read.
It sets the list to a successfully loaded state even when logging hours was
opened before My Timesheets. Older in-flight fetches cannot erase that new
entry. Lists sort by work date and creation time, retain their contents while
refreshing, and refresh from Firestore on re-entry for current approval status.
Successful form submission displays the updated shared list immediately rather
than waiting for another full fetch. Daily attendance, module eligibility,
work-week and approval restrictions remain in place.

Employee Management queries only EMPLOYEE and TEAM_LEADER records, with the
same scope applied to rendering and search. CAPTAIN and PROJECT_CONTROLLER
records are hidden there. The Captain's separate Project Controller Management
screen continues to request and display Project Controllers explicitly.
The optional staffOnly backend filter leaves other existing API consumers'
unfiltered employee directory unchanged.

## Validation

- Backend: 122 tests passed against local Auth and Firestore emulators.
- Flutter: 53 passed; the same four documented lock-screen pixel-comparison
  failures remain. All five new status/timesheet/directory tests passed.
- Firestore: the new multi-module pending-timesheet regression passed,
  including unchanged daily limits and duplicate-retry accounting.
- Flutter analysis and git diff --check passed.

These changes are local source changes. Rollout requires an updated backend
and rebuilt mobile application. The earlier project/activity fixes also require
their Firestore rules deployment. Hosted/device acceptance was not performed.
