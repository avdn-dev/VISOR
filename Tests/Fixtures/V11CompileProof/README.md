# VISOR 11 Swift 6.2 gateway and source proof

This isolated package contains the passing Stage B generated-State-gateway,
Stage C channel-backed, group-locked control-plane and hand-written
heterogeneous-session, Stage D generated-recipe/source-fenced-testing and
Stage E generated production-owner, Stage F journal-resource and Stage G
Observation-parity/hardening plus Stage H safety-deadline/eventual-join slices
for VISOR 11. Stage H passes in debug and release configurations. This is not
the complete v11 implementation proof. It contains both nonisolated and
MainActor-by-default consumer targets. The neighbouring
`V11ExternalCompileProof` package separately verifies the ordinary public
cross-package boundary.

The real root package now separately integrates `VISORObservation`, the bounded
Stage B gateway, the hand-written recipe/session/deadline runtime, the v11
`@ViewModel` recipe cascade, `VISORTesting` and the structured SwiftUI
production owner. Its production `VISOR` target does not use
`.defaultIsolation(MainActor.self)`. The root target, focused
macro, owner and observation tests, and both downstream consumer isolation
modes pass in debug and release. The unchanged
`@LazyViewModel(VM.self, observationPolicy:)` expansion calls one opaque,
readiness-gated structured owner. Root mounted tests exercise that path and a
deterministically injected `.pauseWhenInactive` scene lifecycle.
`V11RootGatewayExternalProof` exercises the public root source, generated-code
visitor and State gateway boundaries plus the unchanged LazyViewModel spelling
under both consumer isolation defaults. Its models omit manual deinitialisers,
so Swift 6.2.4 release compilation exercises the macro-synthesised empty
deinitialisers for both the source-backed outer type and State. Root macro
snapshots separately prove that an unconditional user deinitialiser is
preserved and a conditional deinitialiser fails closed.
`V11RootTestingExternalProof` exercises the real generated source-backed testing
path in debug and release under both consumer isolation defaults. This fixture
remains the broader evidence for the complete Stage F/G prototype matrices;
those cases are not all claimed as ported into the root test targets.

The consumer source intentionally declares only the outer ViewModel as
`@MainActor @Observable @ViewModel`. Its nested `State` is a plain class. The
`@ViewModel` macro attaches MainActor isolation and a hidden State macro, which
becomes the sole owner of State's Observation registrar and field accessors.
Stacking VISOR accessors on a nested `@Observable` type is deliberately rejected
because the composition exercised by this Swift 6.2 proof either conflicted or
left one accessor owner ineffective.

The fixture proves, for the exercised ordinary stored fields:

- the macro cascade generates Observation conformance, typed selectors,
  untracked baseline readers and the dormant recorder attachment point;
- one State-private descriptor per field lets public, package, internal,
  fileprivate and private stored fields compile without widening access;
  public through fileprivate fields receive routed selectors, while private
  fields remain exhaustively accessor-instrumented without an unusable nested
  carrier member;
- an isolated compile-fail matrix rejects imported internal and fileprivate
  selectors, private-field and computed-property selectors, nested selector
  composition and a projecting history overload;
- direct State assignments, `updateState`, `state[\.field]`,
  `$state[\.field]` and `Bindable(state)[\.field]` converge on one generated
  accessor; representative routed, direct and write-back mutations prove one
  raw commit;
- the nil-recorder path branches before journal snapshots or boxing;
- inferred, explicitly typed, optional, collection, non-Equatable and direct
  reference fields compile under both consumer default-isolation policies;
- a stored field with no declaration default is assigned by a custom public
  `State.init` and executed from ordinary non-`@testable` consumer tests under
  both isolation policies;
- `let`, static/class, get-only computed and ordinary `@ObservationIgnored`
  declarations are deliberately left untouched; an `@ObservationIgnored`
  instance stored var cannot also be `nonisolated` or
  `nonisolated(unsafe)`, while those modifiers do not change the intentional
  ignored policy for let, static/class or get-only declarations;
