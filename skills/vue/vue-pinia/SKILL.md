---
name: vue-pinia
description: >
  Use this skill when working with Pinia client-side stores in Vue projects. Covers setup stores, state/getter/action usage, storeToRefs, SSR-safe access, HMR, testing with @pinia/testing, and the boundary between Pinia, Pinia Colada, and VueUse.
---
# Pinia

Pinia is for app state: UI state, preferences, cross-page flags, and client-owned data. Use Pinia Colada for server state.

## Store shape

- Prefer setup stores for composables, watchers, complex logic
- Keep option stores where the project already uses them consistently
- Use one store per domain, not one store per component
- Keep derived state in getters/computed, not duplicated
- Use named actions; safe to destructure

```typescript
import { computed, ref } from "vue";
import { defineStore } from "pinia";

export const usePreferencesStore = defineStore("preferences", () => {
	// The currently selected colour mode.
	const colourMode = ref("system");

	// Whether the current interface should render in dark mode.
	const isDark = computed(() => colourMode.value === "dark");

	function setColourMode(value) {
		colourMode.value = value;
	}

	return { colourMode, isDark, setColourMode };
});
```

## Usage in components

- Use `storeToRefs()` when destructuring state or getters
- Destructure actions directly from the store
- Avoid direct state mutations when an action would clarify intent

```typescript
import { storeToRefs } from "pinia";
import { usePreferencesStore } from "@/stores/preferences";

const preferencesStore = usePreferencesStore();
const { colourMode, isDark } = storeToRefs(preferencesStore);
const { setColourMode } = preferencesStore;
```

## VueUse in stores

- VueUse composables fit setup stores when they model client state directly: storage, breakpoints, online state, dark mode, media queries
- Guard browser-only behaviour in SSR contexts
- Prefer VueUse storage composables over hand-written `localStorage` watchers

## SSR and lifecycle

- Call useStore() within setup, actions, or middleware (where context is active)
- Avoid module-scope `useStore()` in files that can run before Pinia is installed
- Clean up watchers or subscriptions created outside component scope

## HMR

Add HMR handling when editing stores in Vite projects:

```typescript
if (import.meta.hot) {
	import.meta.hot.accept(acceptHMRUpdate(usePreferencesStore, import.meta.hot));
}
```

## Testing

- Configure a fresh Pinia instance for each test
- Use @pinia/testing when mocking store behaviour in component tests
- Test store actions and derived state directly when they contain logic
- Keep server cache behaviour in Pinia Colada tests, not Pinia tests

## Completion

For stores that affect UI state or interaction, run [the accessibility checklist](../../accessibility/accessibility/references/checklist.md) before handoff.
