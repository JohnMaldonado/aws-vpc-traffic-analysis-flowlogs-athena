###############################################################################
# Assignment 15 – VPC Flow Logs Analysis with Athena
# Student: Hector Jonathan Maldonado Vega | Batch 10.28
###############################################################################

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###############################################################################
# S3 BUCKET – Flow Logs destination (Parquet)
###############################################################################
resource "aws_s3_bucket" "flow_logs" {
  bucket        = "${var.prefix}-flow-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(var.common_tags, { Name = "${var.prefix}-flow-logs" })
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket                  = aws_s3_bucket.flow_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athena query results bucket
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.prefix}-athena-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = merge(var.common_tags, { Name = "${var.prefix}-athena-results" })
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

###############################################################################
# IAM ROLE – VPC Flow Logs → S3
###############################################################################
resource "aws_iam_role" "flow_logs" {
  name = "${var.prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "flow_logs_s3" {
  name = "${var.prefix}-flow-logs-s3-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketPolicy"
        ]
        Resource = [
          aws_s3_bucket.flow_logs.arn,
          "${aws_s3_bucket.flow_logs.arn}/*"
        ]
      }
    ]
  })
}

###############################################################################
# VPC
###############################################################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, { Name = "${var.prefix}-vpc" })
}

###############################################################################
# SUBNETS
###############################################################################
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, { Name = "${var.prefix}-public-subnet", Tier = "Public" })
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = merge(var.common_tags, { Name = "${var.prefix}-private-subnet", Tier = "Private" })
}

###############################################################################
# INTERNET GATEWAY + NAT GATEWAY
###############################################################################
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.common_tags, { Name = "${var.prefix}-igw" })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.common_tags, { Name = "${var.prefix}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.main]

  tags = merge(var.common_tags, { Name = "${var.prefix}-nat-gw" })
}

###############################################################################
# ROUTE TABLES
###############################################################################
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, { Name = "${var.prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.common_tags, { Name = "${var.prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# SECURITY GROUPS
###############################################################################

# Public instance SG – SSH from internet, ICMP, HTTP/HTTPS out
resource "aws_security_group" "public_ec2" {
  name        = "${var.prefix}-public-sg"
  description = "Security group for public EC2 instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from trusted IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.trusted_cidr_blocks
  }

  ingress {
    description = "ICMP from VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.prefix}-public-sg" })
}

# Private instance SG – SSH from VPC only, ICMP from VPC
resource "aws_security_group" "private_ec2" {
  name        = "${var.prefix}-private-sg"
  description = "Security group for private EC2 instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "ICMP from VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.prefix}-private-sg" })
}

###############################################################################
# KEY PAIR
###############################################################################
resource "aws_key_pair" "main" {
  key_name   = "${var.prefix}-key"
  public_key = var.public_key_material

  tags = var.common_tags
}

###############################################################################
# EC2 INSTANCES
###############################################################################
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "public" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.public_ec2.id]
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    # Traffic generation tools
    yum install -y wget curl nmap-ncat
    echo "Public instance ready" > /home/ec2-user/ready.txt
  EOF
  )

  tags = merge(var.common_tags, { Name = "${var.prefix}-public-ec2", Role = "Public" })
}

resource "aws_instance" "private" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.private_ec2.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y wget curl
    echo "Private instance ready" > /home/ec2-user/ready.txt
  EOF
  )

  tags = merge(var.common_tags, { Name = "${var.prefix}-private-ec2", Role = "Private" })
}

###############################################################################
# VPC FLOW LOGS → S3 (Parquet format)
###############################################################################
resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"                  # ACCEPT + REJECT
  log_destination_type = "s3"
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_format           = var.flow_log_format

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true           # creates dt=YYYY-MM-DD/hour=HH paths
    per_hour_partition         = true
  }

  tags = merge(var.common_tags, { Name = "${var.prefix}-flow-log" })
}

###############################################################################
# ATHENA – Workgroup + Database
###############################################################################
resource "aws_athena_workgroup" "main" {
  name          = "${var.prefix}-workgroup"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }
  }

  tags = var.common_tags
}

