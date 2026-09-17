#!/bin/bash
set -e

echo "==> Building fetch_climate_data Lambda..."

rm -f dist/fetch_climate_data.zip dist/requests-layer.zip
rm -rf build/fetch_climate_data build/requests-layer
mkdir -p dist build/fetch_climate_data

cp src/lambda/fetch_climate_data/handler.py build/fetch_climate_data/
mkdir -p build/fetch_climate_data/shared
cp src/shared/cities.py build/fetch_climate_data/shared/
touch build/fetch_climate_data/shared/__init__.py

(cd build/fetch_climate_data && zip -r ../../dist/fetch_climate_data.zip .)

echo "==> Building requests layer via Docker (Python 3.12)..."
mkdir -p build/requests-layer
docker run --rm \
    --platform linux/amd64 \
    --entrypoint /bin/bash \
    -v "$(pwd)/build/requests-layer:/build" \
    -v "$(pwd)/src/lambda/fetch_climate_data:/src" \
    public.ecr.aws/lambda/python:3.12 \
    -c "pip install --platform manylinux2014_x86_64 --only-binary=:all: --target /build/python/ -r /src/requirements.txt"

(cd build/requests-layer && zip -r ../../dist/requests-layer.zip python/)

echo "Done"
ls -la dist/