# Security Groups
resource "aws_security_group" "alb_sg" {
  name        = "portfolio-alb-sg-${var.region_name}"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

}

resource "aws_security_group" "ec2_sg" {
  name        = "portfolio-ec2-sg-${var.region_name}"
  description = "Allow HTTP from ALB"
  vpc_id      = aws_vpc.main.id

}

resource "aws_security_group" "DB_sg" {
  name        = "portfolio-DB-sg-${var.region_name}"
  description = "Allow HTTP from DB"
  vpc_id      = aws_vpc.main.id

}

# Security Group for Redis
resource "aws_security_group" "redis_sg" {
  name        = "portfolio-redis-sg-${var.region_name}"
  description = "Allow Redis (6379) from app tier only"
  vpc_id      = aws_vpc.main.id

}
