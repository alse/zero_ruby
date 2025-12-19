# ZeroRuby - Agent Instructions

A Ruby gem for handling [Zero](https://zero.rocicorp.dev/) mutations with type safety, validation, and full protocol support.

Example implementation https://github.com/rocicorp/mono/blob/main/packages/zero-server/src/process-mutations.ts

## Project Structure

```
lib/zero_ruby/
├── schema.rb              # Schema DSL for registering mutations
├── mutation.rb            # Base mutation class
├── input_object.rb        # Input type definitions
├── context.rb             # Request context handling
├── typescript_generator.rb # TypeScript type generation
├── errors.rb              # Error classes
├── types/                 # Scalar types (String, Integer, Float, Boolean)
├── validators/            # Validation rules (length, format, inclusion, etc.)
└── lmid_stores/           # LMID tracking backends (ActiveRecord, Memory)
```

## Key Concepts

- **Schema**: Registers mutation handlers, e.g., `mutation "posts.create", handler: PostCreate`
- **Mutation**: Defines arguments and an `execute` method
- **InputObject**: Nested argument types with validation
- **LMID Tracking**: Deduplication using Zero's `zero_0.clients` table
