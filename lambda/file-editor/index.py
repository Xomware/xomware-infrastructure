"""
File Editor API — Lambda handler for Command Center.
Provides CRUD operations on .md files in an S3 bucket.
Auth: X-Auth-Hash header must match the stored passphrase hash.
"""

import json
import os
import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]
PASSPHRASE_HASH = os.environ["PASSPHRASE_HASH"]
ALLOWED_ORIGIN = os.environ.get("ALLOWED_ORIGIN", "https://xomware.com")

# Only allow .md files, no path traversal
ALLOWED_EXTENSIONS = {".md", ".json"}
MAX_FILE_SIZE = 100_000  # 100KB


def response(status_code, body, extra_headers=None):
    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
        "Access-Control-Allow-Headers": "Content-Type,X-Auth-Hash",
        "Access-Control-Allow-Methods": "GET,PUT,POST,OPTIONS",
    }
    if extra_headers:
        headers.update(extra_headers)
    return {"statusCode": status_code, "headers": headers, "body": json.dumps(body)}


def authenticate(event):
    """Validate the X-Auth-Hash header matches the stored passphrase hash."""
    headers = event.get("headers", {}) or {}
    auth_hash = headers.get("x-auth-hash", "")
    return auth_hash == PASSPHRASE_HASH


def validate_filename(filename):
    """Ensure filename is safe: no slashes, must end in .md."""
    if not filename:
        return False
    if "/" in filename or "\\" in filename or ".." in filename:
        return False
    if not any(filename.endswith(ext) for ext in ALLOWED_EXTENSIONS):
        return False
    if len(filename) > 100:
        return False
    return True


def list_files():
    """List all .md files in the bucket."""
    try:
        result = s3.list_objects_v2(Bucket=BUCKET, MaxKeys=100)
        files = []
        for obj in result.get("Contents", []):
            key = obj["Key"]
            if any(key.endswith(ext) for ext in ALLOWED_EXTENSIONS):
                files.append(
                    {
                        "name": key,
                        "size": obj["Size"],
                        "lastModified": obj["LastModified"].isoformat(),
                    }
                )
        return response(200, {"files": files})
    except ClientError as e:
        return response(500, {"error": str(e)})


def get_file(filename):
    """Read a file from S3."""
    if not validate_filename(filename):
        return response(400, {"error": "Invalid filename"})
    try:
        obj = s3.get_object(Bucket=BUCKET, Key=filename)
        content = obj["Body"].read().decode("utf-8")
        return response(
            200,
            {
                "name": filename,
                "content": content,
                "lastModified": obj["LastModified"].isoformat(),
            },
        )
    except s3.exceptions.NoSuchKey:
        return response(404, {"error": "File not found"})
    except ClientError as e:
        return response(500, {"error": str(e)})


def put_file(filename, body):
    """Write a file to S3."""
    if not validate_filename(filename):
        return response(400, {"error": "Invalid filename"})
    try:
        data = json.loads(body) if isinstance(body, str) else body
        content = data.get("content", "")
    except (json.JSONDecodeError, AttributeError):
        return response(400, {"error": "Invalid request body"})

    if len(content.encode("utf-8")) > MAX_FILE_SIZE:
        return response(400, {"error": f"File too large (max {MAX_FILE_SIZE} bytes)"})

    try:
        s3.put_object(
            Bucket=BUCKET,
            Key=filename,
            Body=content.encode("utf-8"),
            ContentType="text/markdown",
        )
        return response(200, {"name": filename, "saved": True})
    except ClientError as e:
        return response(500, {"error": str(e)})


def get_agent_status():
    """Read agent-status.json from S3 — the live status of all agents."""
    try:
        obj = s3.get_object(Bucket=BUCKET, Key="agent-status.json")
        content = obj["Body"].read().decode("utf-8")
        data = json.loads(content)
        return response(200, data)
    except s3.exceptions.NoSuchKey:
        return response(200, {
            "updatedAt": None,
            "agents": [
                {"name": "Jarvis", "status": "idle", "task": None},
                {"name": "Boris", "status": "idle", "task": None},
                {"name": "Freddy", "status": "idle", "task": None},
                {"name": "Rocco", "status": "idle", "task": None},
                {"name": "Winston", "status": "idle", "task": None},
                {"name": "Stormy", "status": "idle", "task": None},
                {"name": "Debo", "status": "idle", "task": None},
            ]
        })
    except ClientError as e:
        return response(500, {"error": str(e)})


