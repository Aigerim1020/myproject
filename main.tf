terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region  = "us-east-1"
} 

resource "aws_vpc" "basic_vpc" {
  cidr_block       = "10.0.0.0/16"
   enable_dns_support = "true"
    enable_dns_hostnames = "true"
  instance_tenancy = "default"

  tags = {
    Name = "vpc-basic-terraform"

  }
}
resource "aws_subnet" "public_subnet1" {
  vpc_id     = aws_vpc.basic_vpc.id
  cidr_block = "10.0.0.0/24"
  map_public_ip_on_launch = "true" # This is what makes it a public subnet
    availability_zone = "us-east-1a"

  tags = {
    Name = "public-subnet-A"
  }
}

resource "aws_subnet" "public_subnet2" {
  vpc_id     = aws_vpc.basic_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = "true" # This is what makes it a public subnet
    availability_zone = "us-east-1b"

  tags = {
    Name = "public-subnet-B"
  }
}

resource "aws_subnet" "private_subnet1" {
  vpc_id     = aws_vpc.basic_vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet-A"
  }
}

resource "aws_subnet" "private_subnet2" {
  vpc_id     = aws_vpc.basic_vpc.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-subnet-B"
  }
}
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.basic_vpc.id

  tags = {
    Name = "BasicVPC-IGW"
  }
}
resource "aws_route_table" "route_table" {

    vpc_id = aws_vpc.basic_vpc.id
    route {

        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.gw.id
    }


    tags = {

        Name = "My-Public-Routing-Table"
    }
}
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_subnet2.id
  route_table_id = aws_route_table.route_table.id
}


resource "aws_route_table_association" "private-subnet-A"{
    subnet_id = aws_subnet.private_subnet1.id
    route_table_id = aws_route_table.route_table.id
}

resource "aws_route_table_association" "private-subnet-B"{
    subnet_id = aws_subnet.private_subnet2.id
    route_table_id = aws_route_table.route_table.id
}


resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
  description = "Allow ssh inbound traffic"

  # using default VPC
  vpc_id = aws_vpc.basic_vpc.id

  ingress {
    description = "TLS from VPC"

    # we should allow incoming and outoging
    # TCP packets
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    # allow all traffic
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_ssh"
  }
}


resource "aws_instance" "instance1" {
  ami                         = "ami-016eb5d644c333ccb"
  instance_type               = "t2.micro"
  subnet_id = aws_subnet.public_subnet2.id
  vpc_security_group_ids = [ aws_security_group.allow_ssh.id ]
  associate_public_ip_address = true
  source_dest_check           = false
  key_name                    = "ec2"
  
  # root disk
  root_block_device {
    volume_size           = "20"
    volume_type           = "gp2"
    encrypted             = true
    delete_on_termination = true
  }
  # data disk
  ebs_block_device {
    device_name           = "/dev/xvda"
    volume_size           = "20"
    volume_type           = "gp2"
    encrypted             = true
    delete_on_termination = true
  }
  
  tags = {
    Name        = "cloud-dev-web-server"
    Environment = "dev"
  }
}


resource "aws_security_group" "alb-sg" {
  name        = "allow_http"
  description = "Allow inbound traffic"
  vpc_id = aws_vpc.basic_vpc.id

  ingress {
    description      = "HTTP from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_lb_target_group" "alb-tg" {
  name     = "tf-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.basic_vpc.id
   
    health_check {
   enabled =  true
    path = "/"
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 2
    interval = 30
    matcher = "200"  # has to be HTTP 200 or fails
  }
}

resource "aws_lb" "test" {
name         =  "alb-test"
internal = false
load_balancer_type = "application"
security_groups = [ aws_security_group.alb-sg.id ]
subnets = [ aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id ]
enable_deletion_protection = true

tags = {
  enviroment = "staging"
}
}

resource "aws_lb_listener" "applb" {
  load_balancer_arn = aws_lb.test.id
  port         = "80"
  protocol = "HTTP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.alb-tg.id
  }
}

resource "aws_security_group" "instance2" {
  name        = "allow"
  description = "inbound traffic"
  vpc_id = aws_vpc.basic_vpc.id

  ingress {
    description      = "TLS from VPC"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "SSH from VPC"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "allow_tls"
  }
}

# Launch Template Resource
resource "aws_launch_template" "my_launch_template" {
  name = "my-launch-template"
  description = "My Launch Template"
  image_id = "ami-016eb5d644c333ccb"
  instance_type = "t2.micro"
  vpc_security_group_ids = [ aws_security_group.instance2.id ]
  key_name = "ec2"
  update_default_version = true
  user_data = filebase64("userdata1.sh")

tags = {
      Name = "myasg"
    }
}


 # Autoscaling Group Resource
resource "aws_autoscaling_group" "my_asg" {
  name_prefix = "myasg-"
  desired_capacity   = 2
  max_size           = 6
  min_size           = 2
  vpc_zone_identifier = [ aws_subnet.private_subnet1.id, aws_subnet.private_subnet2.id ]
  health_check_type = "ELB"
  #health_check_grace_period = 300 # default is 300 seconds  
  # Launch Template
  launch_template {
    id = aws_launch_template.my_launch_template.id
    version = aws_launch_template.my_launch_template.latest_version
  }    
}


resource "aws_s3_bucket" "test" {
  bucket = "aigerim-test-bucket"

  tags = {
    Name        = "My bucket-images"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.test.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket-config" {

  bucket = aws_s3_bucket.test.id

  rule {
    id = "archival"

    filter {
      and {
        prefix = "/"

        tags = {
          rule      = "archival"
          autoclean = "false"
        }
      }
    }

    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}



resource "aws_s3_bucket" "log" {
  bucket = "aigerim-log-bucket"

  tags = {
    Name        = "My bucket-log"
    Environment = "Dev"
  }
}

resource "aws_s3_bucket_versioning" "version" {
  bucket = aws_s3_bucket.log.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_lifecycle_configuration" "bucket-con" {

  bucket = aws_s3_bucket.log.id

  rule {
    id = "archival"

    filter {
      and {
        prefix = "/"

        tags = {
          rule      = "archival"
          autoclean = "false"
        }
      }
    }

    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}



