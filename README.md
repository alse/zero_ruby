# zero_ruby

A Ruby gem for handling [Zero](https://zero.rocicorp.dev/) mutations with type safety, validation, and full protocol support.

0.1.0.alpha1

## Features

- **Type coercion & checking** - String, Integer, Float, Boolean, ID, BigInt, ISO8601Date, ISO8601DateTime with automatic conversion and runtime type validation
- **Type generation** - Generates typescript types you can use for your frontend mutators
- **Argument validation** - length, numericality, format, inclusion, exclusion, etc.
- **LMID tracking** - Duplicate and out-of-order mutation detection using Zero's `zero_0.clients` table
- **Push protocol** - Version validation, transaction wrapping, retry logic

## Installation

Add to your Gemfile:

```ruby
gem 'zero_ruby'
```

## Usage

### 1. Base classes (optional)

Create base classes to share behavior across mutations and input types:

```ruby
# app/zero/types/base_input_object.rb
module Types
  class BaseInputObject < ZeroRuby::InputObject
    # Add shared behavior across all input objects here
  end
end

# app/zero/mutations/application_mutation.rb
class ApplicationMutation < ZeroRuby::Mutation
  def current_user
    ctx[:current_user]
  end
end
```

### 2. Define custom input types (optional)

```ruby
# app/zero/types/post_input.rb
module Types
  class PostInput < Types::BaseInputObject
    argument :title, String, required: true,
      validates: { length: { minimum: 1, maximum: 200 } }
    argument :body, String, required: false
    argument :published, Boolean, required: false, default: false
  end
end
```

### 3. Define mutations

```ruby
# app/zero/mutations/post_update.rb
module Mutations
  class PostUpdate < ApplicationMutation
    argument :id, ID, required: true
    argument :post_input, Types::PostInput, required: true

    def execute(id:, post_input:)
      post = current_user.posts.find(id)
      post.update!(**post_input)
    end
  end
end
```

### 4. Register mutations in schema

```ruby
# app/zero/app_schema.rb
# The mutation names should match the names used in your Zero client:
#   mutators.posts.update({ id: "...", post_input: { title: "..." } })
#   -> maps to "posts.update"
class ZeroSchema < ZeroRuby::Schema
  mutation "posts.update", handler: Mutations::PostUpdate
end
```

### 5. Add controller

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
      error: {
        kind: "PushFailed",
        reason: "Parse",
        message: "Invalid JSON: #{e.message}"
      }
    }, status: :bad_request
  end
end
```

### 6. Add route

```ruby
# config/routes.rb
match '/zero/push', to: 'zero#push', via: [:get, :post]
```

## Configuration

Create an initializer to customize settings (all options have sensible defaults):

```ruby
# config/initializers/zero_ruby.rb
ZeroRuby.configure do |config|
  # Storage backend (:active_record is the only built-in option)
  config.lmid_store = :active_record

  # Retry attempts for transient errors
  config.max_retry_attempts = 3

  # Push protocol version (reject requests with different version)
  config.supported_push_version = 1
end
```

## TypeScript Type Generation

ZeroRuby generates TypeScript type definitions from your Ruby mutations. GET requests to `/zero/push` return the types.

### Setup

- Set `ZERO_TYPES_URL` env var to your host /zero/push
- `npm install ts-to-zod --save-dev`
- Add the following script to generate types and zod schemas

```json
{
  "scripts": {
    "zero:types": "mkdir -p lib/zero/__generated__ && curl -s $ZERO_TYPES_URL/zero/push > lib/zero/__generated__/zero-types.ts && npx ts-to-zod lib/zero/__generated__/zero-types.ts lib/zero/__generated__/zero-schemas.ts"
  }
}
```

### Using with Zero Mutators

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
        ...(args.postInput.title !== undefined && { title: args.postInput.title }),
        updatedAt: Date.now(),
      })
    }),
  },
})

export type Mutators = typeof mutators
```

## Response format

Success:
```json
{ "mutations": [{ "id": { "id": 1, "clientID": "abc" }, "result": {} }] }
```

Already processed (batch continues):
```json
{ "mutations": [{ "id": { "id": 1, "clientID": "abc" }, "result": { "error": "alreadyProcessed" } }] }
```

Out of order (batch halts):
```json
{ "mutations": [{ "id": { "id": 5, "clientID": "abc" }, "result": { "error": "ooo", "message": "..." } }] }
```

Unsupported push version:
```json
{ "error": { "kind": "PushFailed", "reason": "UnsupportedPushVersion" } }
```

## Validation

Built-in validators:

```ruby
argument :name, String, required: true,
  validates: {
    length: { minimum: 1, maximum: 100 },
    format: { with: /\A[a-z]+\z/i, message: "only letters allowed" },
    allow_blank: false
  }

argument :age, Integer, required: true,
  validates: {
    numericality: { greater_than: 0, less_than: 150 }
  }

argument :status, String, required: true,
  validates: {
    inclusion: { in: %w[draft published archived] }
  }

argument :username, String, required: true,
  validates: {
    exclusion: { in: %w[admin root system], message: "is reserved" }
  }

argument :email, String, required: true,
  validates: {
    allow_null: false,
    allow_blank: false
  }
```

## Type coercion & checking

Types automatically coerce compatible values and raise `CoercionError` for invalid input:

| Type | Accepts | Rejects |
|------|---------|---------|
| `String` | Any value (via `.to_s`) | - |
| `Integer` | `42`, `"42"`, `3.7` → `3` | `"abc"`, `""`, arrays, hashes |
| `Float` | `3.14`, `"3.14"`, `42` → `42.0` | `"abc"`, `""`, arrays, hashes |
| `Boolean` | `true`, `false`, `"true"`, `"false"`, `0`, `1` | `"yes"`, `"maybe"`, other values |
| `ID` | `"abc"`, `123` → `"123"`, `:sym` → `"sym"` | `""`, arrays, hashes |
| `BigInt` | `123`, `"9007199254740993"` | `"abc"`, `""`, floats |
| `ISO8601Date` | `"2025-01-15"`, `Date`, `Time` → `Date` | `"invalid"`, `""`, integers |
| `ISO8601DateTime` | `"2025-01-15T10:30:00Z"`, `Time`, `DateTime` | `"invalid"`, `""`, integers |

## Testing

For tests, pass a mock LMID store to avoid database dependencies:

```ruby
class MockLmidStore < ZeroRuby::LmidStore
  def initialize
    @data = {}
  end

  def fetch_with_lock(client_group_id, client_id)
    @data["#{client_group_id}:#{client_id}"]
  end

  def update(client_group_id, client_id, mutation_id)
    @data["#{client_group_id}:#{client_id}"] = mutation_id
  end

  def transaction(&block)
    yield
  end
end

# In tests
result = ZeroSchema.execute(push_data, context: ctx, lmid_store: MockLmidStore.new)
```

## References

- [Zero Documentation](https://zero.rocicorp.dev/docs/mutators)
- [Zero Server Implementation](https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/process-mutations.ts)

## Acknowledgements

Inspired by [graphql-ruby](https://github.com/rmosolgo/graphql-ruby).
