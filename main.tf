terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }

  backend "s3" {
    bucket = "my-static-assets14"
    key    = "my-static-assets14"
    region = "ap-south-1"
  }
}

# Default provider: primary region. Also used by the root resources below
# (Route53, CloudFront, CloudTrail) so they don't need a provider argument.
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "secondary"
  region = "us-east-2"
}

# ── Module: us-east-1 (Primary, creates the Aurora global cluster) ──
module "portfolio_primary" {
  source           = "./modules/portfolio"
  region_name      = "use1"
  is_primary       = true
  webui_secret_key = var.webui_secret_key

  providers = {
    aws = aws
  }
}

# ── Module: us-east-2 (Secondary, joins the global cluster read-only) ──
module "portfolio_secondary" {
  source      = "./modules/portfolio"
  region_name = "use2"
  is_primary  = false

  global_cluster_id = module.portfolio_primary.aurora_global_cluster_id
  webui_secret_key  = var.webui_secret_key

  providers = {
    aws = aws.secondary
  }

  depends_on = [module.portfolio_primary]
}

# ─────────────────────────────────────────────
# Route53 Hosted Zone
# ─────────────────────────────────────────────
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# Route 53 Apex pointing to CloudFront
resource "aws_route53_record" "cdn" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = false
  }
}

# Weighted routing: primary (us-east-1)
resource "aws_route53_record" "alb_primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "alb.${var.domain_name}"
  type    = "A"

  set_identifier = "us-east-1"
  weighted_routing_policy {
    weight = 100
  }

  alias {
    name                   = module.portfolio_primary.alb_dns_name
    zone_id                = module.portfolio_primary.alb_zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_route53_record.alb_primary, aws_route53_record.alb_secondary]
}

# Weighted routing: secondary (us-east-2)
resource "aws_route53_record" "alb_secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "alb.${var.domain_name}"
  type    = "A"

  set_identifier = "us-east-2"
  weighted_routing_policy {
    weight = 0
  }

  alias {
    name                   = module.portfolio_secondary.alb_dns_name
    zone_id                = module.portfolio_secondary.alb_zone_id
    evaluate_target_health = true
  }
}

# ─────────────────────────────────────────────
# CloudFront Distribution
# ─────────────────────────────────────────────
data "aws_cloudfront_origin_request_policy" "all_viewer" {
  name = "Managed-AllViewer"
}

# Required: the default behavior needs a cache policy (or forwarded_values)
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = module.portfolio_primary.alb_dns_name
    origin_id   = "ALBOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 60
    }
  }

  enabled         = true
  is_ipv6_enabled = true
  comment         = "Portfolio CloudFront Distribution (Multi-Region)"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ALBOrigin"

    # App is dynamic (logins, websockets): no caching, forward everything
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id

    viewer_protocol_policy = "allow-all"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  depends_on = [aws_route53_record.alb_primary, aws_route53_record.alb_secondary]
}

# ─────────────────────────────────────────────
# CloudTrail – global, multi-region audit log
# ─────────────────────────────────────────────

# S3 bucket for CloudTrail logs (root-level, primary region)
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "portfolio-cloudtrail-${data.aws_caller_identity.root.account_id}"
  force_destroy = true

  tags = { Name = "portfolio-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.root.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.cloudtrail]
}

# CloudTrail (multi-region, includes global service events)
resource "aws_cloudtrail" "main" {
  name                          = "portfolio-cloudtrail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3"]
    }
  }

  tags = { Name = "portfolio-cloudtrail" }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

data "aws_caller_identity" "root" {}

# ─────────────────────────────────────────────
# Root-level variables
# database_url and redis_url are gone: the instances build them at boot
# ─────────────────────────────────────────────
variable "domain_name" {
  type        = string
  default     = "portfolio.com"
  description = "Domain you own; a Route53 zone is created for it (delegate its NS records)"
}

variable "webui_secret_key" {
  type        = string
  sensitive   = true
  description = "Session signing key for Open WebUI (WEBUI_SECRET_KEY)"
}
