# Unit testing

## General

- Over-test: happy/unhappy paths, valid/invalid variants
- Meaningful assertions over snapshots for volatile content
- For JSON/serialised output, assert decoded structure or user-visible behaviour unless key order is a deliberate contract. Do not test standard encoder key order.
- Separate test setup from assertions like separating variables from logic in JS — use a blank line between the action and any `expect()` calls
- Keep imports at the top.
- Test and group names are capitalised, human-readable, and self-contained; method/computed names may stay exact. Name the behaviour in plain active voice ("shows an error when the field is empty"), not a passive or clever restatement of the mechanism.
- Group tests by collection: "Initialisation", "Computed", "Methods".
- Keep interaction, layout-sensitive state, browser APIs, focus movement, keyboard, live-region timing, and render-contract assertions (whether a component renders in a given visual/DOM state) in component tests. Vitest can inspect props directly, but that doesn't verify what actually rendered. Do not add a "Render contracts" group to unit tests.
- Use diagnostics script: `.agent/scripts/project-diagnostics.py --list` to discover checks, `--check <name>` for the relevant one. For fixes, narrow with `--test-file <path>` or `--test-glob '<pattern>'`. Ask the user for full suites or `--all`.

### Choosing what to mock

Mock external systems such as network clients, SDKs, clocks, and storage. Mock an owned composable or adapter when it is an established seam that exists so tests can replace it. Keep owned helpers and child components real when they are part of the behaviour under test, rather than mocking them only to make the unit smaller. Assert what the unit does from the outside, such as return values, emitted events, and state changes.

## Vue & Vitest

- Vitest; unit-test computed properties and heavily-used methods
- Skip tests for methods delegating to `@lewishowles/helpers`
- Component logic in unit tests: computed properties, emitted events, composables, heavily-used methods
- Composables: test reactive state, side effects, lifecycle hooks
- For async updates, import `nextTick` from Vue and use `await nextTick()` instead of `await wrapper.vm.$nextTick()`
- Use `flushPromises()` when waiting for pending promises, API mocks, or async component setup
- Use `vi` for spies, fake timers, and module mocks; restore mocks after each test when state can leak
- Use `expectTypeOf` or `assertType` for type-level assertions when runtime assertions cannot cover the contract
- Test component behaviour as black box. Avoid internal refs, private methods, or implementation structure
- Avoid snapshot-only tests. A snapshot may support a focused assertion, but should not be the only proof
- Wrap async setup components in `Suspense` in tests
- Configure Pinia explicitly in tests. Use `@pinia/testing` when component tests need stores without real action side effects
- Test lifecycle-dependent composables through a small helper component when they rely on mount/unmount hooks

### Vitest API and composable mocks

Use this when mocking API composables, SDK clients, or query-layer dependencies.

- Inspect existing local mock helpers before adding new mocks; prefer extending the project pattern over introducing a package abstraction
- Keep literal `vi.mock(...)` calls in the test file or a project-local test helper. Do not hide `vi.mock(...)` inside an imported package helper; Vitest needs to see literal mock calls for hoisting
- Define mock handlers referenced by `vi.mock(...)` with `vi.hoisted(() => vi.fn())`
- For composables, use project-local adapters that match the local module shape:

```js
const mockGet = vi.hoisted(() => vi.fn());
const mockPost = vi.hoisted(() => vi.fn());

vi.mock("@/composables/api/use-api", () => ({
	default: () => ({
		get: mockGet,
		post: mockPost,
	}),
}));
```

- For SDK clients, keep the SDK-specific class or object shape in the local test/helper:

```js
const mockGet = vi.hoisted(() => vi.fn());

vi.mock("@vendor/sdk", () => ({
	Client: class {
		get = mockGet;
	},
}));
```

- Clear or restore mocks in lifecycle hooks when handler state can leak between tests
- Only promote a shared package helper when it doesn't need to know the mocked module path, export shape, SDK class, or composable return shape.

For component, composable, helper, and `test.for` examples, see [references/examples.md](references/examples.md).

### Component logic test structure

- Top-level group names use `kebab-case` to match the component (`form-input`, not `FormInput`)
- Only test component logic that cannot reasonably move to composable/helper
- Do not assert DOM attributes, slot fallbacks, prop-driven element presence, keyboard behaviour, focus movement, browser layout, CSS rendering, or timed live-region behaviour. Even cheap, static render contracts belong in Playwright component tests (`*.ct.js`)

### File co-location

Place `.test.js` next to component, composable, or utility. Vitest discovers automatically.
