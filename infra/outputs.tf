output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = aws_lambda_function.api_lambda.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = aws_lambda_function.api_lambda.arn
}

output "lambda_function_url" {
  description = "Public URL for the Lambda Function"
  value       = aws_lambda_function_url.api_url.function_url
  sensitive   = false
}

output "s3_bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.data_bucket.id
}

output "s3_bucket_arn" {
  description = "ARN of the created S3 bucket"
  value       = aws_s3_bucket.data_bucket.arn
}

output "ssm_lock_parameter_name" {
  description = "Name of the created SSM Parameter for lock status"
  value       = aws_ssm_parameter.api_lock.name
}

output "ssm_filename_parameter_name" {
  description = "Name of the created SSM Parameter for the filename"
  value       = aws_ssm_parameter.api_filename.name
}

output "ssm_password_parameter_name" {
  description = "Name of the created SSM Parameter for the filename"
  value       = aws_ssm_parameter.api_filename.name
}