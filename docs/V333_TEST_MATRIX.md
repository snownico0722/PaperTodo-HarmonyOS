# 3.3.3 device test matrix

| Case | Expected |
| --- | --- |
| Paper top bar | No cross-paper drag-link handle is visible and no 26vp gap is reserved. |
| Taskbar / launcher click | Settings window is restored or shown. |
| Expanded capsule queue | Master capsule width follows its label; ordinary capsules render below it; no opaque host rectangle is visible. |
| Retracted capsule queue | Only the master capsule remains in layout and native host height equals one capsule row. |
| Capsule host transparency | Areas outside capsule rows are transparent after cold start and after restore. |
