# PaperTodo HarmonyOS 3.3.3 device regression notes

This release is limited to the three regressions confirmed on HarmonyOS PC / 2in1 after 3.3.2.

- Temporarily hide the cross-paper drag-link handle while preserving existing association data and non-drag behavior.
- Make `ManagerAbility` the actual HOME/taskbar entry and keep `EntryAbility` runtime-only.
- Tighten the right-edge capsule host: content-sized master row, native host retraction to one row, and transparent native surface re-applied after `loadContent()`.

Device validation remains required for taskbar activation and compositor transparency. API 23 compilation and the formal signing chain are release gates, not substitutes for device testing.
