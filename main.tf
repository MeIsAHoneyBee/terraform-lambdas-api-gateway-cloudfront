variable "profile" {}
variable "public_bucket_name" {}
variable "private_bucket_name" {}
variable "lambda_edge_bucket_name" {}
variable "project_prefix" {}
variable "region" {}
variable "lambda_edge_region" {}
variable "account_id" {}

terraform {
  backend "s3" {}
}

provider "aws" {
  version = "~> 2.22"
  profile = "${var.profile}"
  region  = "eu-west-2"
}

provider "aws" {
  version = "~> 2.22"
  profile = "${var.profile}"
  region  = "${var.lambda_edge_region}"
  alias   = "lambda_edge"
}

data "archive_file" "lambda_json" {
  type        = "zip"
  source_dir  = "${path.module}/src/lambda_json"
  output_path = "${path.module}/_build/lambda_json.zip"
}

data "archive_file" "lambda_html" {
  type        = "zip"
  source_dir  = "${path.module}/src/lambda_html"
  output_path = "${path.module}/_build/lambda_html.zip"
}

module "buckets" {
  source                  = "./buckets"
  public_bucket_name      = "${var.public_bucket_name}"
  private_bucket_name     = "${var.private_bucket_name}"
  lambda_edge_bucket_name = "${var.lambda_edge_bucket_name}"
  providers = {
    aws.lambda_edge = aws.lambda_edge
  }
}

module "objects" {
  source               = "./objects"
  public_bucket        = "${module.buckets.public_bucket}"
  private_bucket       = "${module.buckets.private_bucket}"
  lambda_edge_bucket   = "${module.buckets.lambda_edge_bucket}"
  lambda_json_zip_path = "${data.archive_file.lambda_json.output_path}"
  lambda_html_zip_path = "${data.archive_file.lambda_html.output_path}"
  example_image_path   = "${path.module}/src/assets/example.jpg"
  providers = {
    aws.lambda_edge = aws.lambda_edge
  }
}

module "lambdas" {
  source           = "./lambdas"
  private_bucket   = "${module.buckets.private_bucket}"
  lambda_json_key  = "${module.objects.lambda_json_key}"
  lambda_json_hash = "${data.archive_file.lambda_json.output_base64sha256}"
  project_prefix   = "${var.project_prefix}"
}

module "api_gateway" {
  source                    = "./api_gateway"
  region                    = "${var.region}"
  account_id                = "${var.account_id}"
  lambda_json_invoke_arn    = "${module.lambdas.lambda_json_invoke_arn}"
  lambda_json_function_name = "${module.lambdas.lambda_json_function_name}"
  lambda_json_qualified_arn = "${module.lambdas.lambda_json_qualified_arn}"
}

module "edge_lambdas" {
  source               = "./edge_lambdas"
  lambda_edge_bucket   = "${module.buckets.lambda_edge_bucket}"
  lambda_edge_html_key = "${module.objects.lambda_edge_html_key}"
  lambda_html_hash     = "${data.archive_file.lambda_html.output_base64sha256}"
  project_prefix       = "${var.project_prefix}"
  providers = {
    aws.lambda_edge = aws.lambda_edge
  }
}

module "cloudfront" {
  source                         = "./cloudfront"
  public_bucket_domain_name      = "${module.buckets.public_bucket_domain_name}"
  lambda_edge_bucket_domain_name = "${module.buckets.lambda_edge_bucket_domain_name}"
  origin_id                      = "${var.project_prefix}-cloudfront-distribution"
  project_prefix                 = "${var.project_prefix}"
  edge_lambda_html_qualified_arn = "${module.edge_lambdas.edge_lambda_html_qualified_arn}"
}



# OUTPUT

output "public_bucket_domain_name" {
  value = "${module.buckets.public_bucket_domain_name}"
}
output "private_bucket_domain_name" {
  value = "${module.buckets.private_bucket_domain_name}"
}
output "lambda_edge_bucket_domain_name" {
  value = "${module.buckets.lambda_edge_bucket_domain_name}"
}
output "example_image_url" {
  value = "${module.buckets.public_bucket_domain_name}/${module.objects.example_image_key}"
}

output "cloudfront_domain_name" {
  value = "${module.cloudfront.cloudfront_domain_name}"
}

output "edge_lambda_cloud_url" {
  value = "${module.cloudfront.edge_lambda_cloud_url}"
}
