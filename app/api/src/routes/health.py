from fastapi import APIRouter

router = APIRouter()

@router.get("/health")
def health():
    return {"status": "healthy", "service": "platform-api"}

@router.get("/error")
def force_error():
    """Endpoint to deliberately generate 500s for alarm testing."""
    raise Exception("Forced error for CloudWatch alarm testing")