- writable computed storage, property observers, unknown attributes/wrappers,
  `lazy`, `weak`,
  `unowned`, `nonisolated`, `nonisolated(unsafe)`, multiple bindings and
  destructuring patterns receive precise diagnostics;
- one rejected declaration suppresses all generated State accessors,
  descriptors and conformance plus ViewModel ownership and conformance, so the
  macro cannot leave a partially instrumented model;
- equal writes remain raw commits while exact matching normalises them;
- value-member mutation writes back once, including during throwing unwind;
- a throwing mutation with no resulting change remains an equal raw commit;
- reference replacement is recorded, reference-interior mutation is not, and
  both strict matchers reject concrete and dynamically erased outer-reference
  history before evaluating equality or a predicate;
- baselines are captured atomically from untracked backing storage and remain
  stable across later out-of-window writes;
- re-entrant Observation-driven writes are journalled in successful-completion
  order; and
- the top-down `observe` / `perform` / `expect` spelling, action results,
  replayable exact matching, baseline-inclusive predicates and caller source
  locations compile and execute through Swift Testing; and
- macro diagnostics identify missing outer MainActor, explicit nested
  Observable and the complete accepted unsupported-storage matrix, while the
  MainActor and public-setter Fix-Its are applied and snapshot-tested.

The Stage C slice additionally proves:

- synchronous actor-owned publication through an isolation-neutral channel;
- gap-free open under publication races and stable copied-source identity;
- per-subscription checkpoint, pause, handler acknowledgement and resume;
- latest-snapshot retention while paused and acknowledgement of filtered
  revisions;
- independent subscribers, including a slow handler that does not block
  producer publication or another subscription;
- source termination waking iterators and acknowledgement waiters;
- cancellation cleanup for idle iteration, baseline activation and paused
  checkpoint draining;
- rollback of abandoned or partially failed multi-source preparation and
  protocol-violation errors for duplicate prepare/activation;
- distinct channels joined through `ObservationChannel(_:groupedWith:)` sharing
  one producer group while retaining distinct source identities, without a
  third public group type;
- group-locked preparation/opening and checkpoint/pause atomic relative to
  individual channel operations, including an explicit proof that a group cut
  can fall between sequential publications and therefore is not a batch;
- true concurrent publication preserving every monotonic channel revision,
  including sustained contention across a chained three-channel producer group;
- grouped preparation and checkpoint/pause remaining lock-linearised against
  sequential publications, while cancellation racing acknowledgement-waiter
  registration leaves the subscription reusable;
- publication, rejection after termination, cancellation and termination
  retiring the exercised incoming, replaced or removed user snapshots only
  after leaving source/group critical sections, so snapshot deinitialisation
  may synchronously re-enter channel publication without recursively acquiring
  those locks;
- fail-closed grouped checkpoint rejection: if a later group fails after an
  earlier group was captured, every supplied subscription is cancelled rather
  than leaving a live or stranded paused participant;
- preparation of every independent source and producer group, followed by
  capture and pause of every startup target, before deterministic baseline
  handlers run;
- application of every baseline projection before any initial reaction, with
  workers starting only after all initial work;
- a finite startup frontier: a source publication caused after startup targets
  were captured stays outside readiness and is left for subsequent delivery or
  fencing rather than recursively chased to a quiet fixed point;
- whole-session fences that pause every source and group before draining any
  lane, followed by a synchronous scoped operation that resumes on success,
  tears down the session if it throws and is skipped when cancellation wins at
  the operation boundary;
- a stored supervised startup task with cancellation checks after every
  projection and reaction; stopping at a gated handler waits for it to return,
  skips later startup work and joins the startup task, while cancellation at
  the final readiness hand-off tears down already-started workers; the outer
  start path rechecks failure and lifecycle after the startup task returns, so
  a worker terminating in that hand-off cannot expose false readiness;
