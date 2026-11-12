import json
import os
import boto3

from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")

table = dynamodb.Table(os.environ["TABLE_NAME"])


def response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": json.dumps(body)
    }


def handler(event, context):

    method = event["requestContext"]["http"]["method"]

    # GET /loads/{loadNumber}

    if method == "GET":

        load_number = event["pathParameters"]["loadNumber"]

        result = table.get_item(
            Key={
                "loadNumber": load_number
            }
        )

        item = result.get("Item")

        if not item:
            return response(404, {
                "message": "Load not found"
            })

        return response(200, item)

    # POST /loads

    elif method == "POST":

        try:
            body = json.loads(event.get("body") or "{}")

        except json.JSONDecodeError:
            return response(400, {
                "message": "Invalid JSON request body"
            })

        load_number = body.get("loadNumber")

        if not load_number:
            return response(400, {
                "message": "loadNumber is required"
            })

        try:
            table.put_item(
                Item=body,
                ConditionExpression="attribute_not_exists(loadNumber)"
            )

            return response(201, {
                "message": "Load created successfully",
                "loadNumber": load_number
            })

        except ClientError as e:

            error_code = e.response["Error"]["Code"]

            if error_code == "ConditionalCheckFailedException":
                return response(409, {
                    "message": "Load already exists"
                })

            print(f"DynamoDB error: {e!s}")

            return response(500, {
                "message": "Internal server error"
            })

    return response(405, {
        "message": "Method not allowed"
    })