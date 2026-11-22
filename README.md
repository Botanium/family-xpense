# Family Xpense

A household money app for two partners: Flutter iOS app, Genkit Dart agent on
Cloud Run, A2UI v1.0 generative UI. The specification is in [`docs/`](docs/);
start with [`docs/DELEGATION.md`](docs/DELEGATION.md) and
[`docs/DECISIONS.md`](docs/DECISIONS.md).

## Layout

| Path | What | Package |
|---|---|---|
| `app/` | Flutter app, iOS first | `xpense_app` |
| `server/` | Dart service, one image, two Cloud Run services | `xpense_agent` |
| `packages/xpense_shared/` | pure Dart core used by both | `xpense_shared` |
| `firebase/` | rules, indexes, emulator config, rules tests | |
| `evals/` | evaluation datasets and fixtures | |
| `docs/` | specification | |

## Toolchain

Flutter **3.50.1** / Dart **3.14.0**, pinned in [`.fvmrc`](.fvmrc). With
[FVM](https://fvm.app) run `fvm use` once; without it, make sure
`flutter --version` prints 3.50.1. CI reads the same file.

## Rules that the tooling enforces

- **No pub workspace (D-05).** `app` and `server` depend on `xpense_shared` by
  path and keep separate `pubspec.lock` files, because `a2ui_flutter 0.4.0`
  needs `a2ui_core ^0.8.0` and `genkit_a2ui 0.6.0` needs `^0.7.0`. Run
  `pub get` in each package directory.
- **Versions.** Packages at 1.0 or above use a caret range starting at the
  version in the brief; pre-1.0 packages are pinned exactly. Lockfiles are
  committed and CI runs `pub get --enforce-lockfile`.
- **Lints.** One [`analysis_options.yaml`](analysis_options.yaml) at the root
  (`very_good_analysis` 11.0.0 ruleset, pinned by file name); each package
  includes it. CI treats infos as failures.
- **Import rules.** `app/test/architecture/` enforces the layer table in
  ARCHITECTURE 3.1 and keeps pre-1.0 and native packages in their adapter
  layer; `server/test/architecture/` does the same for the server modules;
  `packages/xpense_shared/test/architecture/` keeps the shared core pure.
- **Material and Cupertino (D-22).** The app imports `package:material_ui`
  and `package:cupertino_ui`, not the deprecated bundled
  `package:flutter/material.dart`. Only `lib/a2ui/` may import the bundled
  library, for the compatibility bridge the `a2ui_flutter` basic widgets need.
- **Codegen.** Generated files (`*.g.dart`) are committed. Run
  `dart run build_runner build` before analyzing; CI regenerates and fails if
  the result differs from what is committed.

## Checks

```bash
cd packages/xpense_shared && dart pub get && dart analyze && dart test
cd server && dart pub get && dart analyze && dart test
cd app && flutter pub get && flutter analyze && flutter test
```

CI runs one path-filtered workflow per area: `shared`, `app`, `server` and
`rules` (see [`.github/workflows/`](.github/workflows/)).
