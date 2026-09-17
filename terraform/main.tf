terraform {
  required_version = ">= 1.5"

  backend "s3" {
    bucket  = "climate-snowflake-tfstate-anass"
    key     = "climate-platform/terraform.tfstate"
    region  = "eu-west-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "climate-analytics-snowflake"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "${var.project_name}-${var.environment}"
}

module "s3_datalake" {
  source      = "./modules/s3_datalake"
  bucket_name = local.bucket_name
}

module "secrets" {
  source           = "./modules/secrets"
  snowflake_account   = var.snowflake_account
  snowflake_user      = var.snowflake_user
  snowflake_password  = var.snowflake_password
  snowflake_role      = var.snowflake_role
  snowflake_warehouse = var.snowflake_warehouse
  snowflake_database  = var.snowflake_database
  snowflake_schema    = var.snowflake_schema
}

module "iam_roles" {
  source     = "./modules/iam_roles"
  bucket_arn = module.s3_datalake.bucket_arn
  secret_arn = module.secrets.secret_arn
}

module "lambda_ingestion" {
  source          = "./modules/lambda_ingestion"
  bucket_name     = module.s3_datalake.bucket_name
  role_arn        = module.iam_roles.lambda_role_arn
  lambda_zip_path = var.lambda_zip_path
  layer_zip_path  = var.layer_zip_path
}

module "lambda_loader" {
  source            = "./modules/lambda_loader"
  bucket_name       = module.s3_datalake.bucket_name
  bucket_arn        = module.s3_datalake.bucket_arn
  role_arn          = module.iam_roles.loader_role_arn
  loader_zip_path   = var.loader_zip_path
  layer_zip_path    = var.loader_layer_zip_path
  secret_name       = module.secrets.secret_name
}