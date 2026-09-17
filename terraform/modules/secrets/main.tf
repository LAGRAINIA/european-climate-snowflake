variable "snowflake_account"   { type = string }
variable "snowflake_user"      { type = string }
variable "snowflake_password" {
  type      = string
  sensitive = true
}
variable "snowflake_role"      { type = string }
variable "snowflake_warehouse" { type = string }
variable "snowflake_database"  { type = string }
variable "snowflake_schema"    { type = string }

resource "aws_secretsmanager_secret" "snowflake" {
  name                    = "climate/snowflake"
  description             = "Snowflake credentials for loader Lambda"
  recovery_window_in_days = 0    # dev only — allows immediate re-create
}

resource "aws_secretsmanager_secret_version" "snowflake" {
  secret_id = aws_secretsmanager_secret.snowflake.id
  secret_string = jsonencode({
    account   = var.snowflake_account
    user      = var.snowflake_user
    password  = var.snowflake_password
    role      = var.snowflake_role
    warehouse = var.snowflake_warehouse
    database  = var.snowflake_database
    schema    = var.snowflake_schema
  })
}

output "secret_arn"  { value = aws_secretsmanager_secret.snowflake.arn }
output "secret_name" { value = aws_secretsmanager_secret.snowflake.name }