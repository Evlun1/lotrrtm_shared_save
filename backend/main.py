import os
import boto3
from fastapi import BackgroundTasks, FastAPI, UploadFile, File, HTTPException, Query
from fastapi.responses import FileResponse
from mangum import Mangum
from botocore.exceptions import ClientError, NoCredentialsError
from dotenv import load_dotenv
import logging
import tempfile

# --- Configuration ---
load_dotenv()  # Load .env file if present (for local development)

AWS_REGION = os.getenv("AWS_REGION", "eu-west-3")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME")
SSM_PARAMETER_NAME = os.getenv("SSM_PARAMETER_NAME")
SSM_FILENAME_PARAMETER_NAME = os.getenv("SSM_FILENAME_PARAMETER_NAME")
SSM_PASSWORD_PARAMETER_NAME = os.getenv("SSM_PASSWORD_PARAMETER_NAME")
LOCK_VALUE_UNLOCKED = "unlocked"

if (
    not S3_BUCKET_NAME
    or not SSM_PARAMETER_NAME
    or not SSM_FILENAME_PARAMETER_NAME
    or not SSM_PASSWORD_PARAMETER_NAME
):
    raise ValueError(
        "Missing required environment variables: S3_BUCKET_NAME, SSM_PARAMETER_NAME, SSM_FILENAME_PARAMETER_NAME, SSM_PASSWORD_PARAMETER_NAME"
    )

# --- Logging ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger()

# --- AWS Clients ---
try:
    s3_client = boto3.client("s3", region_name=AWS_REGION)
    ssm_client = boto3.client("ssm", region_name=AWS_REGION)
except NoCredentialsError:
    logger.error("AWS credentials not found. Ensure they are configured correctly.")
    s3_client = None
    ssm_client = None

# --- FastAPI App ---
app = FastAPI()


# --- Helper Functions ---
def get_ssm_parameter(parameter_name: str, with_decryption: bool = False) -> str | None:
    """Fetches the value of an SSM parameter."""
    if not ssm_client:
        return None
    try:
        response = ssm_client.get_parameter(
            Name=parameter_name, WithDecryption=with_decryption
        )
        return response["Parameter"]["Value"]
    except ssm_client.exceptions.ParameterNotFound:
        logger.info(f"SSM Parameter '{parameter_name}' not found.")
        return None
    except ClientError as e:
        logger.error(f"Error getting SSM parameter '{parameter_name}': {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Error communicating with AWS SSM to get {parameter_name}",
        )


def set_ssm_parameter(parameter_name: str, value: str, overwrite: bool = True) -> bool:
    """Sets the value of an SSM parameter."""
    if not ssm_client:
        return False
    try:
        ssm_client.put_parameter(
            Name=parameter_name, Value=value, Type="String", Overwrite=overwrite
        )
        logger.info(f"Successfully set SSM Parameter '{parameter_name}' to '{value}'.")
        return True
    except ClientError as e:
        logger.error(f"Error setting SSM parameter '{parameter_name}': {e}")
        if e.response["Error"]["Code"] == "ParameterAlreadyExists" and not overwrite:
            logger.info(f"Parameter '{parameter_name}' already exists, not overwriting.")
            return True
        raise HTTPException(
            status_code=500,
            detail=f"Error communicating with AWS SSM to set {parameter_name}",
        )


# --- API Routes ---
@app.get("/get")
async def get_file(
    background_tasks: BackgroundTasks,
    who_are_you: str = Query(..., max_length=20),
    password: str = Query(..., max_length=20),
):
    """
    Fetches the file named in the filename SSM parameter from S3 if the API lock is 'unlocked'.
    If unlocked, it updates the lock with the 'who_are_you' value and returns the file.
    Otherwise, it returns the current lock value (with the name of the last person to download).
    """
    if not s3_client or not ssm_client:
        raise HTTPException(status_code=503, detail="AWS service client not available.")

    app_password = get_ssm_parameter(SSM_PASSWORD_PARAMETER_NAME, with_decryption=True)
    if app_password != password:
        raise HTTPException(status_code=403, detail="Provided password not valid")

    current_lock_value = get_ssm_parameter(SSM_PARAMETER_NAME)

    if current_lock_value == LOCK_VALUE_UNLOCKED:
        # Get the filename to download from the second SSM parameter
        filename_to_download = get_ssm_parameter(SSM_FILENAME_PARAMETER_NAME)
        if not filename_to_download or filename_to_download == "init":
            logger.error(
                f"Filename parameter '{SSM_FILENAME_PARAMETER_NAME}' not set or is initial value."
            )
            raise HTTPException(
                status_code=404, detail="No valid save filename found to download."
            )

        logger.info(
            f"API is unlocked. Attempting to download '{filename_to_download}' for '{who_are_you}'."
        )

        # Create a temporary file to download to
        temp_dir = tempfile.TemporaryDirectory()
        try:
            # Use the filename retrieved from SSM as the S3 Key
            local_path = os.path.join(temp_dir.name, filename_to_download)
            s3_client.download_file(S3_BUCKET_NAME, filename_to_download, local_path)
            logger.info(
                f"Successfully downloaded '{filename_to_download}' to '{local_path}'."
            )

            # Update SSM parameter to lock it
            if set_ssm_parameter(SSM_PARAMETER_NAME, who_are_you, overwrite=True):
                logger.info(f"Locked API with value: '{who_are_you}'.")
                # Return file using the retrieved filename
                background_tasks.add_task(clean_temp_dir, temp_dir)
                return FileResponse(
                    path=local_path,
                    filename=filename_to_download,  # Use the actual filename
                    media_type="application/octet-stream",
                )
            else:
                background_tasks.add_task(clean_temp_dir, temp_dir)
                raise HTTPException(
                    status_code=500,
                    detail="Failed to update API lock after download.",
                )

        except ClientError as e:
            background_tasks.add_task(clean_temp_dir, temp_dir)
            if (
                e.response["Error"]["Code"] == "NoSuchKey"
                or e.response["Error"]["Code"] == "404"
            ):
                logger.error(
                    f"File '{filename_to_download}' not found in bucket '{S3_BUCKET_NAME}'."
                )
                raise HTTPException(
                    status_code=404,
                    detail=f"Save file '{filename_to_download}' not found in S3.",
                )
            else:
                logger.error(f"Error downloading file from S3: {e}")
                raise HTTPException(
                    status_code=500, detail="Error downloading file from S3."
                )

    else:
        logger.info(
            f"API is locked or parameter not found. Current value: '{current_lock_value}'. Request by '{who_are_you}'."
        )
        raise HTTPException(
            status_code=409,
            detail=f"Cannot download as save is locked by {current_lock_value}",
        )


