# zero_ruby

A Ruby gem for handling [Zero](https://zero.rocicorp.dev/) mutations with type safety, validation, and full protocol support.

## Features

- **Type coercion & validation** - Built on [dry-types](https://dry-rb.org/gems/dry-types/) with String, Integer, Float, Boolean, ID, ISO8601Date, ISO8601DateTime
- **Type generation** - Generates TypeScript types for your frontend mutators
- **LMID tracking** - Duplicate and out-of-order mutation detection using Zero's `zero_0.clients` table
- **Push protocol** - Version validation, transaction wrapping, retry logic

## Installation

Add to your Gemfile:

```ruby
gem 'zero_ruby'
```

## Usage

### 1. Define mutations

By default, the entire `execute` method runs inside a transaction with LMID (Last Mutation ID) tracking. Use [`skip_auto_transaction`](#manual-transaction-control) to manually control what runs inside the LMID transaction.

```ruby
# app/zero/mutations/post_update.rb
module Mutations
  class PostUpdate < ApplicationMutation
    argument :id, Types::ID
    argument :post_input, Types::PostInput

    def execute(id:, post_input:)
      post = current_user.posts.find(id)
      authorize! post, to: :update?
      post.update!(**post_input)
    end
  end
end
```

### 2. Register mutations in schema

```ruby
# app/zero/app_schema.rb
# The mutation names should match the names used in your Zero client:
#   mutators.posts.update({ id: "...", post_input: { title: "..." } })
#   -> maps to "posts.update"
class ZeroSchema < ZeroRuby::Schema
  mutation "posts.update", handler: Mutations::PostUpdate
end
```

### 3. Add zero_controller and route

```ruby
# app/controllers/zero_controller.rb
class ZeroController < ApplicationController
  # Skip CSRF for API endpoint
  # skip_before_action :verify_authenticity_token

  def push
    if request.get?
      # GET requests return TypeScript type definitions
      render plain: ZeroSchema.to_typescript, content_type: "text/plain; charset=utf-8"
    else
      # POST requests process mutations
      body = JSON.parse(request.body.read)

      # Build context hash with whatever your mutations need.
      # Access in mutations via ctx[:current_user]
      context = {
        current_user: current_user,
      }

      result = ZeroSchema.execute(body, context: context)
      render json: result
    end
  rescue JSON::ParserError => e
    render json: {
      kind: "PushFailed",
      origin: "server",
      reason: "parse",
      message: "Invalid JSON: #{e.message}",
      mutationIDs: []
    }, status: :bad_request
  end
end
```

```ruby
# config/routes.rb
match '/zero/push', to: 'zero#push', via: [:get, :post]
```

## Define custom input types (optional)

```ruby
# app/zero/types/post_input.rb
module Types
  class PostInput < Types::BaseInputObject
    argument :title, Types::String.constrained(min_size: 1, max_size: 200)
    argument :body, Types::String.optional
    argument :published, Types::Boolean.default(false)
  end
end
```

## Configuration

Create an initializer to customize settings:

```ruby
# config/initializers/zero_ruby.rb
ZeroRuby.configure do |config|
  # Storage backend (:active_record is the only built-in option)
  config.lmid_store = :active_record

  # Retry attempts for transient errors (default: 1)
  config.max_retry_attempts = 1

  # Push protocol version (reject requests with different version)
  config.supported_push_version = 1
end
```

## TypeScript type generation

ZeroRuby generates TypeScript type definitions from your Ruby mutations. GET requests to `/zero/push` return the types.

### Setup

- Set `ZERO_TYPES_URL` env var to your host `http://example.com/zero/push`
- `npm install ts-to-zod --save-dev`
- Add the following script to generate types and zod schemas

```json
{
  "scripts": {
    "zero:types": "mkdir -p lib/zero/__generated__ && curl -s $ZERO_TYPES_URL/zero/push > lib/zero/__generated__/zero-types.ts && npx ts-to-zod lib/zero/__generated__/zero-types.ts lib/zero/__generated__/zero-schemas.ts"
  }
}
```

### Use with Zero Mutators

```typescript
import { defineMutator, defineMutators } from '@rocicorp/zero'
import {
  postsCreateArgsSchema,
  postsUpdateArgsSchema,
} from './zero/__generated__/zero-schemas'

export const mutators = defineMutators({
  posts: {
    update: defineMutator(postsUpdateArgsSchema, async ({ tx, args }) => {
      await tx.mutate.posts.update({
        id: args.id,
        title: args.postInput.title,
        updatedAt: Date.now(),
      })
    }),
  },
})

export type Mutators = typeof mutators
```

## Types

ZeroRuby provides types built on [dry-types](https://dry-rb.org/gems/dry-types/). When you inherit from `ZeroRuby::Mutation` or `ZeroRuby::InputObject`, types are available via the `Types` module:

```ruby
# Basic types
argument :name, Types::String
argument :count, Types::Integer
argument :price, Types::Float
argument :active, Types::Boolean
argument :id, Types::ID               # Non-empty string
argument :date, Types::ISO8601Date
argument :timestamp, Types::ISO8601DateTime

# Optional types (accepts nil)
argument :nickname, Types::String.optional

# Default values
argument :status, Types::String.default("draft")
argument :enabled, Types::Boolean.default(false)
```

## Validation with Constraints

Use dry-types constraints for validation:

```ruby
# Length constraints
argument :title, Types::String.constrained(min_size: 1, max_size: 200)
argument :code, Types::String.constrained(size: 6)  # Exact size

# Numeric constraints
argument :age, Types::Integer.constrained(gt: 0, lt: 150)
argument :quantity, Types::Integer.constrained(gteq: 1, lteq: 100)

# Format (regex)
argument :slug, Types::String.constrained(format: /\A[a-z0-9-]+\z/)

# Inclusion
argument :status, Types::String.constrained(included_in: %w[draft published archived])

# Exclusion
argument :username, Types::String.constrained(excluded_from: %w[admin root system])

# Non-empty (filled)
argument :email, Types::String.constrained(filled: true)

# Combine constraints
argument :name, Types::String.constrained(min_size: 1, max_size: 100, format: /\A[a-zA-Z ]+\z/)
```

### Available Constraints

| Constraint | Description | Example |
|------------|-------------|---------|
| `min_size` | Minimum length | `min_size: 1` |
| `max_size` | Maximum length | `max_size: 200` |
| `size` | Exact length | `size: 6` |
| `gt` | Greater than | `gt: 0` |
| `gteq` | Greater than or equal | `gteq: 1` |
| `lt` | Less than | `lt: 100` |
| `lteq` | Less than or equal | `lteq: 99` |
| `format` | Regex pattern | `format: /\A\d+\z/` |
| `included_in` | Value must be in list | `included_in: %w[a b c]` |
| `excluded_from` | Value must not be in list | `excluded_from: %w[x y]` |
| `filled` | Non-empty string | `filled: true` |

## Type coercion

Types automatically coerce compatible values:

| Type | Accepts | Rejects |
|------|---------|---------|
| `String` | `"hello"` | `nil` |
| `Integer` | `42`, `"42"`, `3.7` → `3` | `"abc"`, `""` |
| `Float` | `3.14`, `"3.14"`, `42` → `42.0` | `"abc"`, `""` |
| `Boolean` | `true`, `false`, `"true"`, `"false"` | `"yes"`, `1`, `0` |
| `ID` | `"abc"` | `""` (empty string) |
| `ISO8601Date` | `"2025-01-15"` → `Date` | `"invalid"`, `""` |
| `ISO8601DateTime` | `"2025-01-15T10:30:00Z"` → `DateTime` | `"invalid"`, `""` |

## Manual transaction control

By default, the entire `execute` method runs inside a transaction in order to atomically commit database changes with the LMID update. Use `skip_auto_transaction` when you need to run code before or after the transaction:

```ruby
class PostUpdate < ApplicationMutation
  skip_auto_transaction

  argument :id, Types::ID
  argument :post_input, Types::PostInput

  def execute(id:, post_input:)
    # 1. Pre-transaction (LMID incremented on error)
    post = current_user.posts.find(id)
    authorize! post, to: :update?

    # 2. Transaction (Transaction rolled back, LMID incremented on error)
    transact do
      post.update!(**post_input)
    end

    # 3. Post-commit - only runs if transact succeeded
    NotificationService.notify_update(id)
  end
end
```

With `skip_auto_transaction`, you **must** call `transact { }` or `TransactNotCalledError` is raised.

### LMID behavior by phase

| Phase | On Error |
|-------|----------|
| Pre-transaction | LMID advanced in separate transaction |
| Transaction | LMID advanced in separate transaction (original tx rolled back) |
| Post-commit | LMID already committed with transaction |

## References

- [Zero Documentation](https://zero.rocicorp.dev/docs/mutators)
- [Zero Server Implementation](https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/process-mutations.ts)
- [dry-types Documentation](https://dry-rb.org/gems/dry-types/)
