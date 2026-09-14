# Protein

Protein is a premium-feeling minimalist, native iPhone app for tracking daily protein and body-weight progress. The roadmap covers fast manual entries, reusable meals, weekly and monthly insights, AI-assisted estimates from meal photos, an interactive Home Screen widget, personalized onboarding, and optional account creation.

## Status

Day 6 adds a small and medium interactive widget with synchronized daily progress, offline quick additions, repeat-last support, local-day rollover, and a deep link into precise manual entry.

## Product principles

- Protein only: calories and other macros are deliberately out of scope.
- Manual logging must remain fast and work offline.
- The interface should feel modern and expensive through restraint, typography, spacing, and polish rather than clutter.
- Photo analysis produces an editable estimate, never an unquestioned fact.
- Suggested protein goals must be transparent, editable guidance rather than medical certainty.
- Height and weight are sensitive profile data and must remain private.
- Account creation is optional and must not weaken guest or offline use.
- Meal photos are not retained by default.
- AI credentials must never be embedded in the public app or committed to Git.
- The app and source code are free to use under the MIT License.

## Planned architecture

- SwiftUI for an iPhone-first interface
- SwiftData behind a repository boundary for local persistence
- Swift Charts for accessible seven-day history
- WidgetKit and App Intents for totals and quick additions
- A provider-neutral `MealAnalysisService`
- A configurable secure proxy for live image analysis
- Shared App Group storage for app/widget synchronization
- Local profile and dated weight models behind repository boundaries
- Protocol-driven authentication with session material stored in Keychain

## Roadmap

1. Scaffold the app, widget, persistence layer, and design system.
2. Build manual protein logging and daily-goal tracking.
3. Add weekly history, a monthly goal calendar, and reusable meals.
4. Define and test the AI meal-analysis boundary.
5. Connect camera/photos to live, editable AI estimates.
6. Build the interactive protein widget.
7. Apply premium visual polish, test, document, and install on a physical iPhone.
8. Add first-launch height/weight onboarding and an editable suggested protein goal.
9. Add private dated weight tracking and an accessible progress graph.
10. Add secure optional account creation without uploading local health-related data.

The detailed roadmap, acceptance criteria, and daily prompts live in the Protein page in Notion.

## Security and cost note

Do not put an AI provider key in the iOS target, source code, configuration committed to Git, or app bundle. The first personal build should call a configurable proxy whose credential is stored server-side. A broader free release will need explicit usage limits, abuse controls, or a bring-your-own-provider model because cloud inference has a real per-request cost.

## Development

### Prerequisites

- Xcode 26 or newer
- An iOS 18 or newer simulator
- A free or paid Apple development team for device installation

### First run

1. Open `Protein.xcodeproj` in Xcode.
2. Select the **Protein** scheme and an iPhone simulator.
3. Build and run. The starter dashboard intentionally shows an empty day.
4. Run the **Protein** scheme's tests with Product → Test.

The checked-in bundle IDs and App Group use the generic `com.example` namespace. Before installing on a physical device, change the app and widget bundle identifiers, set `APP_GROUP_IDENTIFIER` in `Config/Shared.xcconfig`, and register the same App Group capability for both targets.

### Architecture

- `Protein/App`: application entry point and shared App Group constants
- `Protein/Dashboard`: today's live progress and manual logging
- `Protein/Insights`: shared weekly and monthly goal progress
- `Protein/Meals`: reusable meal management and repeat logging
- `Protein/DesignSystem`: spacing, radii, semantic colors, cards, and buttons
- `Protein/Persistence`: SwiftData models, container setup, and repository boundary
- `Protein/Widget`: WidgetKit extension using the same App Group identifier
- `Protein/Tests`: deterministic in-memory persistence tests
- `Protein/Analysis`: provider-neutral models, validation, deterministic fixtures, and editable estimate review
- `Server`: optional Cloudflare Worker proxy example; the provider credential exists only in server-side environment variables

Domain calculations and mutations stay behind `ProteinRepository` and testable core types. SwiftUI uses live SwiftData queries where immediate screen updates matter, while insights fetch only the visible week/month window. `PersistenceController.makeInMemory()` supplies an isolated test store.

### Local configuration and secrets

Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` only when local configuration is needed. The local file is ignored by Git. Set `PROTEIN_PROXY_BASE_URL` to the deployed HTTPS proxy origin. Never place an AI provider credential in the app, widget, repository, or application bundle.

### Photo estimation setup and limits

The Estimate tab uses Apple's system Photos picker or the camera. Protein redraws the selected image at no more than 1,600 pixels on its longest edge, converts it to a metadata-minimized JPEG under 2 MB, and sends only that temporary copy to `POST /v1/meal-analysis`. It does not save the photo to SwiftData, the photo library, or application storage. A failed request may remain in memory only long enough for the user to tap Retry; success, replacement, discard, or leaving the screen clears it.

The example proxy lives in `Server`; follow `Server/README.md` to configure it. It uses the [OpenAI Responses API](https://developers.openai.com/api/reference/cli/resources/responses/methods/create), which supports image inputs and structured JSON outputs. Provider use has a real cost and provider-side data handling depends on the selected account and model. Run a live smoke test only with an explicitly authorized photo and after reviewing current pricing.

Photo-derived foods, portions, confidence values, and protein grams are estimates based on what is visible. Hidden ingredients and uncertain portion sizes can materially change the result. The app validates every response, highlights low confidence, and saves nothing until the user reviews, edits, and confirms it. Physical camera hardware and permission behavior must still be checked on an iPhone.

### Interactive widget

Add **Daily Protein** from the system widget gallery after running the app once. The small widget shows today’s total, goal progress, last refresh, and +5 g/+10 g actions. The medium widget also repeats the latest valid entry and opens Protein’s precise manual-entry sheet.

App and widget mutations save real SwiftData entries in the shared App Group store, then publish a compact versioned snapshot for fast rendering. The snapshot contains only today’s total, goal, refresh time, and the latest entry’s name and grams; it contains no meal photos, account data, or AI credentials. Missing or unreadable state falls back safely, legacy total keys migrate on the next write, and a scheduled midnight timeline entry resets the visible total using the local calendar.

Widget actions remain offline. If protected data is unavailable while the device is locked, the action fails with a recoverable instruction instead of inventing or silently duplicating an entry. Each explicit quick-add or repeat invocation creates at most one entry.

### Command-line verification

```sh
xcodebuild -project Protein.xcodeproj -scheme Protein -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
```

## License

MIT
