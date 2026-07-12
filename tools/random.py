import secrets
import string
import random

def key_generator(length=32):
    if length < 3:
        raise ValueError("Length must be at least 3")

    chars = [
        secrets.choice(string.ascii_lowercase),
        secrets.choice(string.ascii_uppercase),
        secrets.choice(string.digits),
    ]

    alphabet = string.ascii_letters + string.digits

    chars.extend(
        secrets.choice(alphabet)
        for _ in range(length - 3)
    )

    random.SystemRandom().shuffle(chars)

    return ''.join(chars)
