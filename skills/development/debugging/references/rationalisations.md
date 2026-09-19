# Debugging — common rationalisations

| Excuse                                         | Reality                                                                   |
| ---------------------------------------------- | ------------------------------------------------------------------------- |
| "Issue seems simple, no need for process"      | Simple bugs have root causes too. The process is fast for simple bugs.    |
| "Emergency — no time to investigate"           | Systematic debugging is faster than guess-and-check thrashing.            |
| "Let me just try this first, then investigate" | The first fix sets the pattern. Do it right from the start.               |
| "I'll test after confirming the fix works"     | Untested fixes don't stick. A failing test first proves the fix.          |
| "Multiple fixes at once saves time"            | You can't isolate what worked. It causes new bugs.                        |
| "I see the problem, let me fix it"             | Seeing a symptom is not the same as understanding the root cause.         |
| "One more fix attempt" (after two failures)    | Three failures indicates an architectural problem — question the pattern. |
