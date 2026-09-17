#!/bin/bash
#
# Sets up RSA key-pair authentication for LOADER_USER in Snowflake.
# - Generates 2048-bit RSA key pair (stored in ~/.snowflake-keys/)
# - Prints the ALTER USER SQL for you to run in Snowsight
# - Updates the climate/snowflake secret in AWS Secrets Manager with the private key
#
# Run this AFTER the Snowflake SQL setup (snowflake/setup/) completes.
# Requires: openssl, aws CLI, python3, jq
#
set -e

KEY_DIR="${HOME}/.snowflake-keys"
KEY_NAME="climate-loader"
PRIVATE_KEY="${KEY_DIR}/${KEY_NAME}.p8"
PUBLIC_KEY="${KEY_DIR}/${KEY_NAME}.pub"

SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"
SECRET_NAME="${SNOWFLAKE_SECRET_NAME:-climate/snowflake}"
AWS_REGION="${AWS_REGION:-eu-west-1}"

# ---- Prerequisites ----

for cmd in openssl aws python3; do
    if ! command -v "$cmd" > /dev/null; then
        echo "ERROR: $cmd is required but not installed"
        exit 1
    fi
done

if [ -z "$SNOWFLAKE_ACCOUNT" ]; then
    echo "ERROR: SNOWFLAKE_ACCOUNT env var required."
    echo ""
    echo "Get your account identifier by running in Snowsight:"
    echo "  SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();"
    echo ""
    echo "Then re-run this script with:"
    echo "  SNOWFLAKE_ACCOUNT=ORG-ACCOUNT ./scripts/setup-snowflake-keypair.sh"
    exit 1
fi

echo "==> Setting up Snowflake key-pair authentication"
echo "    Account: $SNOWFLAKE_ACCOUNT"
echo "    Secret:  $SECRET_NAME"
echo "    Region:  $AWS_REGION"
echo ""

# ---- Generate key pair ----

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

if [ -f "$PRIVATE_KEY" ]; then
    echo "==> Existing key found at $PRIVATE_KEY"
    read -p "    Regenerate? This invalidates the current key in Snowflake. [y/N] " yn
    if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
        rm -f "$PRIVATE_KEY" "$PUBLIC_KEY"
    fi
fi

if [ ! -f "$PRIVATE_KEY" ]; then
    echo "==> Generating new 2048-bit RSA key pair"
    openssl genrsa 2048 2>/dev/null | \
        openssl pkcs8 -topk8 -inform PEM -out "$PRIVATE_KEY" -nocrypt
    openssl rsa -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY" 2>/dev/null
    chmod 600 "$PRIVATE_KEY"
    echo "    Private key: $PRIVATE_KEY"
    echo "    Public key:  $PUBLIC_KEY"
else
    echo "==> Reusing existing key pair at $KEY_DIR"
fi

# ---- Show public key SQL ----

PUBLIC_KEY_ONE_LINE=$(grep -v -- "-----" "$PUBLIC_KEY" | tr -d '\n')

echo ""
echo "==> Step 1: Register public key with LOADER_USER in Snowsight"
echo "    Copy and run this SQL as ACCOUNTADMIN:"
echo ""
cat <<EOF
    -----------------------------------------------------------
    USE ROLE ACCOUNTADMIN;
    ALTER USER LOADER_USER SET RSA_PUBLIC_KEY='${PUBLIC_KEY_ONE_LINE}';
    ALTER USER LOADER_USER UNSET PASSWORD;
    DESC USER LOADER_USER;
    -----------------------------------------------------------
EOF
echo ""
read -p "    Press ENTER after running the SQL and confirming HAS_KEYPAIR = true..."

# ---- Update AWS secret ----

echo ""
echo "==> Step 2: Update Secrets Manager with private key"

python3 <<PYEOF
import json
import subprocess
import sys

with open("$PRIVATE_KEY") as f:
    private_key = f.read()

secret = {
    "account": "$SNOWFLAKE_ACCOUNT",
    "user": "LOADER_USER",
    "private_key": private_key,
    "role": "LOADER_ROLE",
    "warehouse": "LOAD_WH",
    "database": "RAW",
    "schema": "CLIMATE",
}

result = subprocess.run(
    [
        "aws", "secretsmanager", "put-secret-value",
        "--secret-id", "$SECRET_NAME",
        "--secret-string", json.dumps(secret),
        "--region", "$AWS_REGION",
    ],
    capture_output=True,
    text=True,
)

if result.returncode != 0:
    print(f"ERROR updating secret: {result.stderr}")
    sys.exit(1)

print(f"    Secret $SECRET_NAME updated")
PYEOF

echo ""
echo "==> Step 3: Force Lambda to pick up the new secret"
echo "    Run:"
echo ""
echo "        cd terraform"
echo "        terraform taint 'module.lambda_loader.aws_lambda_function.load_to_snowflake'"
echo "        terraform apply -auto-approve"
echo "        cd .."
echo ""
echo "==> Done. Test the loader with scripts/test-loader.sh"