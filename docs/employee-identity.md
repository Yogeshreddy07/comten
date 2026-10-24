# Employee identities

New mobile accounts receive an employee code when saved, starting after the
highest existing `EMP` number (for example `EMP009` becomes `EMP010`). Existing
codes stay unchanged. The form and review screen show that the code is assigned
on save; the account-created dialog shows the issued code with the temporary
password. The directory sorts codes numerically within their prefixes.

Deploy the updated backend before distributing the updated mobile APK. New
clients omit `employeeCode` from `POST /api/employees`; the backend still accepts
explicit codes for compatibility with older clients, subject to uniqueness.

The backend enforces uniqueness on creation and editing, including inactive and
soft-deleted employees. Email comparison ignores surrounding whitespace and
case. Indian 10-digit numbers and their `+91` equivalents compare identically;
phone spacing and punctuation do not bypass the check. Empty optional phone
numbers are allowed. Duplicate fields return HTTP 409 with a specific message.

Identity checks, code allocation and employee writes share a Firestore
transaction guarded by `counters/employee-identities`. It checks legacy employee
records too, so no backfill is required. All identity mutations must use this API.
The check reads the directory, so its cost grows with the number of employees.
For a much larger directory, migrate legacy contacts to unique reservation
documents before replacing this scan with indexed identity lookups.

Firebase Auth provisioning follows the identity reservation. A failed attempt
releases the employee/contact reservation, while keeping the counter advanced;
there can be sequence gaps after failures, and issued codes are never reused.
Existing duplicate data is not automatically changed or merged.

The Reason for Delay picker reads assigned module fields directly, without
loading full employee profiles. This avoids permission failures caused by
historical module members outside the lead's current peer roster. Employee
profile access rules remain unchanged.