STATE_BUCKET = os.environ.get("STATE_BUCKET_NAME", "")

# Terraform state attributes that may contain secrets — redact values
SENSITIVE_ATTR_PATTERNS = {
    "password", "secret", "private_key", "access_key", "secret_key",
    "token", "credentials", "api_key", "passphrase", "connection_string",
    "authorization", "cookie", "session",
}


def is_sensitive_key(key):
    """Check if an attribute key looks like it contains sensitive data."""
    key_lower = key.lower()
    return any(pattern in key_lower for pattern in SENSITIVE_ATTR_PATTERNS)


def redact_attributes(attrs):
    """Deep-redact sensitive values from a dict of Terraform attributes."""
    if not isinstance(attrs, dict):
        return attrs
    redacted = {}
    for k, v in attrs.items():
        if is_sensitive_key(k):
            redacted[k] = "**REDACTED**"
        elif isinstance(v, dict):
            redacted[k] = redact_attributes(v)
        elif isinstance(v, list):
            redacted[k] = [
                redact_attributes(item) if isinstance(item, dict) else item
                for item in v
            ]
        else:
            redacted[k] = v
    return redacted


def redact_outputs(outputs):
    """Redact sensitive Terraform outputs."""
    if not isinstance(outputs, dict):
        return outputs
    redacted = {}
    for k, v in outputs.items():
        out = dict(v) if isinstance(v, dict) else {"value": v}
        if out.get("sensitive", False) or is_sensitive_key(k):
            out["value"] = "**REDACTED**"
        redacted[k] = out
    return redacted


def list_workspaces():
    """List Terraform workspaces from the state bucket."""
    if not STATE_BUCKET:
        return response(500, {"error": "State bucket not configured"})
    try:
        result = s3.list_objects_v2(Bucket=STATE_BUCKET, Delimiter="/")
        workspaces = []
        for prefix in result.get("CommonPrefixes", []):
            app_name = prefix["Prefix"].rstrip("/")
            # Get state file metadata
            try:
                head = s3.head_object(
                    Bucket=STATE_BUCKET, Key=f"{app_name}/terraform.tfstate"
                )
                # Parse state to get resource count
                obj = s3.get_object(
                    Bucket=STATE_BUCKET, Key=f"{app_name}/terraform.tfstate"
                )
                state = json.loads(obj["Body"].read().decode("utf-8"))
                resources = state.get("resources", [])
                resource_count = sum(
                    len(r.get("instances", [])) for r in resources
                    if r.get("mode") == "managed"
                )
                workspaces.append({
                    "name": app_name,
                    "resourceCount": resource_count,
                    "lastModified": head["LastModified"].isoformat(),
                    "serial": state.get("serial", 0),
                    "terraformVersion": state.get("terraform_version", "unknown"),
                    "fileSize": head["ContentLength"],
                })
            except ClientError:
                workspaces.append({
                    "name": app_name,
                    "resourceCount": 0,
                    "lastModified": None,
                    "serial": 0,
                    "terraformVersion": "unknown",
                    "fileSize": 0,
                })
        return response(200, {"workspaces": workspaces})
    except ClientError as e:
        return response(500, {"error": str(e)})


