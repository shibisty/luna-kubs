import string
import sys
import tools.random as random


def main():
    if len(sys.argv) < 3:
        print("Usage:")
        print("  python my.py random:key <length>")
        sys.exit(1)

    command = sys.argv[1]

    if command == "random:key":
        try:
            length = int(sys.argv[2])
        except ValueError:
            print("Length must be an integer.")
            sys.exit(1)

        print(random.key_generator(length))
    else:
        print(f"Unknown command: {command}")


if __name__ == "__main__":
    main()
