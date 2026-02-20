"""
Local filesystem storage layer that mimics the AWS S3 API.

The "bucket" parameter in every method maps to a subdirectory inside the
data directory (e.g. ``audio``, ``transcripts``, ``summaries``).  This
allows the rest of the codebase to be written as though it were talking to
S3, making the eventual migration to real S3 straightforward.

All paths are resolved relative to the data directory configured in
``config.py``.
"""

import json
import logging
import os
import shutil
from pathlib import Path
from typing import Any, List, Optional, Union

from config import load_config

logger = logging.getLogger(__name__)


def _bucket_root(bucket: str) -> Path:
    """Return the absolute directory for a given *bucket*.

    If the directory does not yet exist it is created automatically.

    Args:
        bucket: Logical bucket name (e.g. ``"audio"``, ``"transcripts"``).

    Returns:
        A :class:`pathlib.Path` pointing to the bucket directory.
    """
    cfg = load_config()
    root = Path(cfg["data_dir"]) / bucket
    root.mkdir(parents=True, exist_ok=True)
    return root


def _resolve(bucket: str, key: str) -> Path:
    """Resolve a bucket + key to an absolute filesystem path.

    Intermediate directories are created as needed.

    Args:
        bucket: Logical bucket name.
        key: Object key (may contain ``/`` separators for nested paths).

    Returns:
        The absolute :class:`pathlib.Path` for the object.
    """
    full = _bucket_root(bucket) / key
    full.parent.mkdir(parents=True, exist_ok=True)
    return full


# ---------------------------------------------------------------------------
# Public API (S3-style)
# ---------------------------------------------------------------------------

def put_object(bucket: str, key: str, body: Union[str, bytes, dict]) -> str:
    """Write an object to the local data directory.

    If *body* is a ``dict`` it is serialised as JSON.  Strings are written
    as UTF-8 text; ``bytes`` are written in binary mode.

    Args:
        bucket: Logical bucket name.
        key: Object key.
        body: The data to write.

    Returns:
        The absolute path of the written file.
    """
    path = _resolve(bucket, key)

    if isinstance(body, (dict, list)):
        body = json.dumps(body, indent=2, default=str)

    if isinstance(body, str):
        path.write_text(body, encoding="utf-8")
    elif isinstance(body, bytes):
        path.write_bytes(body)
    else:
        path.write_text(str(body), encoding="utf-8")

    logger.debug("put_object  bucket=%s  key=%s  -> %s", bucket, key, path)
    return str(path)


def get_object(bucket: str, key: str, as_json: bool = False) -> Optional[Any]:
    """Read an object from the local data directory.

    Args:
        bucket: Logical bucket name.
        key: Object key.
        as_json: If ``True``, parse the file contents as JSON and return
            the resulting Python object.

    Returns:
        File contents as a string (or parsed JSON), or ``None`` if the
        object does not exist.
    """
    path = _resolve(bucket, key)
    if not path.exists():
        logger.debug("get_object  bucket=%s  key=%s  -> NOT FOUND", bucket, key)
        return None

    content = path.read_text(encoding="utf-8")
    logger.debug("get_object  bucket=%s  key=%s  -> %d bytes", bucket, key, len(content))

    if as_json:
        try:
            return json.loads(content)
        except json.JSONDecodeError as exc:
            logger.warning("get_object JSON parse error for %s/%s: %s", bucket, key, exc)
            return None

    return content


def get_object_bytes(bucket: str, key: str) -> Optional[bytes]:
    """Read an object as raw bytes.

    Args:
        bucket: Logical bucket name.
        key: Object key.

    Returns:
        Raw bytes, or ``None`` if the object does not exist.
    """
    path = _resolve(bucket, key)
    if not path.exists():
        return None
    return path.read_bytes()


def list_objects(bucket: str, prefix: str = "") -> List[str]:
    """List object keys in a bucket, optionally filtered by prefix.

    Args:
        bucket: Logical bucket name.
        prefix: Only return keys that start with this prefix.

    Returns:
        A sorted list of keys relative to the bucket root.
    """
    root = _bucket_root(bucket)
    keys: List[str] = []

    for dirpath, _dirnames, filenames in os.walk(root):
        for fname in filenames:
            full = Path(dirpath) / fname
            key = str(full.relative_to(root))
            if key.startswith(prefix):
                keys.append(key)

    keys.sort()
    logger.debug(
        "list_objects  bucket=%s  prefix=%s  -> %d keys", bucket, prefix, len(keys)
    )
    return keys


def delete_object(bucket: str, key: str) -> bool:
    """Delete an object from the local data directory.

    Args:
        bucket: Logical bucket name.
        key: Object key.

    Returns:
        ``True`` if the file was deleted, ``False`` if it did not exist.
    """
    path = _resolve(bucket, key)
    if path.exists():
        path.unlink()
        logger.debug("delete_object  bucket=%s  key=%s  -> DELETED", bucket, key)
        return True
    logger.debug("delete_object  bucket=%s  key=%s  -> NOT FOUND", bucket, key)
    return False


def object_exists(bucket: str, key: str) -> bool:
    """Check whether an object exists.

    Args:
        bucket: Logical bucket name.
        key: Object key.

    Returns:
        ``True`` if the object exists on disk.
    """
    path = _resolve(bucket, key)
    return path.exists()


def delete_bucket(bucket: str) -> bool:
    """Remove an entire bucket directory and all its contents.

    Use with caution -- this is the equivalent of deleting an S3 bucket.

    Args:
        bucket: Logical bucket name.

    Returns:
        ``True`` if the directory was removed.
    """
    root = _bucket_root(bucket)
    if root.exists():
        shutil.rmtree(root)
        logger.info("delete_bucket  bucket=%s  -> DELETED", bucket)
        return True
    return False
