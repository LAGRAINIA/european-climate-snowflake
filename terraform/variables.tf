variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "climate-anass"
}

variable "snowflake_account"   { type = string }
variable "snowflake_user"      {
  type    = string
  default = "LOADER_USER"
}
variable "snowflake_password" {
  type      = string
  sensitive = true
}
variable "snowflake_role" {
  type    = string
  default = "LOADER_ROLE"
}
variable "snowflake_warehouse" {
  type    = string
  default = "LOAD_WH"
}
variable "snowflake_database" {
  type    = string
  default = "RAW"
}
variable "snowflake_schema" {
  type    = string
  default = "CLIMATE"
}

variable "lambda_zip_path" {
  type    = string
  default = "../dist/fetch_climate_data.zip"
}

variable "layer_zip_path" {
  type    = string
  default = "../dist/requests-layer.zip"
}

variable "loader_zip_path" {
  type    = string
  default = "../dist/load_to_snowflake.zip"
}

variable "loader_layer_zip_path" {
  type    = string
  default = "../dist/snowflake-connector-layer.zip"
}