def clean_temp_dir(temp_dir: tempfile.TemporaryDirectory) -> None:
    temp_dir.cleanup()


@app.post("/post")
async def upload_file(
    who_are_you: str = Query(..., max_length=20),
    password: str = Query(..., max_length=20),
    file: UploadFile = File(...),
):
    """
    Uploads a file to S3 if the API lock is not 'unlocked'.
    If the lock SSM parameter doesn't exist, it creates it with value 'unlocked'.
    Updates the filename SSM parameter with the name of the uploaded file.
    """
    if not s3_client or not ssm_client:
        raise HTTPException(status_code=503, detail="AWS service client not available.")

    app_password = get_ssm_parameter(SSM_PASSWORD_PARAMETER_NAME, with_decryption=True)
    if app_password != password:
        raise HTTPException(status_code=403, detail="Provided password not valid")

    logger.info(
        f"Received upload request from '{who_are_you}'. Uploading filename: '{file.filename}'"
    )
    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename cannot be empty.")

    current_lock_value = get_ssm_parameter(SSM_PARAMETER_NAME)

    # Check lock status
    if current_lock_value != LOCK_VALUE_UNLOCKED:
        logger.info(
            f"API lock is not '{LOCK_VALUE_UNLOCKED}' (current: '{current_lock_value}'). Proceeding with upload."
        )
        try:
            # Use the actual uploaded filename as the S3 Key
            s3_client.upload_fileobj(
                file.file,
                S3_BUCKET_NAME,
                file.filename,  # Use the provided filename as S3 key
            )
            logger.info(
                f"Successfully uploaded file as '{file.filename}' in bucket '{S3_BUCKET_NAME}'."
            )

            # After successful upload, update the filename parameter
            logger.info(
                f"Updating filename parameter '{SSM_FILENAME_PARAMETER_NAME}' to '{file.filename}'."
            )
            if not set_ssm_parameter(
                SSM_FILENAME_PARAMETER_NAME, file.filename, overwrite=True
            ):
                # This is problematic - upload succeeded but tracking failed.
                # Might need manual reset then
                logger.error(
                    f"CRITICAL: Failed to update filename SSM parameter '{SSM_FILENAME_PARAMETER_NAME}' after S3 upload."
                )
                raise HTTPException(
                    status_code=500,
                    detail="File uploaded but failed to update tracking parameter.",
                )
            set_ssm_parameter(SSM_PARAMETER_NAME, LOCK_VALUE_UNLOCKED, overwrite=True)
            logger.info(f"State lock set to {LOCK_VALUE_UNLOCKED}.")
            return {
                "message": f"File '{file.filename}' uploaded successfully by '{who_are_you}'."
            }

        except ClientError as e:
            logger.error(f"Error uploading file to S3: {e}")
            raise HTTPException(status_code=500, detail="Error uploading file to S3.")
        finally:
            await file.close()
    else:
        logger.warning(
            f"Upload attempt by '{who_are_you}' rejected. API lock is currently '{LOCK_VALUE_UNLOCKED}'."
        )
        await file.close()
        raise HTTPException(
            status_code=409,
            detail="Cannot upload: API lock is 'unlocked', indicating a file may already be present and downloadable.",
        )


# --- Mangum Handler for AWS Lambda ---
handler = Mangum(app)

# --- For local execution ---
if __name__ == "__main__":
    import uvicorn

    if (
        not S3_BUCKET_NAME
        or not SSM_PARAMETER_NAME
        or not SSM_FILENAME_PARAMETER_NAME
        or not SSM_PASSWORD_PARAMETER_NAME
    ):
        print(
            "ERROR: Set S3_BUCKET_NAME, SSM_PARAMETER_NAME, SSM_FILENAME_PARAMETER_NAME and SSM_PASSWORD_PARAMETER_NAME environment variables for local testing."
        )
    else:
        print(f"Starting Uvicorn server locally...")
        print(f"Using Region: {AWS_REGION}")
        print(f"Using Bucket: {S3_BUCKET_NAME}")
        print(f"Using Lock Param: {SSM_PARAMETER_NAME}")
        print(f"Using Filename Param: {SSM_FILENAME_PARAMETER_NAME}")
        print(f"Using Password Param: {SSM_PASSWORD_PARAMETER_NAME}")
        uvicorn.run(app, host="0.0.0.0", port=8000)
