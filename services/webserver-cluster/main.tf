# Backend Configuration to S3
terraform {
  backend "s3" {
      key    = "stage/services/webserver-cluster/terraform.tfstate"
    
  }
}

# Locals Values #

locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

# My template File data
data "template_file" "user_data" {
  template = file("${path.module}/user-data.sh")

  vars = {
    server_port = var.server_port
    db_address  = data.terraform_remote_state.db.outputs.address
    db_port     = data.terraform_remote_state.db.outputs.port
  }
  
}

# Remote State Configuration
data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "us-east-2"
  }
  
}
#----------------------------------------
data "aws_vpc" "default" {
    default = true
  
}

data "aws_subnet_ids" "default" {
    vpc_id = data.aws_vpc.default.id
  
}

# My Lauch Configuration
resource "aws_launch_configuration" "example" {
    image_id               = "ami-07a0844029df33d7d"
    instance_type          = var.instance_type
    security_groups        = [aws_security_group.instace.id]
    user_data              = data.template_file.user_data.rendered

    
    
    # Requiered when using a lunch configuration with an auto scaling group.
    lifecycle {
      create_before_destroy = true
    }

  
}

# My Auto Scaling Group
resource "aws_autoscaling_group" "example" {
    launch_configuration = aws_launch_configuration.example.name
    vpc_zone_identifier  = data.aws_subnet_ids.default.ids 

    target_group_arns = [aws_lb_target_group.asg.arn]
    health_check_type = "ELB"

    min_size = var.min_size
    max_size = var.max_size

    tag {
      key                 = "Name"
      value               = var.cluster_name
      propagate_at_launch = true
    }
  
}

# My load Balancer
resource "aws_lb" "example" {
    name               = "${var.cluster_name}-lb"
    load_balancer_type = "application"
    subnets            = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.alb.id]
  
}

# My HTTP listern on Port 80
resource "aws_lb_listener" "http" {
    load_balancer_arn = aws_lb.example.arn
    port              = local.http_port
    protocol          = "HTTP"

    #By default, return a simple 404 page
    default_action {
      type = "fixed-response"

      fixed_response {
        content_type = "text/plain"
        message_body = "404: page not found"
        status_code  = 404
      }
    }
  
}

# My Targer Group

resource "aws_lb_target_group" "asg" {
    name = "${var.cluster_name}-asg"
    port = var.server_port
    protocol = "HTTP"
    vpc_id = data.aws_vpc.default.id

    health_check {
      path = "/"
      protocol = "HTTP"
      matcher = "200"
      interval = 15
      timeout = 3
      healthy_threshold = 2
      unhealthy_threshold = 2
    }
  
}

# Tu put it all toghether now:

resource "aws_lb_listener_rule" "asg" {
    listener_arn = aws_lb_listener.http.arn
    priority     = 100

    condition {
      path_pattern {
        values = [ "*" ]
      }
    }

    action {
      type = "forward"
      target_group_arn = aws_lb_target_group.asg.arn
    }
  
}

resource "aws_security_group" "alb" {
    name = "${var.cluster_name}-alb" 
  
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id
  
  #Allow inbound HTTP request
  cidr_blocks = local.all_ips
  from_port = local.http_port
  protocol = local.tcp_protocol
  to_port = local.http_port
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id
  
  #Allow Outbound traffic
  cidr_blocks = local.all_ips
  from_port = local.http_port
  protocol = local.tcp_protocol
  to_port = local.http_port
}

resource "aws_security_group" "instace" {
    name = "${var.cluster_name}-instance"

    ingress {
      cidr_blocks = local.all_ips
      description = "Ingress Rule"
      from_port = var.server_port
      protocol = local.tcp_protocol
      to_port = var.server_port
    } 
  
}