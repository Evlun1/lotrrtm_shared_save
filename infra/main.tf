terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

# --- S3 Bucket ---
resource "aws_s3_bucket" "data_bucket" {
  bucket = "this-is-guigui-buckets-${var.project_name}-deployed"
  tags = {
    Name      = "this-is-guigui-buckets-${var.project_name}-data-bucket"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "data_bucket_access_block" {
  bucket                  = aws_s3_bucket.data_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- SSM Parameters ---
resource "aws_ssm_parameter" "api_lock" {
  name        = var.ssm_parameter_name
  description = "Lock status for the API"
  type        = "String"
  value       = var.ssm_initial_value
  tags = {
    Name      = var.ssm_parameter_name
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
  lifecycle {
    ignore_changes = [ value ]
  }
}

resource "aws_ssm_parameter" "api_filename" {
  name        = var.ssm_filename_parameter_name
  description = "Name of the last successfully uploaded file"
  type        = "String"
  value       = var.ssm_initial_value
  tags = {
    Name      = var.ssm_filename_parameter_name
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
  lifecycle {
    ignore_changes = [ value ]
  }
}

data "aws_kms_key" "this" {
  key_id = "alias/aws/ssm"
}

resource "aws_ssm_parameter" "api_password" {
  name        = var.ssm_password_parameter_name
  description = "Name of the last successfully uploaded file"
  type        = "SecureString"
  value       = var.ssm_password_value
  key_id      = data.aws_kms_key.this.id
  tags = {
    Name      = var.ssm_password_parameter_name
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# --- IAM Role and Policy for Lambda ---
data "aws_iam_policy_document" "lambda_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "${var.project_name}-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
  tags = {
    Name      = "${var.project_name}-lambda-exec-role"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

data "aws_iam_policy_document" "lambda_permissions_policy" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = [
      "${aws_s3_bucket.data_bucket.arn}/*"
    ]
  }

  statement {
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter"
    ]
    resources = [
      aws_ssm_parameter.api_lock.arn,
      aws_ssm_parameter.api_filename.arn
    ]
  }

  statement {
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      aws_ssm_parameter.api_password.arn
    ]
  }

  statement {
    actions = [ 
      "kms:Decrypt"
    ]
    resources = [
      data.aws_kms_key.this.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_permissions" {
  name        = "${var.project_name}-lambda-permissions-policy"
  description = "Permissions for the FastAPI Lambda function"
  policy      = data.aws_iam_policy_document.lambda_permissions_policy.json
  tags = {
    Name      = "${var.project_name}-lambda-permissions-policy"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = aws_iam_policy.lambda_permissions.arn
}

# --- Package Lambda Code ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "../backend/zip_build_dir"
  output_path = "${path.module}/lambda_package.zip"
}

# --- Lambda Function ---
resource "aws_lambda_function" "api_lambda" {
  function_name = "${var.project_name}-api-lambda"
  role          = aws_iam_role.lambda_exec_role.arn
  handler       = "main.handler"
  runtime       = "python3.12"
  memory_size   = 128
  timeout       = 30

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME              = aws_s3_bucket.data_bucket.id
      SSM_PARAMETER_NAME          = aws_ssm_parameter.api_lock.name
      SSM_FILENAME_PARAMETER_NAME = aws_ssm_parameter.api_filename.name
      SSM_PASSWORD_PARAMETER_NAME = aws_ssm_parameter.api_password.name
    }
  }

  tags = {
    Name      = "${var.project_name}-api-lambda"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# --- CloudWatch Log Group for Lambda ---
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${aws_lambda_function.api_lambda.function_name}"
  retention_in_days = 14
  tags = {
    Name      = "${var.project_name}-lambda-logs"
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# --- Lambda Function URL ---
resource "aws_lambda_function_url" "api_url" {
  function_name      = aws_lambda_function.api_lambda.function_name
  authorization_type = "NONE"
  depends_on         = [aws_lambda_function.api_lambda]
}
