"""
Deploys the backend to the VPS over SSH/SFTP using paramiko.
Run: python deploy.py
"""
import os
import stat
import paramiko

# ── Server config ─────────────────────────────────────────────────────────────
HOST = "153.127.16.117"
PORT = 22
USER = "root"
PASSWORD = "7xfqOVS,j2na=H2m"
REMOTE_DIR = "/opt/messaging-backend"

# ── Local source ──────────────────────────────────────────────────────────────
LOCAL_BACKEND = os.path.join(os.path.dirname(__file__), "backend")

# Files/dirs to skip
SKIP = {"__pycache__", "messaging.db", "test_db.py",
        "test_flow.py", ".env", "uploads", "public"}

# ── Helpers ───────────────────────────────────────────────────────────────────

def run(ssh: paramiko.SSHClient, cmd: str, check=True):
    print(f"  $ {cmd}")
    _, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if out:
        print(f"    {out}")
    if err:
        print(f"    [err] {err}")
    return out


def sftp_upload_dir(sftp: paramiko.SFTPClient, local_dir: str, remote_dir: str):
    """Recursively upload a local directory to remote."""
    try:
        sftp.mkdir(remote_dir)
    except OSError:
        pass  # already exists

    for item in os.listdir(local_dir):
        if item in SKIP or item.startswith("."):
            continue
        local_path = os.path.join(local_dir, item)
        remote_path = f"{remote_dir}/{item}"
        if os.path.isdir(local_path):
            sftp_upload_dir(sftp, local_path, remote_path)
        else:
            print(f"    uploading {remote_path}")
            sftp.put(local_path, remote_path)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    print(f"\n=== Connecting to {HOST} ===")
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    ssh.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=30)
    print("Connected!\n")

    # 1. Install system deps
    print("=== Installing system packages ===")
    run(ssh, "apt-get update -qq")
    run(ssh, "apt-get install -y -qq python3 python3-pip python3-venv")

    # 2. Create project dir
    print("\n=== Creating project directory ===")
    run(ssh, f"mkdir -p {REMOTE_DIR}/uploads {REMOTE_DIR}/public")

    # 3. Upload files
    print("\n=== Uploading backend files ===")
    sftp = ssh.open_sftp()
    sftp_upload_dir(sftp, LOCAL_BACKEND, REMOTE_DIR)

    # 4. Write .env
    print("\n=== Writing .env ===")
    env_content = "PORT=3000\n"
    with sftp.open(f"{REMOTE_DIR}/.env", "w") as f:
        f.write(env_content)

    sftp.close()

    # 5. Create virtualenv and install deps
    print("\n=== Setting up Python venv ===")
    run(ssh, f"python3 -m venv {REMOTE_DIR}/venv")
    run(ssh, f"{REMOTE_DIR}/venv/bin/pip install --upgrade pip -q")
    run(ssh, f"{REMOTE_DIR}/venv/bin/pip install -r {REMOTE_DIR}/requirements.txt -q")

    # 6. Create systemd service
    print("\n=== Creating systemd service ===")
    service = f"""[Unit]
Description=Messaging App Backend
After=network.target

[Service]
WorkingDirectory={REMOTE_DIR}
ExecStart={REMOTE_DIR}/venv/bin/uvicorn main:socket_app --host 0.0.0.0 --port 3000
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
"""
    sftp = ssh.open_sftp()
    with sftp.open("/etc/systemd/system/messaging.service", "w") as f:
        f.write(service)
    sftp.close()

    run(ssh, "systemctl daemon-reload")
    run(ssh, "systemctl enable messaging")
    run(ssh, "systemctl restart messaging")

    # 7. Open firewall port 3000
    print("\n=== Opening port 3000 ===")
    run(ssh, "ufw allow 3000/tcp || true")

    # 8. Check status
    print("\n=== Service status ===")
    run(ssh, "systemctl status messaging --no-pager -l")

    ssh.close()
    print(f"\n✓ Done! Backend running at http://{HOST}:3000")


if __name__ == "__main__":
    main()
