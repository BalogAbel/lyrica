#!/usr/bin/env python3
import json
import sys


def extract_first_json_object(raw: str) -> str:
    decoder = json.JSONDecoder()
    for index, char in enumerate(raw):
        if char != "{":
            continue
        try:
            _, end = decoder.raw_decode(raw[index:])
            return raw[index : index + end]
        except json.JSONDecodeError:
            continue
    raise SystemExit("Could not find a JSON object in Supabase CLI output.")


def main() -> None:
    raw = sys.stdin.read()
    if not raw:
        raise SystemExit("Expected Supabase CLI output on stdin.")
    payload = extract_first_json_object(raw)
    parsed = json.loads(payload)
    json.dump(parsed, sys.stdout)


if __name__ == "__main__":
    main()
