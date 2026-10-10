output "alb_dns_name" {
  value = aws_lb.web.dns_name
}

output "alb_zone_id" {
  value = aws_lb.web.zone_id
}

output "waf_web_acl_arn" {
  value       = aws_wafv2_web_acl.main.arn
  description = "ARN of the WAF Web ACL associated with the ALB"
}

output "waf_web_acl_id" {
  value       = aws_wafv2_web_acl.main.id
  description = "ID of the WAF Web ACL"
}

output "aurora_cluster_endpoint" {
  value       = aws_rds_cluster.aurora.endpoint
  description = "Writer endpoint for the Aurora cluster"
}

output "aurora_cluster_reader_endpoint" {
  value       = aws_rds_cluster.aurora.reader_endpoint
  description = "Reader endpoint for the Aurora cluster"
}

output "redis_endpoint" {
  value       = aws_elasticache_serverless_cache.redis.endpoint[0].address
  description = "Primary endpoint for the Redis replication group"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.portfolio.bucket
  description = "Name of the portfolio S3 bucket"
}

output "s3_bucket_arn" {
  value       = aws_s3_bucket.portfolio.arn
  description = "ARN of the portfolio S3 bucket"
}

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "redis_reader_endpoint" {
  description = "Reader endpoint for the Redis replication group"
  value       = aws_elasticache_serverless_cache.redis.reader_endpoint[0].address
}

output "aurora_global_cluster_id" {
  value      = local.global_cluster_id
  depends_on = [aws_rds_cluster_instance.aurora]
}
