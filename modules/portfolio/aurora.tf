# ─────────────────────────────────────────────
# Aurora PostgreSQL Cluster
# ─────────────────────────────────────────────

# Global Aurora Cluster (created only by primary)
resource "aws_rds_global_cluster" "aurora" {
  count = var.is_primary ? 1 : 0

  global_cluster_identifier = "portfolio-aurora-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.aurora_engine_version
  storage_encrypted         = true
  deletion_protection       = false

}

resource "random_password" "db" {
  count   = var.is_primary ? 1 : 0
  length  = 32
  special = false # avoids / @ " and URL-encoding problems in database_url
}

# region KMS key
resource "aws_kms_key" "secrets" {
  description         = "KMS key for Aurora and secretsmanager in ${var.region_name}"
  enable_key_rotation = true
}

resource "aws_secretsmanager_secret" "db" {
  count                   = var.is_primary ? 1 : 0
  name                    = "portfolio/aurora/master"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0

  replica {
    region = "us-east-2" # copy to the secondary region (default key there)
  }
}

resource "aws_secretsmanager_secret_version" "db" {
  count     = var.is_primary ? 1 : 0
  secret_id = aws_secretsmanager_secret.db[0].id
  secret_string = jsonencode({
    username = "portfolio"
    password = random_password.db[0].result
  })
}

resource "aws_db_subnet_group" "aurora" {
  name       = "portfolio-aurora-sng-${var.region_name}"
  subnet_ids = aws_subnet.data[*].id # vpc_id is not a valid argument here
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier  = "portfolio-aurora-${var.region_name}"
  engine              = "aurora-postgresql"
  engine_version      = var.aurora_engine_version
  storage_encrypted   = true
  deletion_protection = false # set true for production
  skip_final_snapshot = true

  # Global cluster membership (set only for primary)
  global_cluster_identifier = local.global_cluster_id

  # Primary only. The secondary inherits data and credentials from the primary.
  database_name   = var.is_primary ? "portfolio" : null
  master_username = var.is_primary ? "portfolio" : null
  master_password = var.is_primary ? random_password.db[0].result : null

  # Secondary only
  source_region = var.is_primary ? null : "us-east-1"
  kms_key_id    = var.is_primary ? null : aws_kms_key.secrets.arn

  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.DB_sg.id]


  # Enable enhanced monitoring and backups
  backup_retention_period         = 7
  preferred_backup_window         = "02:00-03:00"
  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [replication_source_identifier, engine_version]
  }
}

# Aurora Cluster Instances (minimum 2 AZs)
resource "aws_rds_cluster_instance" "aurora" {
  count = 2

  identifier         = "portfolio-aurora-${var.region_name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.r6g.large"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version

  db_subnet_group_name = aws_db_subnet_group.aurora.name

  # Spread instances across different AZs
  availability_zone = data.aws_availability_zones.available.names[count.index]

  performance_insights_enabled = true
}

locals {
  global_cluster_id = coalesce(one(aws_rds_global_cluster.aurora[*].id), var.global_cluster_id)
}
