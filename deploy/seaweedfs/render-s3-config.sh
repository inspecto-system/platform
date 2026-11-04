#!/bin/sh
# Renders the SeaweedFS S3 identities from environment variables:
# each service may access only its own bucket (SECURITY.md §7).
set -eu
cat <<JSON
{
  "identities": [
    {
      "name": "media-service",
      "credentials": [{"accessKey": "${S3_MEDIA_ACCESS_KEY}", "secretKey": "${S3_MEDIA_SECRET_KEY}"}],
      "actions": ["Read:photos", "Write:photos", "List:photos", "Tagging:photos"]
    },
    {
      "name": "report-service",
      "credentials": [{"accessKey": "${S3_REPORT_ACCESS_KEY}", "secretKey": "${S3_REPORT_SECRET_KEY}"}],
      "actions": ["Read:reports", "Write:reports", "List:reports", "Tagging:reports"]
    },
    {
      "name": "admin",
      "credentials": [{"accessKey": "${S3_ADMIN_ACCESS_KEY}", "secretKey": "${S3_ADMIN_SECRET_KEY}"}],
      "actions": ["Admin", "Read", "Write", "List", "Tagging"]
    }
  ]
}
JSON
