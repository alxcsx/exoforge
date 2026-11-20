---
nav: Overview
summary: Binary assets with metadata.
---
# File bucket

Binary assets with metadata. A bucket is `public` or `private`; private buckets need staff access or a signed URL.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `upload_file` | `studio` | `filename`, `bucket`, `content`, `content_type`, `metadata` | Stores a file in a specified bucket from raw binary or base64 content. |
| `get_file_info` | `studio` | `id`, `bucket` | Retrieves metadata and local storage path for a file. |
| `read_file` | `studio` | `id`, `bucket` | Reads raw binary content of a file. |
| `list_files` | `studio` | `bucket`, `limit`, `offset` | Lists stored files within a bucket or across all buckets. |
| `list_buckets` | `studio` | - | Lists all storage buckets with their visibility (`public` or `private`). |
| `set_bucket_visibility` | `studio` | `bucket`, `visibility` | - |
| `update_file` | `studio` | `id`, `bucket`, `filename`, `content`, `content_type`, `metadata` | Modifies an existing file's name, metadata, or content. |
| `signed_url` | `server` | `id`, `bucket`, `ttl_seconds` | - |
| `authorize_download` | `server` | `bucket`, `id`, `exp`, `sig` | Whether an unauthenticated download may be served: a public bucket, or a valid signed URL. |
| `delete_file` | `studio` | `id`, `bucket` | Deletes a stored file. |

## Events

It declares no events.

## Settings

- `config :exoforge_std_file_bucket, :public_buckets`
- `config :exoforge_std_file_bucket, :sdk_dist_dir`
- `config :exoforge_std_file_bucket, :storage_dir`
- `config :exoforge_std_file_bucket, :url_secret`

## Data

It creates no tables of its own.
