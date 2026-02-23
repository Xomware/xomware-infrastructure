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
ALLOWED_EXTENSIONS = {".md"}
MAX_FILE_SIZE = 100_000  # 100KB


def response(status_code, body, extra_headers=None):
    headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
        "Access-Control-Allow-Headers": "Content-Type,X-Auth-Hash",
        "Access-Control-Allow-Methods": "GET,PUT,OPTIONS",
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


def handler(event, context):
    """Main Lambda handler — routes based on HTTP method and path."""
    # Auth check
    if not authenticate(event):
        return response(401, {"error": "Unauthorized"})

    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    path = event.get("rawPath", "")
    path_params = event.get("pathParameters") or {}

    # Route: GET /config/files
    if method == "GET" and path == "/config/files":
        return list_files()

    # Route: GET /config/files/{filename}
    if method == "GET" and "filename" in path_params:
        return get_file(path_params["filename"])

    # Route: PUT /config/files/{filename}
    if method == "PUT" and "filename" in path_params:
        return put_file(path_params["filename"], event.get("body", "{}"))

    return response(404, {"error": "Not found"})