- handler-context re-entrancy: same-session stop is request-only, pause and
  failure waiting are rejected before they can mutate lifecycle or suspend, the
  before-ready seam follows the same rule, standalone lanes reject
  self-checkpoint and avoid
  self-join, an initial reaction may request stop during startup, stale
  unstructured descendants regain normal joining after handler return and a
  handler still awaits teardown of a different session;
- package-only hand-written session and lane control types, keeping ordinary and
  downstream consumers from capturing lifecycle capability inside application
  handlers; TaskLocal tracking is defence-in-depth for inherited internal tasks,
  not a universal ancestry mechanism;
- a concurrent normal stop during pause draining is reported as cancellation,
  not latched as an observation infrastructure failure;
- startup-failure rollback of every heterogeneous subscription, plus whole-
  session cancel-all-then-join teardown and first-worker-failure supervision;
- exactly one strongly retaining teardown supervisor that owns cleanup through
  the final join and then releases itself;
- cancellable failure waiting that does not outlive or stop the session; and
- manually driven action-fence placement through a hand-written
  `_ObservationLane`.

The Stage D slice additionally proves, for the exercised generated
channel-backed declarations:

- a public underscored `_ObservationRecipeVisitor` that downstream-generated
  code may populate only when VISOR supplies it, because visitor construction,
  recipe storage/enumeration and the raw session control plane remain
  package-only;
- generation from two heterogeneous sources, with runtime source identity
  merging two syntactically different key paths that resolve to the same
  source into one subscription;
- all generated baseline projections completing before any initial Reaction,
  an async Reaction being awaited before its revision is acknowledged and
  readiness opening only after the complete initial reconciliation;
- `observe` installing its recorder through an opening whole-session pause
  before entering the body, and `perform` closing through the corresponding
  pause fence before returning;
- deterministic exclusion of source revisions later than the closing targets:
  the later snapshots are reconciled after resume but do not enter the closed
  journal window;
- an ordinary throwing action retaining its exact error and matchable completed
  commits; if a closing failure occurs as well, the action error remains exact,
  the infrastructure issue is separate and the window is invalidated;
- startup and running source failures being reported once, with running failure
  poisoning the scope, invalidating an open window and suppressing later VISOR
  operations;
- cancellation abandoning the open window without unmet-history issues and
  joining source-session work;
- synchronous rejection of an overlapping `perform` before its operation runs,
  without corrupting the active truthful window;
- an escaped observation handle releasing the SUT/session capture graph at
  scope end and diagnosing stale use without reactivating released storage;
- malformed Bound and Reaction placement/declaration diagnostics; and
- the same generated source-fenced path in debug and release builds under both
  nonisolated and MainActor-by-default consumer settings.

The Stage E slice additionally proves:

- a downstream `@LazyViewModel` expansion that names only one public
  underscored View-producing bridge; its concrete SwiftUI host, owner, recipes,
  session and lifecycle controls remain package-owned;
- one host-lifetime root task per ViewModel identity, readiness-before-content,
  immediate fail-closed revocation and joined teardown;
- all three `ObservationPolicy` mappings, a fresh fully reconciled generation
  after scene-policy restart and coalescing of rapid policy requests without
  overlapping source subscriptions;
- active duplicate-owner rejection, plus cancellation-safe waiting when a
  replacement host arrives while its predecessor is already releasing and
  joining;
- cancellation covering the entire asynchronous lease claim, including an
  A-to-B-to-C hand-off where B is cancelled immediately after acquisition and C
  waits for B's explicit post-join relinquishment;
- explicit lease release only after joined teardown, while the retired owner
  remains strongly alive, and ViewModel-identity-keyed opaque host replacement;
- a mounted macOS `NSHostingView` withholding content until readiness, showing it
  after readiness, observing disappearance after root replacement and using the
  identity lease as a deterministic post-join barrier before proving both source
  subscription counts are zero;
- infrastructure failure reporting after joined teardown with retry suppressed
  until a genuine disabled-to-enabled lifecycle edge; and
- the owner request and identity-lease locks containing only synchronous
  bookkeeping, resuming continuations after unlocking and requiring no
  unchecked sendability.

