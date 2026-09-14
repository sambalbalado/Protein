# Meal-analysis proxy example

This Cloudflare Worker is the only component that talks to the AI provider. The iOS app sends a metadata-minimized image to `POST /v1/meal-analysis`; the Worker reads its credential from `OPENAI_API_KEY`, requests strict structured output, validates the result again, and returns the Day 4 client schema.

## Local setup

1. Install the example dependencies with `npm install` inside `Server`.
2. Copy `.dev.vars.example` to `.dev.vars` and replace both placeholder values. `.dev.vars` is ignored and must never be committed.
3. Run `npm run dev`.
4. For a deployed Worker, store the credential with `npx wrangler secret put OPENAI_API_KEY` and configure `OPENAI_MODEL` as a Worker variable.
5. Copy `Config/Secrets.xcconfig.example` to `Config/Secrets.xcconfig`, then set `PROTEIN_PROXY_BASE_URL` to the HTTPS Worker origin. Do not include `/v1/meal-analysis`; the app appends that path.

The example uses the OpenAI Responses API with image input, strict JSON Schema output, and `store: false`. Review current model support and pricing before choosing `OPENAI_MODEL`. Production exposure also needs gateway-level authentication, per-client rate limits, spend limits, and abuse controls; this small example deliberately does not embed a reusable proxy credential in the public iOS app.

## Privacy and limits

- The Worker rejects images over 2 MB and times out provider work after 22 seconds.
- Request bodies, image bytes, and provider payloads are never logged by this code; Worker observability is disabled in the example configuration.
- The Worker does not write images to storage. Provider-side data handling remains governed by the selected provider and account settings.
- Results are estimates based on visible food and inferred portions. The client requires review and supports editing before any local entry is saved.
- The example is not a production authentication or abuse-prevention layer.
