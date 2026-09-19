# Frontend security — extended patterns

## Input validation

Client-side validation is for UX, not security — the server must re-validate everything. But client-side validation still reduces the risk of bad data reaching the DOM.

- Use allowlist (permitted values/patterns) over denylist (blocked strings)
- Validate type, format, length, and range at the point of input
- Never rely solely on `type="email"` or `type="number"` — supply explicit pattern validation too
- Avoid complex regular expressions on user-supplied input (ReDoS risk); keep patterns simple

```javascript
function isValidEmail(value) {
  return (
    typeof value === "string" && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254
  );
}
```

## File upload safety

Client-side file validation is a UX check only — never trust it for security. Add server-side validation too.

```javascript
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];
const MAX_SIZE_BYTES = 5 * 1024 * 1024; // 5 MB

function validateFile(file) {
  if (!ALLOWED_TYPES.includes(file.type)) return "Unsupported file type.";
  if (file.size > MAX_SIZE_BYTES) return "File exceeds 5 MB limit.";
  return null;
}
```

Note: `file.type` is set by the browser from the file extension, not the actual content — it can be spoofed. Server-side MIME sniffing is required for real enforcement.

## Subresource integrity (SRI)

When loading scripts or stylesheets from a CDN, add an `integrity` attribute so the browser verifies the file hasn't been tampered with:

```html
<script
  src="https://cdn.example.com/lib.min.js"
  integrity="sha384-<hash>"
  crossorigin="anonymous"
></script>
```

Generate hashes with: `openssl dgst -sha384 -binary lib.min.js | openssl base64 -A`

Use SRI for all third-party scripts and stylesheets you don't control. Vite can automate this via `vite-plugin-sri`.

## Clickjacking

Prevent your app from being embedded in malicious iframes:

1. **HTTP header** (server-side, most reliable): `X-Frame-Options: DENY` or CSP `frame-ancestors 'none'`
2. **JavaScript frame detection** (client-side fallback):

```javascript
if (window.self !== window.top) {
  document.body.innerHTML = "";
  window.top.location = window.self.location;
}
```

Note: disable or relax iframe restrictions during development if you use devtools embeds or preview iframes.

## CSS injection

Dynamic CSS can be a vector if user-supplied values are placed into style attributes or `<style>` tags:

```javascript
// Dangerous — user controls a CSS value
element.style.cssText = userInput;

// Safe — set individual, validated properties
const ALLOWED_COLOURS = ["red", "blue", "green"];
if (ALLOWED_COLOURS.includes(userInput)) {
  element.style.color = userInput;
}
```

Avoid `style` bindings that contain unvalidated user input. Prefer CSS custom properties with validated values.

## Open redirect prevention

Never build redirect targets from raw query parameters:

```javascript
// Dangerous
const next = new URLSearchParams(location.search).get("next");
router.push(next);

// Safe — validate the target is a relative path on the same origin
function isSafeRedirect(url) {
  if (!url || url.startsWith("//") || /^[a-z]+:/i.test(url)) return false;
  return url.startsWith("/");
}

const next = new URLSearchParams(location.search).get("next");
router.push(isSafeRedirect(next) ? next : "/");
```

## Security headers checklist

Verify these are set by your server or CDN:

| Header                      | Recommended value                                  |
| --------------------------- | -------------------------------------------------- |
| `Content-Security-Policy`   | See SKILL.md                                       |
| `X-Content-Type-Options`    | `nosniff`                                          |
| `X-Frame-Options`           | `DENY`                                             |
| `Referrer-Policy`           | `strict-origin-when-cross-origin`                  |
| `Permissions-Policy`        | Restrict unused APIs (camera, mic, geolocation)    |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` (HTTPS only) |
