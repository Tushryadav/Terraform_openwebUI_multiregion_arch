# Security Groups
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb_sg.id

  description = "HTTP from anywhere"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
}

# resource "aws_vpc_security_group_ingress_rule" "alb_https" {
#   security_group_id = aws_security_group.alb_sg.id

#   description = "HTTPS from anywhere"
#   cidr_ipv4   = "0.0.0.0/0"
#   ip_protocol = "tcp"
#   from_port   = 443
#   to_port     = 443
# }

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.alb_sg.id

  description = "Allow all outbound traffic"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_alb_http" {
  security_group_id            = aws_security_group.ec2_sg.id
  referenced_security_group_id = aws_security_group.alb_sg.id

  description = "HTTP from ALB"
  ip_protocol = "tcp"
  from_port   = 8080
  to_port     = 8080
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_internet_https" {
  security_group_id = aws_security_group.ec2_sg.id

  description = "HTTPS to ALB"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_internet_http" {
  security_group_id = aws_security_group.ec2_sg.id

  description = "HTTPS to ALB"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "tcp"
  from_port   = 80
  to_port     = 80
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_redis" {
  security_group_id            = aws_security_group.ec2_sg.id
  referenced_security_group_id = aws_security_group.redis_sg.id

  description = "Redis from EC2"
  ip_protocol = "tcp"
  from_port   = 6379
  to_port     = 6379
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_DB" {
  security_group_id            = aws_security_group.ec2_sg.id
  referenced_security_group_id = aws_security_group.DB_sg.id

  description = "Database from EC2"
  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}

resource "aws_vpc_security_group_ingress_rule" "db_from_ec2" {
  security_group_id            = aws_security_group.DB_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id

  description = "Database frrom EC2"
  ip_protocol = "tcp"
  from_port   = 5432
  to_port     = 5432
}

# Security Group for Redis
resource "aws_vpc_security_group_ingress_rule" "redis_from_ec2" {
  security_group_id            = aws_security_group.redis_sg.id
  referenced_security_group_id = aws_security_group.ec2_sg.id

  description = "Redis from EC2"
  ip_protocol = "tcp"
  from_port   = 6379
  to_port     = 6379
}

resource "aws_vpc_security_group_egress_rule" "redis_to_internet" {
  security_group_id = aws_security_group.redis_sg.id

  description = "Allow all outbound traffic"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}
