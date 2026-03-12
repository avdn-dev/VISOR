# What's New

## Access modifier propagation for macros

Macros now propagate the access level of the target type to generated members that require it. Previously, applying `@ViewModel` to a `public class` or `@LazyViewModel` to a `public struct` would generate `internal` members, causing compilation errors in consumer targets.

**Affected members:**

| Macro | Member | Now matches target access |
|-------|--------|--------------------------|
| `@ViewModel` | `init(...)` | Yes |
| `@LazyViewModel` | `var body` | Yes |

Internal implementation details (`observe*()`, `startObserving()`, `viewModel` computed properties) remain `internal` — they are not part of the public API surface.

No changes needed for internal types — the default access level produces the same output as before.
