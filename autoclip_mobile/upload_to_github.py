"""
Automated GitHub Uploader for AutoClip Mobile.
Uploads all 21 files and directory structures directly to your GitHub repository
using the GitHub REST API (no Git CLI installation required).
"""

import base64
import json
import os
import sys
from pathlib import Path
import urllib.request
import urllib.error

ROOT_DIR = Path(__file__).resolve().parent

EXCLUDE_NAMES = {
    ".git",
    "upload_to_github.py",
    "__pycache__",
    ".DS_Store",
}

def upload_file(token: str, owner: str, repo: str, rel_path: str, file_path: Path):
    with open(file_path, "rb") as f:
        content_b64 = base64.b64encode(f.read()).decode("utf-8")

    api_url = f"https://api.github.com/repos/{owner}/{repo}/contents/{rel_path}"
    
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "AutoClip-Uploader",
    }

    # Check if file already exists to get SHA for update
    sha = None
    try:
        req = urllib.request.Request(api_url, headers=headers)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            sha = data.get("sha")
    except urllib.error.HTTPError as e:
        if e.code != 404:
            print(f"  Warning checking {rel_path}: {e}")

    payload = {
        "message": f"Add {rel_path}",
        "content": content_b64,
        "branch": "main"
    }
    if sha:
        payload["sha"] = sha

    req = urllib.request.Request(
        api_url,
        data=json.dumps(payload).encode("utf-8"),
        headers=headers,
        method="PUT"
    )

    try:
        with urllib.request.urlopen(req) as resp:
            if resp.status in (200, 201):
                print(f"  [OK] Uploaded: {rel_path}")
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8", errors="ignore")
        print(f"  [FAIL] {rel_path}: {e.code} - {err_msg}")

def main():
    print("=" * 60)
    print("  AutoClip Mobile -> GitHub 1-Click Uploader")
    print("=" * 60)
    print("This will upload all 21 files (with folders) to your GitHub repo.\n")

    owner = input("Enter your GitHub Username: ").strip()
    if not owner:
        print("Username cannot be empty.")
        return

    repo = input("Enter your GitHub Repository Name (e.g. autoclip-mobile): ").strip()
    if not repo:
        print("Repository name cannot be empty.")
        return

    print("\nTo upload without Git, you need a GitHub Personal Access Token.")
    print("1. Go to https://github.com/settings/tokens/new")
    print("2. Note: 'autoclip', check 'repo' checkbox, click 'Generate token'.")
    token = input("Paste your GitHub Token: ").strip()
    if not token:
        print("Token cannot be empty.")
        return

    print("\nUploading project files...")
    count = 0
    for root, dirs, files in os.walk(ROOT_DIR):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_NAMES]
        for f in files:
            if f in EXCLUDE_NAMES or f.endswith(".pyc"):
                continue
            full_path = Path(root) / f
            rel_path = full_path.relative_to(ROOT_DIR).as_posix()
            upload_file(token, owner, repo, rel_path, full_path)
            count += 1

    print(f"\nAll {count} files uploaded successfully!")
    print(f"Now go to: https://github.com/{owner}/{repo}/actions")
    print("The 'Build Release APK' workflow will start automatically!")

if __name__ == "__main__":
    main()
