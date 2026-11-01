# The FilePipe module: everything ONE environment needs.
# dev, test and prod all call this same module with different variables.

locals {
  name = "filepipe-${var.environment}"
}

data "aws_caller_identity" "current" {}

# Latest Amazon Linux 2023 image, looked up rather than hardcoded
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# ---------------- Network ----------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name}-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${local.name}-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${local.name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "server" {
  name        = "${local.name}-server-sg"
  description = "FilePipe server: SSH from admin IP only"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Outbound to pull images and reach AWS APIs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------- Storage ----------------
resource "aws_s3_bucket" "data" {
  for_each = toset(["input", "output"])
  bucket   = "${local.name}-${each.key}-${data.aws_caller_identity.current.account_id}"
  # Allows destroy in dev/test even if files are inside. Never in prod.
  force_destroy = var.environment != "prod"
}

resource "aws_s3_bucket_versioning" "data" {
  for_each = aws_s3_bucket.data
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  for_each = aws_s3_bucket.data
  bucket   = each.value.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  for_each                = aws_s3_bucket.data
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------- Permissions for the server ----------------
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name               = "${local.name}-server-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# Least privilege: read input, write output, write logs, pull images. Nothing else.
data "aws_iam_policy_document" "server" {
  statement {
    sid       = "ReadInput"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [aws_s3_bucket.data["input"].arn, "${aws_s3_bucket.data["input"].arn}/*"]
  }
  statement {
    sid       = "WriteOutput"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data["output"].arn}/*"]
  }
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${aws_cloudwatch_log_group.app.arn}:*"]
  }
  statement {
    sid = "PullImages"
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "server" {
  name   = "${local.name}-server-policy"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server.json
}

resource "aws_iam_instance_profile" "server" {
  name = "${local.name}-server-profile"
  role = aws_iam_role.server.name
}

# ---------------- Server ----------------
resource "aws_key_pair" "admin" {
  key_name   = "${local.name}-admin"
  public_key = var.ssh_public_key
}

resource "aws_instance" "server" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.server.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name
  key_name               = aws_key_pair.admin.key_name

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only: a common security standard
    http_put_response_hop_limit = 2          # lets Docker containers reach the server's role
  }

  root_block_device {
    encrypted   = true
    volume_size = 8
  }

  tags = { Name = "${local.name}-server" }
}

# ---------------- Monitoring ----------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/filepipe/${var.environment}"
  retention_in_days = var.log_retention_days
}

# Count every log line where the app reports a failure
resource "aws_cloudwatch_log_metric_filter" "failures" {
  name           = "${local.name}-failures"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name      = "FilePipeErrors"
    namespace = "FilePipe/${var.environment}"
    value     = "1"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email # you must click the confirm link in the email
}

resource "aws_cloudwatch_metric_alarm" "failures" {
  alarm_name          = "${local.name}-run-failed"
  alarm_description   = "FilePipe logged an error. See runbook: docs/runbook.md"
  namespace           = "FilePipe/${var.environment}"
  metric_name         = "FilePipeErrors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}