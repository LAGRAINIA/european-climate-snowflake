#!/bin/bash
#
# Invokes the load_to_snowflake Lambda with a real S3 event payload.
# Used to verify the pipeline end-to-end after any config change.
#
set -e

export AWS_PAGER=""

BUCKET=$(terraform -chdir=terraform output -raw bucket_name)

FILE_KEY=$(aws s3 ls "s3://${BUCKET}/bronze/climate/forecast/" --recursive \
    | grep '\.json$' \
    | head -1 \
    | awk '{print $4}')

if [ -z "$FILE_KEY" ]; then
    echo "ERROR: No JSON files in Bronze. Trigger ingestion first:"
    echo "    aws lambda invoke --function-name fetch_climate_data \\"
    echo "        --cli-binary-format raw-in-base64-out --payload '{}' /tmp/r.json"
    exit 1
fi

echo "==> Testing loader with:"
echo "    Bucket: $BUCKET"
echo "    File:   $FILE_KEY"
echo ""

BUCKET="$BUCKET" FILE_KEY="$FILE_KEY" python3 <<'PYEOF'
import json
import os

event = {
    "Records": [
        {
            "s3": {
                "bucket": {"name": os.environ["BUCKET"]},
                "object": {"key": os.environ["FILE_KEY"]},
            }
        }
    ]
}

with open("/tmp/s3-event.json", "w") as f:
    json.dump(event, f)
PYEOF

aws lambda invoke \
    --function-name load_to_snowflake \
    --cli-binary-format raw-in-base64-out \
    --payload file:///tmp/s3-event.json \
    /tmp/loader-response.json > /dev/null

echo "==> Response:"
cat /tmp/loader-response.json
echo ""

if grep -q '"loaded": [1-9]' /tmp/loader-response.json; then
    echo ""
    echo "SUCCESS - file loaded to RAW.CLIMATE.RAW_FORECAST"
else
    echo ""
    echo "FAILED - inspect the error above"
    echo "For full logs run:"
    echo "    aws logs tail /aws/lambda/load_to_snowflake --since 5m --format short"
    exit 1
fi