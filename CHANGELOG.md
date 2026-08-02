# Changelog

## 0.1.0.alpha8

Compatibility verification and semantics alignment against Zero **v1.8.0**
(the latest stable zero-cache/zero-server release). The push wire protocol is
unchanged between Zero 1.5.0 and 1.8.0, so no rollout ordering is required;
this release closes semantic gaps between the gem and the v1.8.0 reference
implementation (`zero-server/src/process-mutations.ts`).

### Fixed (protocol semantics)

- **Unknown mutations now advance the LMID and persist their error result**,
  matching the reference. Previously the LMID was left untouched, which could
  wedge a client into resending the unknown mutation forever. The error
  message is now the reference's `could not find mutator <name>`.
- **Transaction failures are retried once without the mutator** (reference
  `Transactor#transact` semantics, upstream #5634): infrastructure errors
  during the mutation transaction now advance the LMID and persist an `app`
  error result in a second transaction, skipping the mutation instead of
  failing the whole push. Only a failing retry aborts with
  `PushFailed{reason: "database"}`.
- **LMID re-check during failure persistence**: the persist/retry transaction
  re-validates the LMID like the reference. An `alreadyProcessed` race during
  a transaction retry yields an `alreadyProcessed` result; an out-of-order
  race aborts with `PushFailed{reason: "oooMutation"}`; a duplicate detected
  while persisting a pre-transaction failure aborts with
  `PushFailed{reason: "internal"}` (reference `persistPreTransactionFailure`).
- **Top-level catch-all**: unexpected errors now return
  `PushFailed{reason: "internal"}` with the unprocessed mutation IDs instead
  of raising (which surfaced as HTTP 500 / retries in zero-cache).
- **CRUD-typed mutations** (`type != "custom"`) abort the push with
  `PushFailed{reason: "internal", message: "Expected custom mutation"}`,
  matching the reference assertion.
- **`alreadyProcessed` details** now use the reference text and value:
  `Ignoring mutation from <clientID> with ID <id> as it was already
  processed. Expected: <postIncrementLMID>` (previously a different wording
  with an off-by-one expected value).
- **`PushFailed` bodies include `details`** when the failing error carries
  JSON-serializable details.
- **Wrapped non-`ZeroRuby::Error` exceptions** now carry
  `details: {name: "<ExceptionClass>"}` in their `app` error result,
  mirroring the reference's `getErrorDetails` fallback.
- **Message alignment**: parse failures are prefixed with
  `Failed to parse push body: …` and the unsupported-push-version message is
  `Unsupported push version: <v>` (reference format).
- `OutOfOrderMutationError#error_type` corrected from `"ooo"` to the wire
  value `"oooMutation"` (defensive only — this error always escalates to a
  top-level `PushFailed`).
- **JS-falsy `details` are omitted** (`0`, `""`, `false`, `NaN`), matching the
  reference's `details ? {details} : {}` guards, both on the wire and in the
  persisted `mutations` row.
- **`PushFailed{database}` bodies match the reference's
  `DatabaseTransactionError` framing**: message is
  `Failed to open database transaction: <cause>` /
  `Database transaction failed after opening: <cause>` with
  `details: {name: "DatabaseTransactionError"}`. The previous
  `Failed to persist mutation failure for …` context now goes to the server
  log instead of the wire.
- **Non-`StandardError` exceptions** from handlers (e.g. `NotImplementedError`
  when `#execute` is missing) are handled like the reference's
  catch-everything semantics — app error result, LMID advanced — instead of
  escaping as HTTP 500. Process-control exceptions (`SignalException`,
  `SystemExit`, `NoMemoryError`) still propagate.
- **`_zero_cleanupResults` args with unknown extra keys are rejected**
  (skipped with a warning, no deletion), matching the reference's strict-mode
  valita validation.

### Changed

- **Explicit `userID: null` support**: a context containing an explicit
  `user_id: nil` key now echoes `"userID": null` (zero-cache's
  server-validated "logged out" state). Contexts without a `:user_id` key and
  without a resolvable `current_user` continue to omit `userID`. Note: if you
  previously passed `user_id: nil` alongside `current_user`, the explicit nil
  now wins — remove the key to fall back to `current_user`.
- **Stricter push body validation** per `pushBodySchema`: top-level field
  types and per-mutation `id`/`clientID`/`name`/`args` shapes are validated
  and rejected with `PushFailed{reason: "parse"}`. Unknown extra fields
  (`schemaVersion`, `auth`, `traceparent`, …) still pass through.
- **`_zero_cleanupResults` argument validation** matches
  `cleanupResultsArgSchema`: malformed args (empty bulk `clientIDs`, unknown
  `type`, missing `upToMutationID`, …) are skipped with a warning and never
  touch the database; the intercept is skipped for non-`custom` typed
  mutations.

## 0.1.0.alpha7

Compatibility upgrade from Zero 0.25.12 → 1.5+.

**Required rollout:** deploy `zero-cache@1.5+` before upgrading this gem. The new
response shape is not parseable by `zero-cache` 1.4 and earlier.

### Breaking changes

- **Response shape**: successful pushes now return
  `{kind: "MutateResponse", mutations: [...], userID: ...}` (1.5 protocol).
  Previously `{mutations: [...]}`. The `userID` is included when the controller
  passes an authenticated user via `context[:current_user]` or
  `context[:user_id]`.
- **`LmidStore` interface**: `fetch_and_increment`, `write_mutation_result`,
  and `delete_mutation_results` now take a required `upstream_schema:` kwarg.
  Custom store implementations must be updated.
- **Persist-failure semantics**: when LMID/result persistence after a mutation
  error fails, the batch now aborts with `PushFailed{reason: "database"}` and
  lists unprocessed mutation IDs. Previously, the gem logged a warning and
  returned a (desyncing) success response. Matches the TS reference.

### Features

- **`userID` echo** for Zero 1.5 "Authenticated Client Groups". The gem reads
  `context[:user_id]` or `context[:current_user]&.id&.to_s` and echoes it in
  the response so zero-cache can enforce that only tabs from the same user
  share a client group.
- **Configurable `upstream_schema`**: previously hardcoded to `zero_0`. The
  controller now passes `context[:upstream_schema] = params[:schema]` (zero-
  cache sends `?schema=` on every request). Deployments with non-default
  `ZERO_APP_ID` / `ZERO_SHARD_NUM` now work without code changes.
- **Explicit `_zero_cleanupResults` `type: "single"`** handling alongside the
  legacy (no-type) and `type: "bulk"` variants.

### Docs

- README updated to declare compatibility with Zero 1.5+ and document the
  rollout requirement, the recommended `/zero/mutate` endpoint convention,
  the auth flow (`Authorization: Bearer`, `X-Api-Key`), and how to surface
  structured errors via `ZeroRuby::Error.new(msg, details: {...})`.

## 0.1.0.alpha6 and earlier

See git history.
