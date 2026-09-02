# PaperTodo HarmonyOS Agent Rules

## Formal package is the default

- When the user asks to build, package, release, or make a “正式包”, use `.github/workflows/harmonyos-package.yml` and produce a versioned **release-signed APP**. Do not substitute an unsigned APP/HAP.
- A formal package is complete only after AGC release certificate/Profile creation, `hap-sign-tool sign-app`, `hap-sign-tool verify-app`, SHA-256 generation and artifact upload all succeed.
- Required repository secrets are `AGC_SERVICE_ACCOUNT_JSON` and `AGC_APP_ID`. Never print, copy, commit, or ask the user to paste their values. The API client secrets are not needed by the verified signing path.
- Missing credentials, AGC errors, signing errors, verification errors, missing outputs, or checksum errors must fail the workflow. Never fall back to unsigned output while keeping a formal-package name.
- Formal artifacts and APP filenames must contain the app version, `release`, and `signed`. The ZIP may contain only the verified signed APP, `SHA256SUMS`, and non-secret build metadata.
- Keep the successful run's AGC release certificate and Profile. Delete only stale CI/test resources before a replacement run, always Profile first and certificate second; deleting the current Profile/certificate can invalidate the package.
- Never commit P12 files, certificates, Profiles, private keys, passwords, JWTs, service-account JSON, or decoded signing material. Signing material may exist only in the runner's temporary directory and must never be uploaded.
- Unsigned builds are allowed only when the user explicitly asks for a debug/unsigned developer build. Call them unsigned test builds, never formal packages.
- After changing packaging code, validate YAML, run `bash -n` on signing scripts, run a clean local release assembly, then push and wait for the remote signing workflow to finish. A local unsigned assembly alone does not satisfy a formal-package request.
