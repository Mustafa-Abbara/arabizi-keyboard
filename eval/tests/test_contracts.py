"""Engine contracts (roadmap P5 step 1): the examples in docs/schemas match the JSON Schemas.

The Swift tests (Packages/ArabiziContracts) decode and re-encode the same examples, so the schemas, the examples
and the Swift types cannot drift apart.
"""

import json

import pytest
from jsonschema import Draft202012Validator

from arabizi_eval import pairs as P

SCHEMAS = P.ROOT / "docs" / "schemas"


def validator(name: str) -> Draft202012Validator:
    schema = json.loads((SCHEMAS / f"{name}.v1.schema.json").read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=Draft202012Validator.FORMAT_CHECKER)


def example(name: str) -> dict:
    return json.loads((SCHEMAS / "examples" / f"{name}.json").read_text(encoding="utf-8"))


@pytest.mark.parametrize("name", ["convert_request", "convert_response"])
def test_examples_match_their_schema(name):
    validator(name).validate(example(name))


@pytest.mark.parametrize(("name", "change"), [
    ("convert_request", {"v": 2}),
    ("convert_request", {"deadlineMs": 0}),
    ("convert_request", {"extra": True}),
    ("convert_response", {"outcome": "guess"}),
    ("convert_response", {"latencyMs": -1}),
])
def test_bad_messages_fail_the_schema(name, change):
    assert not validator(name).is_valid(example(name) | change)
