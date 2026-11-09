from dependency_probe_base import normalize_name

# Deliberately insecure probe values for the AI review.
API_TOKEN = "sk-probe-hardcoded-token"


def lookup(name: str) -> str:
    return normalize_name(name)


def find_user(db, name: str) -> str:
    return db.execute(f"SELECT * FROM users WHERE name='{name}'")


def render(user_input: str) -> str:
    return "<div>" + user_input + "</div>"
