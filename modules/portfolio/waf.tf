# WAF Web ACL (Regional - for ALB)
resource "aws_wafv2_web_acl" "main" {
  name        = "portfolio-waf-${var.region_name}"
  description = "WAF Web ACL for Portfolio ALB - ${var.region_name}"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: AWS Managed - Common Rule Set
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "portfolio-waf-${var.region_name}-common"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: AWS Managed - Known Bad Inputs
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "portfolio-waf-${var.region_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS Managed - SQL Injection Protection
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 3

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "portfolio-waf-${var.region_name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # Rule 4: Rate Limiting - 1000 requests per 5 minutes per IP
  rule {
    name     = "RateLimitRule"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "portfolio-waf-${var.region_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "portfolio-waf-${var.region_name}"
    sampled_requests_enabled   = true
  }

  tags = {
    Name   = "portfolio-waf-${var.region_name}"
    Region = var.region_name
  }
}

# Associate WAF Web ACL with the ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.web.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