def get_workspace_state(app_name):
    """Parse and return a workspace's Terraform state (redacted)."""
    if not STATE_BUCKET:
        return response(500, {"error": "State bucket not configured"})
    # Validate app name — alphanumeric, hyphens, underscores only
    if not app_name or not all(c.isalnum() or c in "-_" for c in app_name):
        return response(400, {"error": "Invalid workspace name"})
    try:
        obj = s3.get_object(
            Bucket=STATE_BUCKET, Key=f"{app_name}/terraform.tfstate"
        )
        state = json.loads(obj["Body"].read().decode("utf-8"))

        # Parse resources
        resources = []
        for r in state.get("resources", []):
            mode = r.get("mode", "managed")
            res_type = r.get("type", "")
            res_name = r.get("name", "")
            module = r.get("module", "")
            provider = r.get("provider", "")
            for inst in r.get("instances", []):
                attrs = inst.get("attributes", {})
                resources.append({
                    "mode": mode,
                    "type": res_type,
                    "name": res_name,
                    "module": module or None,
                    "provider": provider,
                    "attributes": redact_attributes(attrs),
                    "indexKey": inst.get("index_key"),
                })

        # Parse outputs (redacted)
        outputs = redact_outputs(state.get("outputs", {}))

        return response(200, {
            "workspace": app_name,
            "serial": state.get("serial", 0),
            "terraformVersion": state.get("terraform_version", "unknown"),
            "lineage": state.get("lineage", ""),
            "resourceCount": len([r for r in resources if r["mode"] == "managed"]),
            "dataSourceCount": len([r for r in resources if r["mode"] == "data"]),
            "resources": resources,
            "outputs": outputs,
        })
    except s3.exceptions.NoSuchKey:
        return response(404, {"error": f"No state found for workspace '{app_name}'"})

def get_board_status():
    """Read board-status.json from S3 — the live XomBoard state."""
    try:
        obj = s3.get_object(Bucket=BUCKET, Key="board-status.json")
        content = obj["Body"].read().decode("utf-8")
        data = json.loads(content)
        return response(200, data)
    except s3.exceptions.NoSuchKey:
        return response(200, {
            "updatedAt": None,
            "columns": [
                {"id": "dom-todo", "title": "Dom Todo", "icon": "👤", "color": "#3b82f6"},
                {"id": "dom-done", "title": "Dom Done", "icon": "👍", "color": "#22c55e"},
                {"id": "blocked-by-dom", "title": "Blocked by Dom", "icon": "🚫", "color": "#ef4444"},
                {"id": "todo", "title": "Todo", "icon": "📋", "color": "#8a8a9a"},
                {"id": "in-progress", "title": "In Progress", "icon": "🔨", "color": "#00b4d8"},
                {"id": "in-review", "title": "In Review", "icon": "👀", "color": "#ff6b35"},
                {"id": "done", "title": "Done", "icon": "✅", "color": "#00ffab"},
            ],
            "cards": [],
            "archivedCards": []
        })
    except ClientError as e:
        return response(500, {"error": str(e)})


def get_board_inbox():
    """Read board-inbox.json — ideas waiting to be turned into tickets."""
    try:
        obj = s3.get_object(Bucket=BUCKET, Key="board-inbox.json")
        content = obj["Body"].read().decode("utf-8")
        data = json.loads(content)
        return response(200, data)
    except s3.exceptions.NoSuchKey:
        return response(200, {"items": []})
    except ClientError as e:
        return response(500, {"error": str(e)})


def add_board_inbox_item(body):
    """Add an idea to the board inbox for Scribe to process."""
    import datetime
    import uuid
    try:
        data = json.loads(body) if isinstance(body, str) else body
        title = (data.get("title") or "").strip()
        if not title:
            return response(400, {"error": "title is required"})

        description = (data.get("description") or "").strip()
        repo_hint = (data.get("repoHint") or "").strip()

        # Read existing inbox
        try:
            obj = s3.get_object(Bucket=BUCKET, Key="board-inbox.json")
            inbox = json.loads(obj["Body"].read().decode("utf-8"))
        except s3.exceptions.NoSuchKey:
            inbox = {"items": []}

        item = {
            "id": str(uuid.uuid4())[:8],
            "title": title,
            "description": description,
            "repoHint": repo_hint,
            "status": "pending",
            "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "processedAt": None,
            "issuesCreated": [],
        }
        inbox["items"].append(item)

        s3.put_object(
            Bucket=BUCKET,
            Key="board-inbox.json",
            Body=json.dumps(inbox).encode("utf-8"),
            ContentType="application/json",
        )
        return response(201, {"added": True, "item": item})
    except (json.JSONDecodeError, AttributeError):
        return response(400, {"error": "Invalid request body"})
    except ClientError as e:
        return response(500, {"error": str(e)})


