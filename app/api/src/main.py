import json
import os
import boto3
import logging

from fastapi import FastAPI
from aws_xray_sdk.core import xray_recorder, patch_all
from aws_xray_sdk.ext.fastapi.middleware import XRayMiddleware

from routes.health import router as health_router
from routes.items import router as items_router

# X-Ray setup — must happen before patch_all()
xray_recorder.configure(
    service="platform-api",
    daemon_address="localhost:2000"
)
patch_all()  # Patches boto3, psycopg2, requests automatically

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Platform API", version="1.0.0")

# X-Ray middleware — traces every request
app.add_middleware(XRayMiddleware, recorder=xray_recorder)

app.include_router(health_router)
app.include_router(items_router, prefix="/api")

@app.on_event("startup")
async def startup():
    logger.info("Platform API starting up")
    logger.info(f"Region: {os.environ.get('AWS_REGION', 'unknown')}")
