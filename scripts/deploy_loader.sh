#!/bin/bash
set -e

echo "==> Building load_to_snowflake Lambda..."

rm -f dist/load_to_snowflake.zip dist/snowflake-connector-layer.zip
rm -rf build/load_to_snowflake build/snowflake-layer
mkdir -p dist build/load_to_snowflake

cp src/lambda/load_to_snowflake/handler.py build/load_to_snowflake/

(cd build/load_to_snowflake && zip -r ../../dist/load_to_snowflake.zip .)

echo "==> Building Snowflake connector layer for Lambda (linux/amd64)..."
mkdir -p build/snowflake-layer
docker run --rm \
    --platform linux/amd64 \
    --entrypoint /bin/bash \
    -v "$(pwd)/build/snowflake-layer:/build" \
    -v "$(pwd)/src/lambda/load_to_snowflake:/src" \
    public.ecr.aws/lambda/python:3.12 \
    -c "pip install --platform manylinux2014_x86_64 --only-binary=:all: --target /build/python/ -r /src/requirements.txt"

(cd build/snowflake-layer && zip -r ../../dist/snowflake-connector-layer.zip python/)

echo ""
echo "Done"
ls -la dist/