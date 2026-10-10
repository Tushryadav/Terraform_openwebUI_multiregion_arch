# EC2 IAM Role
resource "aws_iam_role" "ec2" {
  name = "portfolio-ec2-role-${var.region_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# EC2 Instance Profile
resource "aws_iam_instance_profile" "ec2" {
  name = "portfolio-ec2-profile-${var.region_name}"
  role = aws_iam_role.ec2.name
}
