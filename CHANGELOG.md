# Changelog

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
