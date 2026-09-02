# 3.3.3 release checklist

- [ ] PR changed-file review contains no temporary workflow helper.
- [ ] HarmonyOS API 23 PR build succeeds.
- [ ] Merge only after final head is green.
- [ ] Formal release APP build succeeds on trusted `main`.
- [ ] AGC release signing succeeds.
- [ ] `hap-sign-tool verify-app` succeeds.
- [ ] SHA-256 and signed artifact are uploaded.
- [ ] Device retest: drag-link handle hidden, taskbar opens Settings, capsule host has no gray dead rectangle and retracts to one row.
