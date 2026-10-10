data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_region" "current" {}

# Attach to EC2 instance role
data "aws_iam_policy_document" "ec2_permissions" {
  statement {
    sid       = "SecretsManagerAccess"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:*:*:secret:portfolio/aurora/master-*"]
  }

  # Primary region only: the secret is encrypted with aws_kms_key.secrets.
  # The us-east-2 replica uses the default key, so no kms:Decrypt is needed there.
  dynamic "statement" {
    for_each = var.is_primary ? [1] : []
    content {
      sid       = "KMSDecryptAccess"
      actions   = ["kms:Decrypt"]
      resources = [aws_kms_key.secrets.arn]
    }
  }

  # S3 bucket permissions for Open WebUI storage
  statement {
    sid       = "S3BucketAccess"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.portfolio.arn]
  }

  statement {
    sid = "S3ObjectAccess"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.portfolio.arn}/*"]
  }

  # CloudWatch logs for Docker container awslogs logging driver
  statement {
    sid = "CloudWatchLogsAccess"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/owui/*",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/portfolio/*"
    ]
  }
}

resource "aws_iam_role_policy" "ec2_app_policy" {
  name   = "portfolio-ec2-app-policy-${var.region_name}"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

# Attach AWS SSM Managed Instance Core for Session Manager support
resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_launch_template" "web" {
  name_prefix   = "portfolio-lt-${var.region_name}-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.small"

  # The instance profile MUST be attached, or the instance can't call Secrets Manager
  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name # <- your existing profile
  }

  network_interfaces {
    security_groups             = [aws_security_group.ec2_sg.id]
    associate_public_ip_address = false
  }

  depends_on = [aws_rds_cluster_instance.aurora]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }


  user_data = base64encode(templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region       = data.aws_region.current.name # real region (us-east-1), NOT var.region_name ("use1")
    db_endpoint      = aws_rds_cluster.aurora.endpoint
    redis_url        = local.redis_url
    s3_bucket        = local.s3_bucket
    webui_secret_key = var.webui_secret_key
    log_group        = aws_cloudwatch_log_group.app.name
    is_primary       = var.is_primary
  }))
}


