# Unit testing — code examples

## Component logic test

```javascript
import { mount } from "@vue/test-utils";
import { describe, expect, test } from "vitest";

import FormCounter from "./form-counter.vue";

describe("form-counter", () => {
  describe("Emits", () => {
    test("Emits an updated count when incremented", () => {
      const wrapper = mount(FormCounter, {
        props: { modelValue: 2 },
      });

      wrapper.vm.increment();

      expect(wrapper.emitted("update:modelValue")).toEqual([[3]]);
    });
  });
});
```

## Composable test

```javascript
// src/composables/use-form.test.js
import { describe, expect, test } from "vitest";
import { useForm } from "./use-form";

describe("useForm", () => {
  describe("Initialisation", () => {
    test("Initialises with default values", () => {
      const { data } = useForm({ name: "", email: "" });
      expect(data.value).toEqual({ name: "", email: "" });
    });
  });

  describe("Computed", () => {
    test("hasErrors is true when errors are present", () => {
      const { errors, hasErrors } = useForm({ name: "" });
      errors.value.name = "Name is required";
      expect(hasErrors.value).toBe(true);
    });
  });

  describe("Methods", () => {
    test("Updates field values", () => {
      const { data, updateField } = useForm({ name: "", email: "" });
      updateField("name", "Lewis");
      expect(data.value.name).toBe("Lewis");
    });

    test("Validates required fields", () => {
      const { validate, errors } = useForm({ name: "" }, { name: { required: true } });
      validate();
      expect(errors.value.name).toBeDefined();
    });

    test("Resets the form to its initial state", () => {
      const { data, updateField, reset } = useForm({ name: "Lewis" });
      updateField("name", "Jane");
      reset();
      expect(data.value.name).toBe("Lewis");
    });
  });
});
```

## Helper test

```javascript
import { describe, expect, test } from "vitest";
import get from ".";

describe("get", () => {
  test("Retrieves a top-level property", () => {
    const sampleObject = {
      name: "Sophie",
      profiles: { linkedIn: "linkedin/sophie" },
    };

    expect(get(sampleObject, "name")).toBe("Sophie");
  });
});
```

## Testing input types with `test.for`

When a function expects a specific type, use `test.for()` with a shared invalid-input list, removing cases the function should accept:

```javascript
test.for([
  ["boolean (true)", true],
  ["boolean (false)", false],
  ["number (positive)", 1],
  ["number (negative)", -1],
  ["number (NaN)", NaN],
  ["string (non-empty)", "string"],
  ["string (empty)", ""],
  ["object (non-empty)", { property: "value" }],
  ["object (empty)", {}],
  ["array (non-empty)", [1, 2, 3]],
  ["array (empty)", []],
  ["null", null],
  ["undefined", undefined],
])("Rejects invalid <something>: %s", ([, input]) => {
  expect(myHelper(input)).toBe("...");
});
```

Remove entries that are valid inputs for the helper under test. For `isNonEmptyObject`, remove `["object (non-empty)", { property: "value" }]`.

## File co-location

Place test file next to the component, composable, or utility using `.test.js`. Vitest discovers and runs automatically.
