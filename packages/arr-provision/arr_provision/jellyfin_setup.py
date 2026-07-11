"""Ensure Jellyfin admin account matches declarative secrets (startup wizard + password sync)."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any, Optional

from arr_provision.common import http_json, read_key_file, wait_for_url

_EMBY_AUTH = (
    'MediaBrowser Client="arr-provision", Device="q958", DeviceId="q958-arr-provision", Version="1.0.0"'
)


def _jellyfin_base() -> str:
    host = os.environ.get("JELLYFIN_HOST", "127.0.0.1")
    port = int(os.environ.get("JELLYFIN_PORT", "8096"))
    return f"http://{host}:{port}"


def _public_info(base_url: str) -> dict[str, Any]:
    status, body = http_json("GET", f"{base_url}/System/Info/Public")
    if status >= 400 or not isinstance(body, dict):
        return {}
    return body


def _authenticate(base_url: str, username: str, password: str) -> Optional[tuple[str, str]]:
    payload = {"Username": username, "Pw": password}
    request = urllib.request.Request(
        f"{base_url}/Users/authenticatebyname",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "X-Emby-Authorization": _EMBY_AUTH,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30.0) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        print(f"Jellyfin auth failed for {username} (HTTP {exc.code})", file=sys.stderr)
        return None

    token = body.get("AccessToken")
    user = body.get("User") or {}
    user_id = user.get("Id")
    if not token or not user_id:
        return None
    return token, user_id


def _set_password(
    base_url: str,
    user_id: str,
    token: str,
    new_password: str,
    *,
    current_password: Optional[str] = None,
) -> bool:
    payload: dict[str, Any] = {"Id": user_id, "NewPw": new_password}
    if current_password:
        payload["CurrentPw"] = current_password
    status, body = http_json(
        "POST",
        f"{base_url}/Users/{user_id}/Password",
        headers={
            "X-Emby-Authorization": f'{_EMBY_AUTH}, Token="{token}"',
            "Content-Type": "application/json",
        },
        body=payload,
    )
    if status >= 400:
        print(f"Jellyfin password update failed (HTTP {status}): {body}", file=sys.stderr)
        return False
    return True


def _complete_startup(base_url: str, username: str, password: str) -> bool:
    payload = {
        "Name": username,
        "Password": password,
        "PasswordConfirm": password,
    }
    request = urllib.request.Request(
        f"{base_url}/Startup/User",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30.0) as response:
            if response.status not in (200, 204):
                print(f"Jellyfin startup user failed (HTTP {response.status})", file=sys.stderr)
                return False
    except urllib.error.HTTPError as exc:
        print(f"Jellyfin startup user failed (HTTP {exc.code})", file=sys.stderr)
        return False

    status, _ = http_json("POST", f"{base_url}/Startup/Complete", body={})
    if status >= 400:
        print(f"Jellyfin startup complete failed (HTTP {status})", file=sys.stderr)
        return False
    print(f"Jellyfin startup wizard completed (user: {username})")
    return True


def setup_jellyfin() -> int:
    base_url = _jellyfin_base()
    username = os.environ.get("JELLYFIN_ADMIN_USER", "admin")
    password_file = os.environ.get("JELLYFIN_ADMIN_PASSWORD_FILE", "/var/lib/secrets/jellyfin_admin_password")

    if not wait_for_url(f"{base_url}/System/Info/Public"):
        print("Jellyfin not reachable — skipped", file=sys.stderr)
        return 0

    password = read_key_file(password_file)
    if not password:
        print("No Jellyfin admin password file — skipped", file=sys.stderr)
        return 0

    public = _public_info(base_url)
    if not public.get("StartupWizardCompleted", False):
        if _complete_startup(base_url, username, password):
            print("Jellyfin admin ready for Seerr")
        return 0

    auth = _authenticate(base_url, username, password)
    if auth:
        print(f"Jellyfin admin password already valid ({username})")
        return 0

    legacy_password = os.environ.get("JELLYFIN_LEGACY_PASSWORD", "")
    if legacy_password:
        legacy_auth = _authenticate(base_url, username, legacy_password)
        if legacy_auth:
            token, user_id = legacy_auth
            if _set_password(base_url, user_id, token, password, current_password=legacy_password):
                print(f"Jellyfin admin password migrated to declarative secret ({username})")
            return 0

    print(
        "Jellyfin wizard completed but declarative password does not match — "
        "set JELLYFIN_LEGACY_PASSWORD once or fix jellyfin_admin_password",
        file=sys.stderr,
    )
    return 0


def main() -> None:
    raise SystemExit(setup_jellyfin())


if __name__ == "__main__":
    main()
