# Vue — advanced patterns

## Fragment-based component composition

Break complex components into internal `/fragments/` subdirectory. Fragments not exported; used only by parent. Reduces re-render scope, keeps logic isolated.

**Pattern**: parent component → child fragments (via slots, not props)

```vue
<!-- src/components/form/form-field/form-field.vue -->
<script setup>
import { useSlots } from "vue";
import { isNonEmptySlot } from "@lewishowles/components";

const slots = useSlots();
const haveError = isNonEmptySlot(slots.error);
const haveHelp = isNonEmptySlot(slots.help);
</script>

<template>
  <div class="form-field">
    <form-label />
    <form-wrapper>
      <slot />
      <form-prefix v-if="havePrefix" />
      <form-suffix v-if="haveSuffix" />
    </form-wrapper>
    <form-error v-if="haveError"><slot name="error" /></form-error>
    <form-help v-if="haveHelp"><slot name="help" /></form-help>
  </div>
</template>
```

**Slot checking**: use `useSlots()` + boolean computed/const to detect available slots.

## Composables as global state

For smaller apps (without Pinia), composables expose module-scope refs persisting across component mounts.

```typescript
// src/composables/use-film-finder.js
import { ref, computed } from "vue";
import { useApi } from "./use-api";

const data = ref(null);
const selectedIds = ref([]);
const { get, isLoading } = useApi();

export function useFilmFinder() {
  async function findFilms(query) {
    data.value = await get(`/api/films?q=${query}`);
    selectedIds.value = [];
  }

  const availableFilms = computed(() =>
    data.value ? data.value.filter((film) => film.available) : [],
  );

  const selectedFilms = computed(() =>
    selectedIds.value.map((id) => data.value.find((film) => film.id === id)),
  );

  return { data, isLoading, findFilms, availableFilms, selectedFilms, selectedIds };
}
```

**Trade-off**: simpler than Pinia for small apps; no devtools or time-travel debugging.

## Complex computed chains (filtering pipelines)

Build filtering/transformation pipelines where each computed depends on the previous.

```typescript
// src/composables/use-film-set-calculator.js
import { computed } from "vue";
import { useFilmFinder } from "./use-film-finder";

export function useFilmSetCalculator() {
  const { selectedFilms } = useFilmFinder();

  const filmScreenings = computed(() =>
    selectedFilms.value.flatMap((film) => film.screenings || []).filter((s) => s.type === "cinema"),
  );

  const validScreenings = computed(() => filmScreenings.value.filter((s) => !isPastScreening(s)));

  const filmSets = computed(() => {
    const combinations = [];
    for (const first of validScreenings.value) {
      for (const second of validScreenings.value) {
        if (first.filmId !== second.filmId && isTimeGapAcceptable(first, second)) {
          combinations.push({ first, second, gap: calculateGap(first, second) });
        }
      }
    }
    return combinations.sort((a, b) => a.gap - b.gap);
  });

  return { validScreenings, filmSets };
}
```

## Reusable template pattern (VueUse)

`createReusableTemplate` from `@vueuse/core` for define-once, render-many patterns.

```vue
<script setup>
import { createReusableTemplate } from "@vueuse/core";
const [DefineTemplate, ReuseTemplate] = createReusableTemplate();
</script>

<template>
  <DefineTemplate v-slot="{ data, action }">
    <div class="notification" :class="`notification--${data.type}`">
      <p>{{ data.message }}</p>
      <button @click="action">{{ data.actionLabel }}</button>
    </div>
  </DefineTemplate>

  <div class="notifications-container">
    <ReuseTemplate :data="successNotification" :action="dismissSuccess" />
    <ReuseTemplate :data="errorNotification" :action="dismissError" />
    <ReuseTemplate :data="warningNotification" :action="dismissWarning" />
  </div>
</template>
```

**Trade-off**: cleaner than three separate components, but less obvious than slot-based composition. Use sparingly.

## Dynamic slot names

Template literals in `#[...]` for computed slot names. Useful for flexible column configs or dynamic field rendering.

