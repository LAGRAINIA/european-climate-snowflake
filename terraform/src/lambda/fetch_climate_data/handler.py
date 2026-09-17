"""Lambda: fetch hourly weather from Open-Meteo for 30 European capitals."""
import json
import os
import sys
import boto3
import requests
from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, "/var/task/shared")
from cities import CITIES

S3_BUCKET = os.environ["S3_BUCKET"]
OPENMETEO_URL = "https://api.open-meteo.com/v1/forecast"

s3 = boto3.client("s3")


def fetch_city(city):
    params = {
        "latitude": city["lat"],
        "longitude": city["lon"],
        "current_weather": "true",
        "hourly": "temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,weather_code,pressure_msl,cloud_cover",
        "forecast_days": 1,
        "timezone": "UTC",
    }
    for attempt in range(3):
        try:
            r = requests.get(OPENMETEO_URL, params=params, timeout=10)
            r.raise_for_status()
            data = r.json()
            data["_ingestion_ts"] = datetime.now(timezone.utc).isoformat()
            data["_source_city"] = city["name"]
            data["_source_country"] = city["country"]
            return data
        except Exception as e:
            print(f"Attempt {attempt+1} failed for {city['name']}: {e}")
            if attempt == 2:
                raise


def write_to_s3(city_name, payload):
    now = datetime.now(timezone.utc)
    key = (
        f"bronze/climate/forecast/"
        f"year={now.year}/month={now.month:02d}/day={now.day:02d}/hour={now.hour:02d}/"
        f"city={city_name}/data.json"
    )
    s3.put_object(
        Bucket=S3_BUCKET,
        Key=key,
        Body=json.dumps(payload),
        ContentType="application/json",
    )
    return key


def lambda_handler(event, context):
    print(f"Fetching climate for {len(CITIES)} cities")
    results = {"success": [], "failed": []}

    with ThreadPoolExecutor(max_workers=10) as pool:
        futures = {pool.submit(fetch_city, c): c for c in CITIES}
        for fut in as_completed(futures):
            city = futures[fut]
            try:
                payload = fut.result()
                key = write_to_s3(city["name"], payload)
                results["success"].append({"city": city["name"], "key": key})
                print(f"OK {city['name']}")
            except Exception as e:
                results["failed"].append({"city": city["name"], "error": str(e)})
                print(f"FAIL {city['name']}: {e}")

    if len(results["failed"]) > len(CITIES) * 0.2:
        raise Exception(f"Too many failures: {len(results['failed'])}/{len(CITIES)}")

    return {
        "cities_processed": len(results["success"]),
        "cities_failed": len(results["failed"]),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }