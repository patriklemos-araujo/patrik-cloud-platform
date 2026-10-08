import boto3

BUCKET = "patrik-cloud-platform-s3-lab-910093226300"
KEY = "lab/app-test.txt"

s3 = boto3.client("s3", region_name="us-east-1")

content = b"Hello from boto3 - Lab 06"

s3.put_object(
    Bucket=BUCKET,
    Key=KEY,
    Body=content,
    ContentType="text/plain"
)

print(f"Upload completed: s3://{BUCKET}/{KEY}")