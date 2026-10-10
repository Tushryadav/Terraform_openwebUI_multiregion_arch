# ─────────────────────────────────────────────
# Amazon GuardDuty – per region threat detection
# ─────────────────────────────────────────────

resource "aws_guardduty_detector" "main" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  datasources {
    s3_logs {
      enable = true
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name   = "portfolio-guardduty-${var.region_name}"
    Region = var.region_name
  }
}
