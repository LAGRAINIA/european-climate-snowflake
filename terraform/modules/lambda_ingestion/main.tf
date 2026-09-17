variable "bucket_name"     { type = string }
variable "role_arn"        { type = string }
variable "lambda_zip_path" { type = string }
variable "layer_zip_path"  { type = string }

resource "aws_lambda_layer_version" "requests" {
  layer_name          = "climate-requests-layer"
  filename            = var.layer_zip_path
  compatible_runtimes = ["python3.12"]
  source_code_hash    = fileexists(var.layer_zip_path) ? filebase64sha256(var.layer_zip_path) : ""
}

resource "aws_lambda_function" "fetch_climate" {
  function_name    = "fetch_climate_data"
  role             = var.role_arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  timeout          = 120
  memory_size      = 512
  filename         = var.lambda_zip_path
  source_code_hash = fileexists(var.lambda_zip_path) ? filebase64sha256(var.lambda_zip_path) : ""
  layers           = [aws_lambda_layer_version.requests.arn]

  environment {
    variables = { S3_BUCKET = var.bucket_name }
  }
}

resource "aws_iam_role" "scheduler" {
  name = "climate-scheduler-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  role = aws_iam_role.scheduler.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.fetch_climate.arn
    }]
  })
}

resource "aws_scheduler_schedule" "hourly" {
  name = "climate-hourly-fetch"
  flexible_time_window { mode = "OFF" }
  schedule_expression = "rate(1 hour)"

  target {
    arn      = aws_lambda_function.fetch_climate.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

output "function_name" { value = aws_lambda_function.fetch_climate.function_name }