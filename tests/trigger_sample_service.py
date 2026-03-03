#!/usr/bin/env python3

from urllib.request import Request, urlopen


def main() -> None:
    for i in range(1, 1000):
        request = Request(
            f"http://localhost:8000/get?i={i}",
            headers={"Host": "example.com"},
        )
        with urlopen(request) as response:
            response.read()


if __name__ == "__main__":
    main()