```vue
<template>
  <tr v-for="row in rows" :key="row.id">
    <td v-for="col in columns" :key="col.key">
      <slot :name="`column-${col.key}`" :value="row[col.key]">
        {{ row[col.key] }}
      </slot>
    </td>
  </tr>
</template>
```

## Skeleton loaders

Build domain-specific skeleton components composing `loading-skeleton` + `loading-skeleton-indicator` from `@lewishowles/components`. Use `v-show` (not `v-if`) to preserve animation state.

```vue
<!-- user-list-skeleton.vue -->
<script setup>
const skeletonCount = 5;
</script>

<template>
  <div class="space-y-2" data-test="user-list-skeleton">
    <loading-skeleton v-for="i in skeletonCount" :key="i" data-test="user-list-skeleton.item">
      <loading-skeleton-indicator class="mb-2 h-4 w-2/3" />
      <loading-skeleton-indicator class="h-3 w-1/2" />
    </loading-skeleton>
  </div>
</template>
```

```vue
<!-- Usage -->
<user-list-skeleton v-show="isLoading" />
<headline-users v-show="!isLoading" :users="users" />
```

**Key**: `v-show` keeps DOM mounted (preserves animations); `v-if` destroys and recreates (breaks transitions).

## Pinia setup store

```typescript
// src/stores/security.js
import { defineStore } from "pinia";
import { ref, computed } from "vue";

export const useSecurityStore = defineStore("security", () => {
  const status = ref("unknown");
  const lastUpdated = ref(null);
  const isSecure = computed(() => status.value === "secure");

  async function updateStatus() {
    const result = await fetch("/api/security/status");
    const data = await result.json();
    status.value = data.status;
    lastUpdated.value = new Date();
  }

  return { status, isSecure, lastUpdated, updateStatus };
});
```

**vs module-level refs**: Pinia offers devtools, time-travel debugging, type-safe mutations. Use for complex state; module refs for simple shared data.

## keep-alive

Cache component instance when hidden (tabs, routes). Preserves state, skips re-run of `onMounted`.

```vue
<keep-alive>
	<film-list v-if="activeTab === 'films'" />
	<watch-settings v-else-if="activeTab === 'settings'" />
</keep-alive>
```

**With include/exclude**:

```vue
<keep-alive :include="['film-list', 'watch-settings']" :exclude="['search-form']">
	<component :is="currentComponent" />
</keep-alive>
```

## Suspense

Boundary for async setup or data loading. Shows fallback while child loads. Works well with skeleton loaders in `#fallback`.

```vue
<Suspense>
	<template #default>
		<film-details :id="filmId" />
	</template>
	<template #fallback>
		<loading-skeleton />
	</template>
</Suspense>
```

In child (`film-details.vue`): `await` directly in `<script setup>` — Suspense catches it.

## Teleport

Render component to a different DOM location. Useful for modals, tooltips, popovers.

```vue
<teleport to="#modal-portal">
	<base-modal v-if="showModal" @close="showModal = false">
		<p>This is rendered in the portal.</p>
	</base-modal>
</teleport>
```

**Accessibility**: use `role="dialog"` + `aria-modal="true"` on teleported modal; mark main app `aria-hidden="true"` while modal is open.

## v-memo

Skip re-render if dependency array unchanged. Use only when re-render is known expensive (complex template, large list).

```vue
<div v-memo="[filtered]">
	<expensive-list-item v-for="item in filtered" :key="item.id" :item="item" />
</div>
```

**Caveat**: premature optimisation. Use only if profiler shows re-render is a bottleneck.

## watch and watchEffect

`computed` is preferred for derived state. Use `watch`/`watchEffect` for side effects only.

**Always comment why the watch is needed.**

```typescript
// Fetch film details whenever the user selects a different film.
watch(
  () => filmId.value,
  async (newId) => {
    if (newId) filmData.value = await fetch(`/api/films/${newId}`).then((r) => r.json());
  },
);
```

`watchEffect` auto-tracks dependencies; `watch` uses explicit dependencies.

Use `watch`/`watchEffect` only for:

- Side effects (API calls, analytics, DOM manipulation)
- Reactions that don't produce a value (logging, validation)
- Conditional reactions

**Common mistake**: using `watch` to compute derived state. Use `computed` instead.
