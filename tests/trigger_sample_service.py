#!/usr/bin/env python3

from urllib.request import Request, urlopen


def main() -> None:
    for i in range(1, 100):
        request = Request(
            f"http://kong-aws-alb-1918001745.ap-southeast-1.elb.amazonaws.com:8000/get?i={i}",
            headers={"Host": "example.com"},
        )
        with urlopen(request) as response:
            response.read()


if __name__ == "__main__":
    main()
