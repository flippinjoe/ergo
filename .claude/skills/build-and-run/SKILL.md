# Skill: build-and-run

**Description:** Generate the Xcode project, build the macOS app, and launch it.

**Trigger:** "build the app", "run Ergo", "launch it", after changing app-shell
or `project.yml`.

## Steps

1. On a fresh checkout (or after tool changes), bootstrap once:
   ```
   make bootstrap
   ```
   This verifies the toolchain and builds the vendored XcodeGen. It fails
   loudly if `swift`/`xcodebuild` are missing.

2. Generate the project from the manifest (needed after editing `project.yml`,
   or when `Ergo.xcodeproj` is absent — it's gitignored):
   ```
   make generate
   ```

3. Build the SPM package and the app:
   ```
   make build
   ```

4. Launch:
   ```
   make run
   ```

## Notes

- The app wires `FakeClusterClient` — it renders fixture data and never touches
  a real cluster.
- Signing is "Sign to Run Locally" (ad-hoc, `CODE_SIGN_IDENTITY = -`), so it
  builds with no Apple account. `make build` passes `CODE_SIGNING_ALLOWED=NO`
  for headless CI.
- Source of truth is `project.yml`; **never** hand-edit `Ergo.xcodeproj`.
- If the build fails after editing dependencies, re-run `make generate`.
