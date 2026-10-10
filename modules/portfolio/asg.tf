# Auto Scaling Group
resource "aws_autoscaling_group" "web" {
  name                      = "portfolio-asg-${var.region_name}"
  vpc_zone_identifier       = aws_subnet.private[*].id
  target_group_arns         = [aws_lb_target_group.web.arn]
  min_size                  = 2
  max_size                  = 3
  desired_capacity          = 2
  health_check_type         = "ELB"
  health_check_grace_period = 600
  wait_for_elb_capacity     = 2
  wait_for_capacity_timeout = "25m"

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }
}
