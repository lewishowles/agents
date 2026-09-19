# E2E testing — patterns

## Cypress component test

Projects may provide custom helpers via `@cypress/support/mount`:

- `cy.getByData("data-test-value")` — select by `data-test` attribute
- `cy.getFormField("data-test-value")` — select native form control inside a form component
- `cy.shouldBeVisible()`, `cy.shouldHaveAttribute(attr, value)`, `cy.shouldNotHaveAttribute(attr)`, `cy.shouldHaveText(text)`, `cy.shouldHaveClass(cls)`

```javascript
import { createMount } from "@cypress/support/mount";
import FormInput from "./form-input.vue";

const defaultProps = { id: "id-abc" };
const defaultSlots = { default: "Your name" };
const mount = createMount(FormInput, { props: defaultProps, slots: defaultSlots });

describe("form-input", () => {
  it("Sets aria-invalid when an error is provided", () => {
    mount({ slots: { error: "Error text" } });
    cy.getFormField("form-input").shouldHaveAttribute("aria-invalid", "true");
  });

  it("Does not set aria-invalid without an error", () => {
    mount();
    cy.getFormField("form-input").shouldNotHaveAttribute("aria-invalid");
  });
});
```

## Playwright component test

Use `@playwright/experimental-ct-vue` (or relevant framework package).

```typescript
import { test, expect } from "@playwright/experimental-ct-vue";
import FormInput from "./form-input.vue";

test("sets aria-invalid when an error is provided", async ({ mount }) => {
  const component = await mount(FormInput, {
    props: { id: "id-abc" },
    slots: { default: "Your name", error: "Error text" },
  });

  await expect(component.locator("input")).toHaveAttribute("aria-invalid", "true");
});
```

## Playwright setup

```bash
bun add -D @playwright/test
```

```typescript
// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: "html",
  use: { baseURL: "http://localhost:5173" },
  webServer: {
    command: "bun run dev",
    url: "http://localhost:5173",
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
  ],
});
```

## Full e2e test structure

```typescript
import { test, expect } from "@playwright/test";

test("user registers and logs in", async ({ page }) => {
  await page.goto("/register");

  await page.fill('[data-test="form-register.email"]', "user@example.com");
  await page.fill('[data-test="form-register.password"]', "secure-pass");
  await page.click('[data-test="form-register.submit"]');
  await page.waitForURL("/login");

  await page.fill('[data-test="form-login.email"]', "user@example.com");
  await page.fill('[data-test="form-login.password"]', "secure-pass");
  await page.click('[data-test="form-login.submit"]');

  await expect(page).toHaveURL("/dashboard");
  await expect(page.locator('[data-test="page-dashboard"]')).toBeVisible();
});
```

## Interaction patterns

```typescript
// Click and navigate
await page.click('[data-test="nav.settings"]');
await page.waitForURL("/settings");

// Form input
await page.fill('[data-test="form.name"]', "Lewis");
await page.selectOption('[data-test="form.role"]', "admin");
await page.check('[data-test="form.terms"]');

// Wait for element
await page.waitForSelector('[data-test="message.success"]');

// Extract data
const count = await page.locator('[data-test="list-item"]').count();
const text = await page.locator('[data-test="page-title"]').textContent();
```

## Best practices

- **One user journey per test** — full flows, not isolated pieces
- **Use data attributes** — `data-test="user-input"` is more stable than CSS selectors
- **Wait explicitly** — avoid `page.waitForTimeout()`; use `waitForURL()` or `waitForSelector()`
- **Cleanup** — no test data left behind; use `beforeAll`/`afterAll` for setup/teardown
- **Parallel tests** — parallel by default; no execution-order dependency
