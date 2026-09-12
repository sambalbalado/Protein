# Protein development instructions

Protein is a native, iPhone-first protein tracker. Keep the experience premium-minimal, accessible, privacy-conscious, and honest about uncertainty. Aim for quiet luxury: confident typography, generous spacing, restrained color, precise alignment, and subtle motion without decorative clutter.

## Session protocol

When the user says `PROTEIN`:

1. Read `README.md`, `TASKS.md`, this file, the current Git history, and the Protein roadmap in Notion.
2. Run the existing build and tests before editing.
3. Select the lowest-numbered unfinished daily task.
4. Work only on that task and its acceptance criteria.
5. Show verification results and the diff, then make and push one focused commit when checks pass; the user has granted standing approval for successful daily commits.
6. Mark the Notion task Done and record the pushed commit hash.
7. Name the next task, but do not begin it in the same session.

## Engineering rules

- Use SwiftUI, SwiftData, WidgetKit, App Intents, and native Apple frameworks unless the active task justifies otherwise.
- Keep domain and persistence logic out of SwiftUI views.
- Prefer protocol-driven dependencies and deterministic test doubles.
- Manual logging must work offline.
- Account creation is optional and must never block local or offline manual logging.
- Treat height and weight as sensitive local profile data; never log or expose them.
- Protein-goal suggestions must show their basis, remain editable, and never be framed as medical certainty.
- Treat every photo-derived protein value as an editable estimate.
- Never save an AI result before the user confirms it.
- Do not retain meal photos by default or log image data.
- Never commit secrets, signing assets, personal identifiers, or personal meal photos.
- Keep the AI provider replaceable behind `MealAnalysisService`.
- Keep authentication replaceable behind a protocol-driven service and store session material in Keychain.
- Add tests for domain logic, date boundaries, persistence, service validation, and widget synchronization in proportion to the active task.
- Do not invent build results, benchmarks, screenshots, or AI accuracy claims.
- Do not expand scope to calories, other macros, cloud sync, social features, subscriptions, behavioral analytics, HealthKit, barcode scanning, TestFlight, or App Store work unless explicitly requested.

## Quality bar

- Support light/dark mode and Dynamic Type.
- Verify the premium-minimal visual language across compact and large iPhones, Reduce Motion, and increased contrast.
- Add VoiceOver labels and accessible summaries for visual charts.
- Handle loading, empty, offline, invalid, and cancellation states.
- Keep commits focused and leave the tree clean.
