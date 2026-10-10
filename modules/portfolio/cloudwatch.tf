# ─────────────────────────────────────────────
# CloudWatch – Log Groups, Alarms, Dashboard
# ─────────────────────────────────────────────

# ── Log Groups ───────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/portfolio/${var.region_name}/app"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "aurora" {
  name              = "/portfolio/${var.region_name}/aurora"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "waf" {
  # WAF requires log group name prefix: aws-waf-logs-
  name              = "aws-waf-logs-portfolio-${var.region_name}"
  retention_in_days = 30
}

# WAF logging configuration
resource "aws_wafv2_web_acl_logging_configuration" "main" {
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]
  resource_arn            = aws_wafv2_web_acl.main.arn
}

# ── ALB CloudWatch Alarms ─────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "portfolio-alb-5xx-${var.region_name}"
  alarm_description   = "ALB 5XX error rate too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  alarm_name          = "portfolio-alb-latency-${var.region_name}"
  alarm_description   = "ALB target response time too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  extended_statistic  = "p99"
  threshold           = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}

# ── Aurora Alarms ────────────────────────────
resource "aws_cloudwatch_metric_alarm" "aurora_cpu" {
  alarm_name          = "portfolio-aurora-cpu-${var.region_name}"
  alarm_description   = "Aurora cluster CPU utilization too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.aurora.cluster_identifier
  }
}

resource "aws_cloudwatch_metric_alarm" "aurora_freeable_memory" {
  count               = 2
  alarm_name          = "portfolio-aurora-memory-${var.region_name}-${count.index + 1}"
  alarm_description   = "Aurora instance freeable memory low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 256000000 # 256 MB in bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_rds_cluster_instance.aurora[count.index].identifier
  }
}

# ── Redis Alarms ─────────────────────────────
resource "aws_cloudwatch_metric_alarm" "redis_cpu" {
  alarm_name          = "portfolio-redis-cpu-${var.region_name}"
  alarm_description   = "Redis CPU utilization too high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    ServerlessCacheName = aws_elasticache_serverless_cache.redis.name
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  alarm_name          = "portfolio-redis-evictions-${var.region_name}"
  alarm_description   = "Redis evictions occurring – cache too small"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Evictions"
  namespace           = "AWS/ElastiCache"
  period              = 60
  statistic           = "Sum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    ServerlessCacheName = aws_elasticache_serverless_cache.redis.name
  }
}

# ── CloudWatch Dashboard ──────────────────────
resource "aws_cloudwatch_dashboard" "portfolio" {
  dashboard_name = "portfolio-${var.region_name}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "ALB 5XX Errors – ${var.region_name}"
          metrics = [["AWS/ApplicationELB", "HTTPCode_ELB_5XX_Count", "LoadBalancer", aws_lb.web.arn_suffix]]
          period  = 60
          stat    = "Sum"
          region  = data.aws_region.current.name
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title   = "Aurora CPU – ${var.region_name}"
          metrics = [["AWS/RDS", "CPUUtilization", "DBClusterIdentifier", aws_rds_cluster.aurora.cluster_identifier]]
          period  = 60
          stat    = "Average"
          region  = data.aws_region.current.name
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "Redis CPU – ${var.region_name}"
          metrics = [["AWS/ElastiCache", "CPUUtilization", "ServerlessCacheName", aws_elasticache_serverless_cache.redis.name]]
          period  = 60
          stat    = "Average"
          region  = data.aws_region.current.name
          view    = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title   = "ALB Target Response Time p99 – ${var.region_name}"
          metrics = [["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.web.arn_suffix]]
          period  = 60
          stat    = "p99"
          region  = data.aws_region.current.name
          view    = "timeSeries"
        }
      }
    ]
  })
}
