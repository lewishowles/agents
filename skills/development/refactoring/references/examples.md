# Refactoring — worked examples

## Vue: extract composable

Before — logic inline in component:

```vue
<script setup>
import { ref, computed } from "vue";

const items = ref([]);
const search = ref("");

const filtered = computed(() =>
  items.value.filter((i) => i.name.toLowerCase().includes(search.value.toLowerCase())),
);

async function load() {
  items.value = await fetch("/api/items").then((r) => r.json());
}
</script>
```

After — extracted to `use-items.js`:

```javascript
// src/composables/use-items.js
import { ref, computed } from "vue";

export function useItems() {
  const items = ref([]);
  const search = ref("");

  const filtered = computed(() =>
    items.value.filter((i) => i.name.toLowerCase().includes(search.value.toLowerCase())),
  );

  async function load() {
    items.value = await fetch("/api/items").then((r) => r.json());
  }

  return { items, search, filtered, load };
}
```

```vue
<script setup>
import { useItems } from "@/composables/use-items";

const { search, filtered, load } = useItems();
</script>
```

**Steps taken:** rename nothing → extract function body → update component import → run tests.

---

## Vue: simplify conditional rendering

Before — nested `v-if` chains:

```vue
<template>
  <div v-if="user && user.role && user.role === 'admin'">
    <span v-if="!isLoading">Admin panel</span>
    <span v-if="isLoading">Loading…</span>
  </div>
</template>
```

After — computed boolean, `v-show` for toggle:

```vue
<script setup>
const isAdmin = computed(() => user.value?.role === "admin");
</script>

<template>
  <div v-if="isAdmin">
    <span v-show="!isLoading">Admin panel</span>
    <span v-show="isLoading">Loading…</span>
  </div>
</template>
```

---

## Swift: extract method from large body

Before — long `body` with inline logic:

```swift
var body: some View {
	VStack {
		if user.role == "admin" && !isLoading {
			Text("Admin: \(user.name)")
				.font(.headline)
				.foregroundColor(.blue)
		}
	}
}
```

After — extracted computed property:

```swift
private var adminHeader: some View {
	Text("Admin: \(user.name)")
		.font(.headline)
		.foregroundColor(.blue)
}

var body: some View {
	VStack {
		if user.role == "admin" && !isLoading {
			adminHeader
		}
	}
}
```

---

## Debt triage: duplicate validation logic

**Symptom:** same email validation regex copied into 4 form components.

**Category:** code debt (duplication).

**Impact:** high — a bug fix or rule change must be applied in 4 places; one is always missed.

**Effort:** low — extract to `@lewishowles/helpers` or a local `validate-email.js`.

**Action:** quick win — extract now, update all 4 call sites, add a single unit test.
