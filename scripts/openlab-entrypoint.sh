#!/bin/sh
set -e

nginx

cd /app/backend
exec uvicorn main:app --host 0.0.0.0 --port 8000