The Stage F slice additionally proves:

- an internal finite logical raw-commit guard whose exact boundary remains a
  complete matchable window and whose next commit invalidates the whole window;
- equal and cross-field commits each counting once in global completion order;
- overflow detected only after the State mutation and storage update have
  committed,
  immediately clearing every retained typed prefix value, poisoning the scope,
  synchronously requesting session teardown and joining it when `perform`
  returns;
- exactly one first-cause infrastructure report, including a source failure
  already latched before the journal guard is crossed;
- no matching against a retained prefix and suppression of every later VISOR
  expectation or operation;
- preservation of exact throwing action errors and already-produced action
  results while the infrastructure failure remains separately reported;
- release of a previous completed window at the next `perform` and release of
  the complete typed capture graph when `observe` ends;
- a 4,352-commit mixed scalar, growing-collection and repeated copy-on-write
  stress window below the internal default guard; this is a logical entry
  bound, not a byte, transitive-retention or OOM guarantee;
- 10,000 ordinary mutations on the nil-recorder production path completing
  without activating or being limited by the test journal;
- one fixed-size outside-window metadata ring per recorder, preserving retained
  global field order, action relation and cumulative omission count while
  safely overwriting its oldest entry;
- startup writes classified before action one, post-action tails reclassified
  between consecutive actions, and a previous typed-window deinitialiser's
  synchronous routed write classified before the next baseline;
- no arbitrary typed value or reference payload persistently retained by the
  ring, with context formatted only for a requested diagnostic; the shared
  recorder hook still receives and type-erases old and resulting values
  transiently, so this is not a zero-boxing claim;
- outside metadata never entering or changing the matchable active journal,
  including after active-window invalidation; and
- independent recorder rings plus complete ring and omission-context release at
  observe teardown.

The Stage G slice additionally proves:

- generated setter notifications match a neighbouring `@Observable` oracle for
  changed and equal Equatable values, same-content non-Equatable values,
  identity-compared non-Equatable references, equality-compared Equatable
  references and both optional-reference forms, including same-instance,
  nil-transition, distinct-equal and unequal optional assignments;
- generated `_modify` notifications match the oracle for changed, no-op,
  throwing-changed and throwing-unchanged completion, including unwind;
- an error thrown while evaluating a setter's right-hand side enters neither
  the oracle nor generated setter, produces no notification and produces no
  raw commit;
- guarded same-field re-entrant Observation callbacks see the pre-mutation
  value under both implementations, while generated raw commits complete
  nested-first and outer-last;
- raw journalling remains intentionally independent of notification
  suppression: every completed setter or `_modify` access contributes one raw
  commit, equal/no-op commits normalise out of exact matching and a pre-setter
  throw contributes none;
- one shared strict-history gate checks the erased baseline and every erased
  resulting commit before either matcher runs, rejecting concrete classes,
  `AnyObject`, class-bound existentials and `Any` holding a class without
  evaluating user predicates, with a diagnostic that describes the rejected
  outer reference value rather than only the field's static type; and
- optional and container values that transitively hold references remain
  admitted only under the documented caller precondition that retained history
  stays stable; Swift cannot prove or diagnose that transitive property.

The Stage H slice additionally proves:

- phase-specific safety deadlines for VISOR-owned readiness, opening and
  closing fences, ordinary observation fences and teardown joins, with user
  actions and closed expectations deliberately outside the watchdog boundary;
- a private production `ContinuousClock` whose absolute monotonic deadline is
  captured synchronously before control-plane preparation, plus a package-only
  deterministic watchdog-factory seam; expiry wins off MainActor even while
  synchronous MainActor work delays failure delivery. If expiry has won at the
  pre-cut linearisation check, the source checkpoint is skipped; if the check
  wins first, the cut may complete and later expiry still fails closed;
- fail-closed readiness revocation, cancellation and one teardown supervisor,
  while an uncooperative handler can keep the generation joining after the
  bounded caller returns without making the session stopped prematurely or
  permitting replacement;
- first-cause ordering across operation failure, watchdog expiry, re-entrant
  failure callbacks and caller cancellation, including fail-closed handling of
  an unexpected `CancellationError` from an uncancelled sleeper;
- bounded deadline diagnostics containing the exact phase, an eight-source
  prefix and an omitted-source count;
- one callback-backed teardown coordinator and one watchdog shared by
  concurrent waiters, with cancellation eligibility and outcome publication
  linearised under one non-suspending lock and no retained waiter task per
  timed-out stop;
- production identity leases remaining in release until the true join, plus a
  queued false-to-true scene activation starting a replacement generation only
  after that join; and
- testing scopes retaining a dormant, write-discarding State reservation after
  bounded return until the old handler truly joins, so a stale write cannot
  enter a newer journal, while action results, typed action errors, body errors
  and their phase-specific perform/observe source attribution retain their
  accepted precedence.

Stage D proves the four accepted v11.0 source declaration spellings:
`@Bound(source:)`, `@Bound(source:selecting:)`, `@Reaction(source:)` and
`@Reaction(source:selecting:)`. Source-backed Polled, debounce and throttle
markers are not part of v11.0. Cooperative polling is producer-owned
`ObservationSource` behaviour consumed through Bound or Reaction; other delayed
work has explicit injected-clock structured ownership and is not auto-flushed
by a source fence. The legacy positional marker forms were removed in the v11
cutover.

Stages C and D prove channel-backed raw and grouped source control planes, the
hand-written heterogeneous session and its exercised generated-recipe testing
integration. Stage H additionally proves a deterministic false-to-true owner
policy request during bounded teardown and restart only after true join. The
fixture does **not** itself prove arbitrary custom/composite source
construction, the root package's real production SwiftUI owner or
environment-to-policy wiring or the Align background-presentation migration.
Its fixture-local `VISORTestDoubles`
target remains the historical marker used by the prototype dependency graph;
the root's real independent product is proved separately. The real root owner
is instead exercised by mounted source-backed root tests; root
ViewModel/testing integration is proved separately against the real products.
A separate mounted root macOS proof injects
active → background → active → inactive → active for `.pauseWhenInactive` and
proves disabled publication suppression, readiness/latest reconciliation,
exact zero/one source-subscription counts and joined lease teardown. That
controlled proof does not cover arbitrary scene scheduling, other platforms or
Align presentation and renderer work.
The active-window complete-or-fail guard and outside-window diagnostic ring are
covered by Stage F above; the ring never participates in matching.
Grouping does not make sequential `publish` calls
an atomic batch. Published snapshots must retain stable contents after
publication. Swift cannot prove transitive value semantics, so this remains a
producer precondition rather than a claimed deep-copy, alias-detection or
alias-rejection guarantee.

The lock and re-entrancy tests establish the exercised linearisation,
retirement and progress paths. They are not a throughput bound, fairness
guarantee, proof for arbitrary custom synchronisation or an atomic
multi-channel publish. `Task.detached` deliberately does not inherit task-local
handler context. The Stage E owner retains its root lexically and does not expose
raw session or lane lifecycle controls to handlers. The root source-backed
ViewModel/testing integration and integrated structured production owner
preserve the raw-control boundary.

The root `VISORObservation` product, target, source and focused source/channel
tests, State gateway, hand-written recipe/session/deadline runtime, v11
`@ViewModel` cascade, `VISORTesting` product and structured
production owner are integrated separately. The deterministic mounted root
scene lifecycle is also integrated. The independent root `VISORTestDoubles`
product passes three focused tests in debug and release; its genuine downstream
fixture passes two tests in both configurations with package access disabled
and production code importing only that product. The ordinary
declaration matrix and positive selector/accessor visibility matrix are covered;
the negative selector matrix also proves
visibility, flatness and the absence of a projecting history overload. The
neighbouring external package verifies that descriptor metadata, visitor
construction and raw observation lifecycle controls cannot cross the package
boundary.

Run it with:

```sh
swift test --package-path Tests/Fixtures/V11CompileProof
```