def update_board_inbox_item(body):
    """Update an inbox item (used by Scribe to mark as processed)."""
    import datetime
    try:
        data = json.loads(body) if isinstance(body, str) else body
        item_id = data.get("id")
        if not item_id:
            return response(400, {"error": "id is required"})

        obj = s3.get_object(Bucket=BUCKET, Key="board-inbox.json")
        inbox = json.loads(obj["Body"].read().decode("utf-8"))

        for item in inbox["items"]:
            if item["id"] == item_id:
                if "status" in data:
                    item["status"] = data["status"]
                if "issuesCreated" in data:
                    item["issuesCreated"] = data["issuesCreated"]
                if data.get("status") == "processed":
                    item["processedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
                break
        else:
            return response(404, {"error": "Item not found"})

        s3.put_object(
            Bucket=BUCKET,
            Key="board-inbox.json",
            Body=json.dumps(inbox).encode("utf-8"),
            ContentType="application/json",
        )
        return response(200, {"updated": True})
    except s3.exceptions.NoSuchKey:
        return response(404, {"error": "Inbox not found"})
    except (json.JSONDecodeError, AttributeError):
        return response(400, {"error": "Invalid request body"})
    except ClientError as e:
        return response(500, {"error": str(e)})


def move_board_card(body):
    """Move a card to a different column in board-status.json."""
    try:
        data = json.loads(body) if isinstance(body, str) else body
        card_id = data.get("cardId")
        target_column = data.get("targetColumn")
        if not card_id or not target_column:
            return response(400, {"error": "cardId and targetColumn required"})

        # Read current board
        obj = s3.get_object(Bucket=BUCKET, Key="board-status.json")
        board = json.loads(obj["Body"].read().decode("utf-8"))

        # Find and move the card
        moved = False
        for card in board.get("cards", []):
            if card["id"] == card_id:
                card["column"] = target_column
                moved = True
                break

        # Also check archived cards — allow unarchiving
        if not moved:
            for card in board.get("archivedCards", []):
                if card["id"] == card_id:
                    card["column"] = target_column
                    board["cards"].append(card)
                    board["archivedCards"].remove(card)
                    moved = True
                    break

        if not moved:
            return response(404, {"error": "Card not found"})

        # Save updated board
        import datetime
        board["updatedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
        s3.put_object(
            Bucket=BUCKET,
            Key="board-status.json",
            Body=json.dumps(board).encode("utf-8"),
            ContentType="application/json",
        )
        return response(200, {"moved": True, "cardId": card_id, "targetColumn": target_column})
    except s3.exceptions.NoSuchKey:
        return response(404, {"error": "Board not found"})
    except (json.JSONDecodeError, AttributeError):
        return response(400, {"error": "Invalid request body"})
    except ClientError as e:
        return response(500, {"error": str(e)})


def handler(event, context):
    """Main Lambda handler — routes based on HTTP method and path."""
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "")
    path_params = event.get("pathParameters") or {}

    # Auth required for all routes
    if not authenticate(event):
        return response(401, {"error": "Unauthorized"})

    # Route: GET /status/agents
    if method == "GET" and path == "/status/agents":
        return get_agent_status()

    # Route: GET /status/board
    if method == "GET" and path == "/status/board":
        return get_board_status()

    # Route: PUT /status/board/move
    if method == "PUT" and path == "/status/board/move":
        return move_board_card(event.get("body", "{}"))

    # Route: GET /status/board/inbox
    if method == "GET" and path == "/status/board/inbox":
        return get_board_inbox()

    # Route: POST /status/board/inbox
    if method == "POST" and path == "/status/board/inbox":
        return add_board_inbox_item(event.get("body", "{}"))

    # Route: PUT /status/board/inbox
    if method == "PUT" and path == "/status/board/inbox":
        return update_board_inbox_item(event.get("body", "{}"))

    # Route: GET /config/files
    if method == "GET" and path == "/config/files":
        return list_files()

    # Route: GET /config/files/{filename}
    if method == "GET" and "filename" in path_params and path.startswith("/config"):
        return get_file(path_params["filename"])

    # Route: PUT /config/files/{filename}
    if method == "PUT" and "filename" in path_params:
        return put_file(path_params["filename"], event.get("body", "{}"))

    # Route: GET /infra/workspaces
    if method == "GET" and path == "/infra/workspaces":
        return list_workspaces()

    # Route: GET /infra/workspaces/{app}/state
    if method == "GET" and "app" in path_params and path.endswith("/state"):
        return get_workspace_state(path_params["app"])

    return response(404, {"error": "Not found"})
