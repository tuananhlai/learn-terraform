provider "aws" {
  region = "us-east-1"
}

locals {
  # IP address to allow through WAF.
  home_ip_address = "106.167.201.84"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.1"

  name = "SimpleWafVpc"
  azs  = ["us-east-1a", "us-east-1b"]
  cidr = "10.0.0.0/16"
  # A load balancer must be attached to 2 or more subnets in different AZs.
  public_subnets = ["10.0.0.0/20", "10.0.16.0/20"]
}

module "instance_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "InstanceSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 8
      to_port     = 0
      protocol    = "icmp"
      cidr_blocks = "0.0.0.0/0"
    },
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::0/0"
    }
  ]
}

module "lb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.1.0"

  vpc_id          = module.vpc.vpc_id
  name            = "AlbSg"
  use_name_prefix = true

  ingress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  egress_with_cidr_blocks = [
    {
      protocol         = "-1"
      from_port        = 0
      to_port          = 0
      cidr_blocks      = "0.0.0.0/0"
      ipv6_cidr_blocks = "::0/0"
    }
  ]
}

resource "aws_instance" "default" {
  ami                         = "ami-0b5bf7c3d5a739610" #Bitnami Debian with Wordpress
  instance_type               = "t2.micro"
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [module.instance_sg.security_group_id]
  associate_public_ip_address = true
}

locals {
  target_group_port     = 80
  target_group_protocol = "HTTP"
}

resource "aws_alb_target_group" "default" {
  vpc_id   = module.vpc.vpc_id
  port     = local.target_group_port
  protocol = local.target_group_protocol
}

resource "aws_alb_target_group_attachment" "default" {
  target_group_arn = aws_alb_target_group.default.arn
  target_id        = aws_instance.default.id
}

resource "aws_alb" "default" {
  subnets         = module.vpc.public_subnets
  security_groups = [module.lb_sg.security_group_id]
  internal        = false
}

resource "aws_alb_listener" "default" {
  load_balancer_arn = aws_alb.default.arn
  port              = local.target_group_port
  protocol          = local.target_group_protocol
  default_action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.default.arn
  }
}

resource "aws_s3_bucket" "waf_logs" {
  bucket_prefix = "aws-waf-logs-demo"
  force_destroy = true
}

locals {
  managed_rule_group_statements = [
    {
      priority    = 4
      name        = "AWSManagedRulesCommonRuleSet"
      vendor_name = "AWS"
    },
    {
      priority    = 5
      name        = "AWSManagedRulesSQLiRuleSet"
      vendor_name = "AWS"
    },
    {
      priority    = 6
      name        = "AWSManagedRulesPHPRuleSet"
      vendor_name = "AWS"
    },
    {
      priority    = 7
      name        = "AWSManagedRulesWordPressRuleSet"
      vendor_name = "AWS"
    },
  ]
}

resource "aws_wafv2_ip_set" "home" {
  name               = "home-ip"
  ip_address_version = "IPV4"
  scope              = "REGIONAL"
  addresses          = ["${local.home_ip_address}/32"]
}

resource "aws_wafv2_regex_pattern_set" "no_wp_files" {
  name  = "no-wp-files"
  scope = "REGIONAL"

  regular_expression {
    regex_string = "(wp\\-login\\.php)$"
  }
  regular_expression {
    regex_string = "(.*wp\\-config.*)"
  }
  regular_expression {
    regex_string = "(xmlrpc\\.php)"
  }
}

resource "aws_wafv2_web_acl" "default" {
  name  = "wordpress-acl"
  scope = "REGIONAL"

  default_action {
    allow {

    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = false
    metric_name                = "wordpress-acl"
  }

  dynamic "rule" {
    for_each = toset(local.managed_rule_group_statements)

    content {
      name     = "${rule.value.vendor_name}-${rule.value.name}"
      priority = rule.value.priority

      # This is a workaround for the issue below.
      # https://github.com/hashicorp/terraform-provider-aws/issues/29321
      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name
        }
      }

      visibility_config {
        sampled_requests_enabled   = false
        cloudwatch_metrics_enabled = false
        metric_name                = "${rule.value.name}Metric"
      }
    }
  }

  rule {
    name     = "allow-home"
    priority = 1

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.home.arn
      }
    }

    action {
      allow {}
    }

    visibility_config {
      sampled_requests_enabled   = false
      cloudwatch_metrics_enabled = false
      metric_name                = "AllowHomeMetric"
    }
  }

  rule {
    # Block all other countries except for Japan.
    name     = "block-all"
    priority = 2

    statement {
      not_statement {
        statement {
          geo_match_statement {
            country_codes = ["JP"]
          }
        }
      }
    }

    action {
      block {}
    }

    visibility_config {
      sampled_requests_enabled   = false
      cloudwatch_metrics_enabled = false
      metric_name                = "BlockAllMetric"
    }
  }

  rule {
    name     = "allow-jp"
    priority = 8
    statement {
      geo_match_statement {
        country_codes = ["JP"]
      }
    }

    action {
      allow {}
    }

    visibility_config {
      sampled_requests_enabled   = false
      cloudwatch_metrics_enabled = false
      metric_name                = "AllowJpMetric"
    }
  }

  rule {
    name     = "no-wp-files"
    priority = 3

    statement {
      regex_pattern_set_reference_statement {
        arn = aws_wafv2_regex_pattern_set.no_wp_files.arn
        field_to_match {
          uri_path {}
        }
        text_transformation {
          priority = 0
          type     = "LOWERCASE"
        }
      }
    }

    action {
      block {}
    }

    visibility_config {
      sampled_requests_enabled   = false
      cloudwatch_metrics_enabled = false
      metric_name                = "AllowJpMetric"
    }
  }
}

resource "aws_wafv2_web_acl_association" "default" {
  resource_arn = aws_alb.default.arn
  web_acl_arn  = aws_wafv2_web_acl.default.arn
}

# TEST:
# - You can follow the test guide here. https://github.com/acantril/learn-cantrill-io-labs/tree/master/aws-waf#stage-5---testing-our-waf
#   If you choose to do so, be sure to comment out any custom rules (line 225 to 318) to ensure
#   both environments are the same.
