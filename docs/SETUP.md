# Setup Guide

Complete zero-to-running instructions for the climate analytics platform.

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity` works)
- Terraform 1.9+
- Docker Desktop running
- Python 3.12+
- Snowflake account (trial at https://signup.snowflake.com/)
- GitHub account

## 1. AWS bootstrap

Create the Terraform state bucket (one-time):

```bash
aws s3 mb s3://climate-snowflake-tfstate-anass --region eu-west-1
aws s3api put-bucket-versioning \
    --bucket climate-snowflake-tfstate-anass \
    --versioning-configuration Status=Enabled
```

## 2. Snowflake setup

In Snowsight, run the SQL scripts in `snowflake/setup/` in order:

- `01_warehouses.sql`
- `02_databases.sql`
- `03_roles.sql`
- `04_users.sql`

Uncomment and edit the final line in `04_users.sql` to grant `TRANSFORMER_ROLE` to your admin user (find yours with `SELECT CURRENT_USER()`).

Get your account identifier for later:

```sql
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();
```

Save this value — you'll use it as `SNOWFLAKE_ACCOUNT`.

## 3. Terraform variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform/terraform.tfvars` with your values. The `snowflake_password` field is a placeholder — the loader uses key-pair auth (Step 5), not password auth.

## 4. Initial deploy

Build Lambda zips:

```bash
./scripts/deploy_lambda.sh
./scripts/deploy_loader.sh
```

Apply Terraform:

```bash
cd terraform
terraform init
terraform apply -auto-approve
cd ..
```

This creates:
- S3 datalake bucket
- Ingestion Lambda + hourly EventBridge schedule
- Loader Lambda + S3 event trigger
- Secrets Manager entry (placeholder)
- IAM roles

## 5. Snowflake key-pair authentication for LOADER_USER

Snowflake enforces MFA on PERSON users, so LOADER_USER needs key-pair auth. Run the setup script:

```bash
SNOWFLAKE_ACCOUNT=YOUR-ORG-ACCOUNT ./scripts/setup-snowflake-keypair.sh
```

The script:
1. Generates a 2048-bit RSA key pair in `~/.snowflake-keys/`
2. Prints the SQL to run in Snowsight (registers the public key with LOADER_USER)
3. Waits for you to confirm the SQL ran
4. Updates the AWS secret with the private key

Then force the Lambda to reload:

```bash
cd terraform
terraform taint 'module.lambda_loader.aws_lambda_function.load_to_snowflake'
terraform apply -auto-approve
cd ..
```

## 6. Verify end-to-end

Trigger the ingestion Lambda:

```bash
aws lambda invoke \
    --function-name fetch_climate_data \
    --cli-binary-format raw-in-base64-out \
    --payload '{}' /tmp/r.json && cat /tmp/r.json
```

Wait 60 seconds for the S3 events to fire loaders, then check Snowflake:

```sql
USE ROLE LOADER_ROLE;
USE WAREHOUSE LOAD_WH;
SELECT COUNT(*), MAX(loaded_at) FROM RAW.CLIMATE.RAW_FORECAST;
```

You should see rows for the 30 cities.

You can also test manually with:

```bash
./scripts/test-loader.sh
```

## Troubleshooting

### "Incorrect username or password" from Lambda

The password path is broken because MFA is required. Confirm LOADER_USER is `TYPE = SERVICE` and has a key-pair registered:

```sql
DESC USER LOADER_USER;
-- TYPE should be SERVICE
-- HAS_KEYPAIR should be true
```

If not, re-run `scripts/setup-snowflake-keypair.sh`.

### "Unable to import module 'handler'" in Lambda logs

The Lambda layer was built for the wrong platform. Rebuild with:

```bash
./scripts/deploy_loader.sh
```

The deploy script forces `--platform linux/amd64` in Docker.

### "404 Not Found" from Snowflake

The `snowflake_account` value in `terraform.tfvars` doesn't match a real Snowflake account. Get the correct value from Snowsight:

```sql
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();
```

Update tfvars, then re-run `scripts/setup-snowflake-keypair.sh` and force redeploy the Lambda.