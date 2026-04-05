#!/usr/bin/env python3
"""
generate_test_data.py — Generate fake test data using Faker.

Outputs N user records with name, email, company, and address as JSON.

Usage:
    python generate_test_data.py
    python generate_test_data.py --count 50
    python generate_test_data.py --count 10 --output-file users.json
    python generate_test_data.py --count 5 --locale en_GB
    python generate_test_data.py --count 5 --seed 42
"""

import argparse
import json
import sys
from pathlib import Path

from faker import Faker


def _state(fake: Faker) -> str:
    """Return a state/county/region string that works across all Faker locales."""
    for method in ("state", "county", "administrative_unit", "region", "province"):
        fn = getattr(fake, method, None)
        if fn:
            return fn()
    return ""

def generate_user(fake: Faker) -> dict:
    """Generate a single fake user record."""
    return {
        "id": fake.uuid4(),
        "first_name": fake.first_name(),
        "last_name": fake.last_name(),
        "full_name": fake.name(),
        "email": fake.email(),
        "phone": fake.phone_number(),
        "username": fake.user_name(),
        "company": {
            "name": fake.company(),
            "industry": fake.bs(),
            "catch_phrase": fake.catch_phrase(),
        },
        "address": {
            "street": fake.street_address(),
            "city": fake.city(),
            "state": _state(fake),
            "postcode": fake.postcode(),
            "country": fake.country(),
        },
        "date_of_birth": fake.date_of_birth(minimum_age=18, maximum_age=75).isoformat(),
        "registered_at": fake.date_time_this_decade().isoformat(),
        "is_active": fake.boolean(chance_of_getting_true=85),
        "role": fake.random_element(["admin", "editor", "viewer", "tester", "developer"]),
    }


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate fake test user data using Faker.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--count",
        "-n",
        type=int,
        default=10,
        metavar="N",
        help="Number of user records to generate",
    )
    parser.add_argument(
        "--output-file",
        "-o",
        type=str,
        default=None,
        metavar="FILE",
        help="Path to write JSON output (defaults to stdout)",
    )
    parser.add_argument(
        "--locale",
        "-l",
        type=str,
        default="en_US",
        metavar="LOCALE",
        help="Faker locale (e.g. en_US, en_GB, de_DE, fr_FR)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        metavar="SEED",
        help="Random seed for reproducible output",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=2,
        metavar="N",
        help="JSON indentation level (0 for compact output)",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    if args.count < 1:
        print("Error: --count must be at least 1.", file=sys.stderr)
        return 1

    try:
        fake = Faker(args.locale)
    except AttributeError:
        print(
            f"Error: Unsupported locale '{args.locale}'. "
            "Try en_US, en_GB, de_DE, fr_FR, es_ES, ja_JP, etc.",
            file=sys.stderr,
        )
        return 1

    if args.seed is not None:
        Faker.seed(args.seed)

    users = [generate_user(fake) for _ in range(args.count)]

    payload = {
        "meta": {
            "count": len(users),
            "locale": args.locale,
            "seed": args.seed,
            "generated_by": "generate_test_data.py",
        },
        "users": users,
    }

    indent = args.indent if args.indent > 0 else None
    json_output = json.dumps(payload, indent=indent, ensure_ascii=False)

    if args.output_file:
        output_path = Path(args.output_file)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json_output, encoding="utf-8")
        print(
            f"Generated {len(users)} user(s) → {output_path.resolve()}",
            file=sys.stderr,
        )
    else:
        print(json_output)

    return 0


if __name__ == "__main__":
    sys.exit(main())
