# Snowflake Setup

Run these in Snowsight in order, once per Snowflake account.

1. `01_warehouses.sql` — creates LOAD_WH and TRANSFORM_WH
2. `02_databases.sql` — creates RAW and ANALYTICS databases with schemas
3. `03_roles.sql` — creates LOADER_ROLE and TRANSFORMER_ROLE with grants
4. `04_users.sql` — creates LOADER_USER (SERVICE) and DBT_USER

After running these, run `scripts/setup-snowflake-keypair.sh` from the project root to generate the RSA key pair, register the public key with LOADER_USER, and store the private key in AWS Secrets Manager.

## Why LOADER_USER uses key-pair auth

Snowflake enforces MFA on all PERSON-type users (as of April 2025). Service accounts can't respond to MFA prompts, so we use:
- `TYPE = SERVICE` — exempts from MFA policies
- RSA key-pair auth — the only auth method allowed for SERVICE users

This is Snowflake's recommended pattern for service accounts.