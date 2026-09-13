# Meal analysis boundary

Protein treats photo analysis as an untrusted estimate. The iOS app sends image bytes only after the user chooses a photo, receives structured JSON through `MealAnalysisService`, validates the entire response, and presents an editable draft. Nothing enters SwiftData until the user presses **Confirm and save**.

Day 4 uses `MockMealAnalysisService` only. It performs no network request and requires no credential.

## Client configuration

The future proxy base URL is supplied through the `ProteinAnalysisServiceURL` Info.plist value backed by `PROTEIN_PROXY_BASE_URL` in xcconfig. Local overrides belong in ignored `Config/Secrets.xcconfig`. Provider credentials must exist only on the server and must never be added to the app bundle.

## Proposed proxy contract

`POST /v1/meal-analysis` with an authenticated, rate-limited multipart request:

- `image`: JPEG or HEIC bytes with a strict server-side size limit
- `response_version`: `1`

Successful JSON response:

```json
{
  "foods": [
    {
      "id": "0F4A2D7B-54AA-49F2-8EB9-BF07A6C8FD05",
      "name": "Grilled chicken",
      "assumedPortion": "About one palm-sized breast",
      "proteinGrams": 38,
      "confidence": 0.88
    }
  ],
  "totalProteinGrams": 38,
  "warnings": ["Portion size is inferred from the image."]
}
```

The client rejects missing fields, empty foods or portions, non-finite/out-of-range numbers, confidence outside `0...1`, and totals that differ from item sums by more than 0.5 g. A rejected response never produces stored entries.

Errors map to stable client states: no network, timeout, refusal, malformed response, missing configuration, or cancellation. Error bodies must not echo image bytes, credentials, or provider internals.

## Threat model

- **Credential extraction:** no provider key exists in the public client; the proxy owns secrets.
- **Untrusted model output:** strict decoding and semantic validation occur before review or persistence.
- **Prompt injection in images:** model text is treated as data, never as executable instructions.
- **Oversized or malicious uploads:** client and proxy enforce MIME, byte-size, decompression, and timeout limits.
- **Privacy leakage:** photos are not retained by default; request bodies and response payloads are excluded from logs.
- **Replay and abuse:** the proxy applies short-lived authorization, rate limits, request-size limits, and abuse controls.
- **Transport interception:** production configuration requires HTTPS and rejects embedded URL credentials.
- **Partial writes:** all reviewed food entries are validated first and saved as one repository operation.