resource "aws_athena_database" "flow_logs" {
  name   = replace("${var.prefix}_flowlogs_db", "-", "_")
  bucket = aws_s3_bucket.athena_results.bucket

  force_destroy = true
}

###############################################################################
# ATHENA – Flow Logs table (CREATE TABLE DDL as named query)
###############################################################################
resource "aws_athena_named_query" "create_table" {
  name      = "${var.prefix}-01-create-table"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    CREATE EXTERNAL TABLE IF NOT EXISTS vpc_flow_logs (
      version              int,
      account_id           string,
      interface_id         string,
      srcaddr              string,
      dstaddr              string,
      srcport              int,
      dstport              int,
      protocol             bigint,
      packets              bigint,
      bytes                bigint,
      start                bigint,
      end                  bigint,
      action               string,
      log_status           string,
      vpc_id               string,
      subnet_id            string,
      instance_id          string,
      tcp_flags            int,
      type                 string,
      pkt_srcaddr          string,
      pkt_dstaddr          string,
      region               string,
      az_id                string,
      sublocation_type     string,
      sublocation_id       string,
      pkt_src_aws_service  string,
      pkt_dst_aws_service  string,
      flow_direction       string,
      traffic_path         int
    )
    PARTITIONED BY (
      `aws-account-id`  string,
      `aws-service`     string,
      `aws-region`      string,
      `year`            string,
      `month`           string,
      `day`             string,
      `hour`            string
    )
    ROW FORMAT SERDE 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe'
    STORED AS
      INPUTFORMAT  'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat'
      OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat'
    LOCATION 's3://${aws_s3_bucket.flow_logs.bucket}/AWSLogs/'
    TBLPROPERTIES (
      'classification'       = 'parquet',
      'projection.enabled'   = 'true',
      'projection.year.type' = 'integer',
      'projection.year.range'= '2024,2030',
      'projection.month.type'= 'integer',
      'projection.month.range' = '1,12',
      'projection.month.digits' = '2',
      'projection.day.type'  = 'integer',
      'projection.day.range' = '1,31',
      'projection.day.digits'= '2',
      'projection.hour.type' = 'integer',
      'projection.hour.range'= '0,23',
      'projection.hour.digits'= '2',
      'storage.location.template' = 's3://${aws_s3_bucket.flow_logs.bucket}/AWSLogs/$${aws-account-id}/vpcflowlogs/$${aws-region}/$${year}/$${month}/$${day}/$${hour}/'
    );
  SQL

  description = "Create the VPC flow logs Parquet table with partition projection"
}

###############################################################################
# ATHENA – Named Queries (analysis)
###############################################################################
resource "aws_athena_named_query" "top10_src_ips" {
  name      = "${var.prefix}-02-top10-source-ips"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    -- Top 10 source IPs by total bytes transferred
    SELECT
      srcaddr                       AS source_ip,
      COUNT(*)                      AS flow_count,
      SUM(bytes)                    AS total_bytes,
      SUM(packets)                  AS total_packets,
      ROUND(SUM(bytes) / 1048576.0, 2) AS total_mb
    FROM vpc_flow_logs
    WHERE action = 'ACCEPT'
      AND srcaddr NOT IN ('-')
    GROUP BY srcaddr
    ORDER BY total_bytes DESC
    LIMIT 10;
  SQL

  description = "Top 10 source IPs ranked by bytes transferred"
}

resource "aws_athena_named_query" "reject_actions" {
  name      = "${var.prefix}-03-all-reject-actions"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    -- All REJECT actions (blocked traffic – potential security events)
    SELECT
      from_unixtime(start)          AS event_time,
      srcaddr                       AS source_ip,
      dstaddr                       AS destination_ip,
      srcport                       AS src_port,
      dstport                       AS dst_port,
      CASE protocol
        WHEN 6   THEN 'TCP'
        WHEN 17  THEN 'UDP'
        WHEN 1   THEN 'ICMP'
        ELSE CAST(protocol AS varchar)
      END                           AS protocol_name,
      bytes,
      packets,
      interface_id,
      vpc_id
    FROM vpc_flow_logs
    WHERE action = 'REJECT'
    ORDER BY start DESC
    LIMIT 1000;
  SQL

  description = "All REJECT traffic – potential security events"
}

