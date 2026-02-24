import time
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    logger.info("Platform worker starting")
    logger.info(f"Region: {os.environ.get('AWS_REGION', 'unknown')}")

    iteration = 0
    while True:
        iteration += 1
        logger.info(f"Worker iteration {iteration} - processing...")
        time.sleep(30)

if __name__ == "__main__":
    main()
