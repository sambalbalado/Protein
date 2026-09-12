# Protein

Protein is a minimalist, native iPhone app for tracking daily protein. The one-week MVP will support fast manual entries, reusable meals, seven-day history, AI-assisted estimates from meal photos, and an interactive Home Screen widget.

## Status

Day 1 foundation is implemented: the app, widget extension, shared persistence module, design system, dashboard shell, and unit-test target are ready for feature work.

## Product principles

- Protein only: calories and other macros are deliberately out of scope.
- Manual logging must remain fast and work offline.
- Photo analysis produces an editable estimate, never an unquestioned fact.
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

## One-week roadmap

1. Scaffold the app, widget, persistence layer, and design system.
2. Build manual protein logging and daily-goal tracking.
3. Add history, charts, and reusable meals.
4. Define and test the AI meal-analysis boundary.
5. Connect camera/photos to live, editable AI estimates.
6. Build the interactive protein widget.
7. Polish, test, document, and install on a physical iPhone.

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
- `Protein/Dashboard`: the empty-state dashboard shell
- `Protein/DesignSystem`: spacing, radii, semantic colors, cards, and buttons
- `Protein/Persistence`: SwiftData models, container setup, and repository boundary
- `Protein/Widget`: WidgetKit extension using the same App Group identifier
- `Protein/Tests`: deterministic in-memory persistence tests
- `Logging`, `History`, `Meals`, and `Analysis`: feature boundaries reserved for later roadmap days

Views do not access SwiftData directly. `ProteinRepository` is the boundary for persistence operations, and `PersistenceController.makeInMemory()` supplies an isolated test store.

### Local configuration and secrets

Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig` only when local configuration is needed. The local file is ignored by Git. Never place an AI provider credential in the app, widget, repository, or application bundle; live analysis will call a configurable server-side proxy.

### Command-line verification

```sh
xcodebuild -project Protein.xcodeproj -scheme Protein -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build test
```

## License

MIT
