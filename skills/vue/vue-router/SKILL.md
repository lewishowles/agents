---
name: vue-router
description: >
  Use this skill when working with Vue Router routes, navigation guards, params, query strings, layouts, redirects, or route-driven state. Covers async guards, same-route param updates, side-effect cleanup, and the boundary between router state and component state.
---
# Vue Router

Use Vue Router for production Vue SPAs and route-driven state. Keep URL state meaningful for shareable filters, tabs, pagination, selected records, and search.

## Routes and state

- Keep routes named and domain-oriented
- Use route params for resource identity and query strings for view state
- Keep temporary UI state in components or Pinia
- Validate route params before using them for API calls or store lookups
- Keep route metadata small: auth, layout, titles, and feature flags

## Navigation guards

- Prefer modern guards that return a value or throw
- Avoid legacy `next()` unless maintaining code already using it
- Guard redirects against loops by checking the target route
- Keep API-heavy guard work minimal; prefer page-level loading when possible

```typescript
router.beforeEach((to) => {
	if (to.meta.requiresAuth && !authStore.isSignedIn) {
		return { name: "sign-in", query: { redirect: to.fullPath } };
	}
});
```

## Same-route updates

Vue reuses component when only params or query values change.

- Watch specific route params or query values, not the whole route object
- Use `onBeforeRouteUpdate()` when navigation should be accepted, rejected, or reload data
- Cancel stale async work when params change

```typescript
const route = useRoute();

watch(
	() => route.params.projectId,
	(projectId) => {
		loadProject(projectId);
	}
);
```

## Side effects

- Remove event listeners, timers, and subscriptions on unmount or route change
- Stop watchers created outside component setup scopes
- Avoid beforeRouteEnter; use Composition API guards instead

## Accessibility

- Move focus to main region/heading after route changes (when not fully reloading)
- Update document titles from route metadata or page setup
- Preserve meaningful browser history for user-triggered navigation

## Completion

For route or page UI changes, run [the accessibility checklist](../../accessibility/accessibility/references/checklist.md) before handoff.
