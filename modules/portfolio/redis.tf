# ─────────────────────────────────────────────
# ElastiCache Serverless – DB caching layer
# Replaces: aws_elasticache_subnet_group + aws_elasticache_replication_group
# (delete both, serverless takes subnet_ids directly and has no parameter group)
# ─────────────────────────────────────────────

resource "aws_elasticache_serverless_cache" "redis" {
  name        = "portfolio-redis-${var.region_name}"
  description = "Portfolio Redis cache - ${var.region_name}"

  engine               = "redis" # "valkey" is the cheaper drop-in (check current pricing)
  major_engine_version = "7"

  subnet_ids         = aws_subnet.data[*].id
  security_group_ids = [aws_security_group.redis_sg.id]

  # Caps scaling (and cost). Raise if you see throttling.
  cache_usage_limits {
    data_storage {
      maximum = 5
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 5000
    }
  }

  daily_snapshot_time      = "03:00"
  snapshot_retention_limit = 3

}

# TLS is mandatory on serverless, so the scheme is rediss:// (two s's)
locals {
  redis_url = "rediss://${aws_elasticache_serverless_cache.redis.endpoint[0].address}:${aws_elasticache_serverless_cache.redis.endpoint[0].port}"
}

