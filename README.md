# Protein

Protein is a minimalist, native iPhone app for tracking daily protein. The one-week MVP will support fast manual entries, reusable meals, seven-day history, AI-assisted estimates from meal photos, and an interactive Home Screen widget.

## Status

Planning complete. Implementation begins with Day 1 in the Notion roadmap.

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

Prerequisites are Xcode 26 or newer and an iPhone capable of running the deployment target selected on Day 1. Exact build, signing, App Group, proxy, and test instructions will be added as each feature is implemented.

## License

MIT

