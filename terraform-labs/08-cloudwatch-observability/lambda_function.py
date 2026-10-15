import json
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def lambda_handler(event, context):
    mode = event.get("mode", "success")

    logger.info("Application started")
    logger.info(f"Execution mode: {mode}")

    if mode == "warning":
        logger.warning("Simulated warning event")

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Warning generated successfully"
            })
        }

    if mode == "error":
        logger.error("Simulated application failure")

        raise Exception("Simulated application error")

    logger.info("Execution completed successfully")

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Application executed successfully"
        })
    }