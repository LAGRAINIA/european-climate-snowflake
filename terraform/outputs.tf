output "bucket_name" {
  value = module.s3_datalake.bucket_name
}

output "secret_name" {
  value = module.secrets.secret_name
}