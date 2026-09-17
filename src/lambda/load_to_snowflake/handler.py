"""Lambda: triggered by S3 event, INSERTs JSON payload into Snowflake using key-pair auth."""
import json
import os
import boto3
import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION_NAME", "eu-west-1"))

SECRET_NAME = os.environ["SNOWFLAKE_SECRET_NAME"]


def get_snowflake_config():
    resp = secrets.get_secret_value(SecretId=SECRET_NAME)
    return json.loads(resp["SecretString"])


def get_private_key_bytes(pem_str):
    """Parse PEM private key string into DER bytes for Snowflake connector."""
    p_key = serialization.load_pem_private_key(
        pem_str.encode(),
        password=None,
        backend=default_backend(),
    )
    return p_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def lambda_handler(event, context):
    config = get_snowflake_config()

    conn = snowflake.connector.connect(
        account=config["account"],
        user=config["user"],
        private_key=get_private_key_bytes(config["private_key"]),
        role=config["role"],
        warehouse=config["warehouse"],
        database=config["database"],
        schema=config["schema"],
    )

    loaded = 0
    failed = []

    try:
        cur = conn.cursor()
        for record in event.get("Records", []):
            bucket = record["s3"]["bucket"]["name"]
            key = record["s3"]["object"]["key"]

            try:
                print(f"Loading s3://{bucket}/{key}")
                obj = s3.get_object(Bucket=bucket, Key=key)
                payload = json.loads(obj["Body"].read())

                cur.execute(
                    "INSERT INTO RAW_FORECAST (raw_payload, file_name) SELECT PARSE_JSON(%s), %s",
                    (json.dumps(payload), key),
                )
                loaded += 1
            except Exception as e:
                print(f"FAIL {key}: {e}")
                failed.append({"key": key, "error": str(e)})

        conn.commit()
        cur.close()
    finally:
        conn.close()

    return {"loaded": loaded, "failed": len(failed), "details": failed}