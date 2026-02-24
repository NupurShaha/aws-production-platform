import json
import os
import boto3
import logging

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter()
logger = logging.getLogger(__name__)

def get_secret(secret_name: str) -> dict:
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

class Item(BaseModel):
    name: str
    description: str = ""

@router.get("/items")
def list_items():
    """Demo endpoint - returns static list (no DB needed for initial test)."""
    return {"items": [
        {"id": 1, "name": "Widget A", "description": "First demo item"},
        {"id": 2, "name": "Widget B", "description": "Second demo item"},
    ]}

@router.post("/items")
def create_item(item: Item):
    """Demo endpoint - echoes back the item (no DB write needed for initial test)."""
    logger.info(f"Creating item: {item.name}")
    return {"id": 3, "name": item.name, "description": item.description, "status": "created"}