resource "aws_athena_named_query" "traffic_between_ips" {
  name      = "${var.prefix}-04-traffic-between-ips"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    -- Traffic between two specific IPs (replace placeholders)
    SELECT
      from_unixtime(start)          AS event_time,
      srcaddr,
      dstaddr,
      srcport,
      dstport,
      CASE protocol
        WHEN 6   THEN 'TCP'
        WHEN 17  THEN 'UDP'
        WHEN 1   THEN 'ICMP'
        ELSE CAST(protocol AS varchar)
      END                           AS protocol_name,
      action,
      bytes,
      packets
    FROM vpc_flow_logs
    WHERE (srcaddr = '10.0.1.0' AND dstaddr = '10.0.2.0')  -- replace with actual IPs
       OR (srcaddr = '10.0.2.0' AND dstaddr = '10.0.1.0')  -- bidirectional
    ORDER BY start DESC;
  SQL

  description = "Traffic between two specific IPs (bidirectional)"
}

resource "aws_athena_named_query" "port22_connections" {
  name      = "${var.prefix}-05-port22-ssh-connections"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    -- All SSH connections (port 22) – accepted and rejected
    SELECT
      from_unixtime(start)          AS event_time,
      srcaddr                       AS source_ip,
      dstaddr                       AS destination_ip,
      action,
      bytes,
      packets,
      interface_id,
      CASE tcp_flags
        WHEN 2  THEN 'SYN'
        WHEN 18 THEN 'SYN-ACK'
        WHEN 4  THEN 'RST'
        WHEN 1  THEN 'FIN'
        ELSE CAST(tcp_flags AS varchar)
      END                           AS tcp_flag_name
    FROM vpc_flow_logs
    WHERE dstport = 22
      AND protocol = 6
    ORDER BY start DESC;
  SQL

  description = "All connections to port 22 (SSH)"
}

resource "aws_athena_named_query" "traffic_by_protocol" {
  name      = "${var.prefix}-06-traffic-by-protocol"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    -- Traffic breakdown by protocol (TCP / UDP / ICMP / Other)
    SELECT
      CASE protocol
        WHEN 6   THEN 'TCP'
        WHEN 17  THEN 'UDP'
        WHEN 1   THEN 'ICMP'
        ELSE CONCAT('Other (', CAST(protocol AS varchar), ')')
      END                               AS protocol_name,
      COUNT(*)                          AS flow_count,
      SUM(bytes)                        AS total_bytes,
      SUM(packets)                      AS total_packets,
      ROUND(SUM(bytes) * 100.0 / SUM(SUM(bytes)) OVER (), 2) AS pct_bytes,
      SUM(CASE WHEN action = 'ACCEPT' THEN 1 ELSE 0 END) AS accepted,
      SUM(CASE WHEN action = 'REJECT' THEN 1 ELSE 0 END) AS rejected
    FROM vpc_flow_logs
    WHERE protocol IS NOT NULL
    GROUP BY protocol
    ORDER BY total_bytes DESC;
  SQL

  description = "Traffic volume by protocol (TCP/UDP/ICMP/Other)"
}

resource "aws_athena_named_query" "cost_estimate" {
  name      = "${var.prefix}-07-data-scanned-cost"
  workgroup = aws_athena_workgroup.main.id
  database  = aws_athena_database.flow_logs.name
  query     = <<-SQL
    -- Estimate Athena cost: $5 per TB scanned (Parquet saves ~80% vs CSV)
    -- Run this AFTER other queries in same session to see cumulative scan
    SELECT
      workgroup_name,
      SUM(data_scanned_in_bytes)             AS total_bytes_scanned,
      ROUND(SUM(data_scanned_in_bytes) / POWER(1024,3), 4) AS gb_scanned,
      ROUND(SUM(data_scanned_in_bytes) / POWER(1024,4), 6) AS tb_scanned,
      ROUND(SUM(data_scanned_in_bytes) / POWER(1024,4) * 5.0, 6) AS estimated_cost_usd
    FROM information_schema.__internal_partitions__
    WHERE table_schema = '${aws_athena_database.flow_logs.name}'
    GROUP BY workgroup_name;
  SQL

  description = "Estimate Athena query cost from data scanned"
}
