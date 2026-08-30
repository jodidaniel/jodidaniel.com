#!/usr/bin/env bash
#
# Manage the PRIVATE S3 media archive that holds the `_media` PDFs.
#
# The archive exists because this repo is PUBLIC: a committed PDF of a
# third-party article is world-readable at raw.githubusercontent.com whatever
# the website renders, and git history keeps it after a `git rm`. So the bytes
# live in a private bucket, `_media/*.md` names the object in
# `pdf_archive_file`, and `pdf_public` decides whether a deploy publishes a copy
# to the website. See docs/CONTENT-MODEL.md, "Archived PDFs".
#
#   bash scripts/media-archive.sh list
#   bash scripts/media-archive.sh put   <file.pdf> [object-name]
#   bash scripts/media-archive.sh get   <object-name> [dest]
#   bash scripts/media-archive.sh link  <object-name> [seconds]   # presigned URL
#   bash scripts/media-archive.sh audit                           # keys vs objects
#
# Requires the AWS CLI and credentials that can read/write the archive bucket.
# MEDIA_ARCHIVE_BUCKET overrides the default derived from the apex domain.
set -euo pipefail

cd "$(dirname "$0")/.."

BUCKET="${MEDIA_ARCHIVE_BUCKET:-jodidaniel-com-media-archive}"
PREFIX="media-pdfs"

need_aws() {
  command -v aws >/dev/null || { echo "aws CLI not found on PATH" >&2; exit 2; }
}

case "${1:-}" in
  list)
    need_aws
    aws s3 ls "s3://${BUCKET}/${PREFIX}/"
    ;;
  put)
    need_aws
    src="${2:?usage: put <file.pdf> [object-name]}"
    name="${3:-$(basename "$src")}"
    case "$name" in *.pdf) ;; *) echo "object name must end in .pdf" >&2; exit 2 ;; esac
    # No public-read ACL, ever: the bucket blocks public access and the ONLY
    # sanctioned route to the public web is the deploy step, which copies an
    # object out only when its entry carries `pdf_public: true`.
    aws s3 cp "$src" "s3://${BUCKET}/${PREFIX}/${name}" --content-type application/pdf
    echo "uploaded ${name} — now set pdf_archive_file: \"${name}\" on the media item"
    ;;
  get)
    need_aws
    name="${2:?usage: get <object-name> [dest]}"
    aws s3 cp "s3://${BUCKET}/${PREFIX}/${name}" "${3:-./${name}}"
    ;;
  link)
    need_aws
    name="${2:?usage: link <object-name> [seconds]}"
    aws s3 presign "s3://${BUCKET}/${PREFIX}/${name}" --expires-in "${3:-900}"
    ;;
  audit)
    need_aws
    # Every key a media item names must exist in the archive, or the item is
    # pointing at nothing — and ticking pdf_public would publish a 404.
    missing=0
    while IFS= read -r key; do
      if aws s3 ls "s3://${BUCKET}/${PREFIX}/${key}" >/dev/null 2>&1; then
        printf 'present  %s\n' "$key"
      else
        printf 'MISSING  %s\n' "$key"; missing=$((missing + 1))
      fi
    done < <(grep -hoE '^pdf_archive_file:[[:space:]]*"[^"]+"' _media/*.md | sed 's/.*"\(.*\)"/\1/' | sort -u)
    [ "$missing" -eq 0 ] || { echo "$missing archive object(s) missing" >&2; exit 1; }
    ;;
  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
