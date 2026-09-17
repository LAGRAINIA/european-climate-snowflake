variable "bucket_name"     { type = string }
variable "bucket_arn"      { type = string }
variable "role_arn"        { type = string }
variable "loader_zip_path" { type = string }
variable "layer_zip_path"  { type = string }
variable "secret_name"     { type = string }

resource "aws_lambda_layer_version" "snowflake_connector" {
  layer_name          = "climate-snowflake-connector-layer"
  filename            = var.layer_zip_path
  compatible_runtimes = ["python3.12"]
  source_code_hash    = fileexists(var.layer_zip_path) ? filebase64sha256(var.layer_zip_path) : ""
}

resource "aws_lambda_function" "load_to_snowflake" {
  function_name    = "load_to_snowflake"
  role             = var.role_arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  timeout          = 300
  memory_size      = 1024
  filename         = var.loader_zip_path
  source_code_hash = fileexists(var.loader_zip_path) ? filebase64sha256(var.loader_zip_path) : ""
  layers           = [aws_lambda_layer_version.snowflake_connector.arn]

  environment {
    variables = {
      SNOWFLAKE_SECRET_NAME = var.secret_name
      AWS_REGION_NAME       = "eu-west-1"
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.load_to_snowflake.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.bucket_arn
}

resource "aws_s3_bucket_notification" "loader_trigger" {
  bucket = var.bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.load_to_snowflake.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "bronze/climate/forecast/"
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

output "function_name" { value = aws_lambda_function.load_to_snowflake.function_name }