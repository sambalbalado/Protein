import assert from "node:assert/strict";
import test from "node:test";
import { findOutputText, validateAndNormalize } from "./worker.js";

const validEstimate = {
  isFood: true,
  refusalReason: null,
  foods: [{
    name: "Grilled chicken",
    assumedPortion: "One palm-sized breast",
    proteinGrams: 38,
    confidence: 0.82,
  }],
  totalProteinGrams: 38,
  warnings: ["Portion size is inferred."],
};

test("normalizes a valid estimate to the iOS response schema", () => {
  const result = validateAndNormalize(validEstimate);
  assert.equal(result.totalProteinGrams, 38);
  assert.match(result.foods[0].id, /^[0-9a-f-]{36}$/i);
  assert.equal(result.foods[0].name, "Grilled chicken");
});

test("rejects an inconsistent provider total", () => {
  assert.throws(() => validateAndNormalize({ ...validEstimate, totalProteinGrams: 90 }));
});

test("extracts output text without assuming the first response item", () => {
  const payload = {
    output: [
      { type: "reasoning", content: [] },
      { type: "message", content: [{ type: "output_text", text: "{\"foods\":[]}" }] },
    ],
  };
  assert.equal(findOutputText(payload), "{\"foods\":[]}");
});
