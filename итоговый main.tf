# Определение провайдера
provider "aws" {
  region = "eu-central-1"
}

# Создание VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/18"
  tags = {
    Name = "main-vpc"
  }
}

# Создание публичной подсети
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "public-subnet"
  } 
}

# Создание приватной подсети
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "private-subnet"
  }
}

# Создание второй приватной подсети для балансировщика
resource "aws_subnet" "private_subnet_2" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.3.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "private-subnet-2"
  }
}

# Создание Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# Создание маршрутизационной таблицы для публичной подсети
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Ассоциация маршрутизационной таблицы с публичной подсетью
resource "aws_route_table_association" "public_route_table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Ассоциация маршрутизационной таблицы с приватной подсетью 2
resource "aws_route_table_association" "private2_route_table_association" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_route_table.id
}

# Создание Elastic IP для NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

# Создание NAT Gateway в публичной подсети
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_subnet.id

  depends_on = [aws_internet_gateway.main]
}

# Создание маршрутизационной таблицы для приватной подсети
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "private-route-table"
  }
}

# Ассоциация маршрутизационной таблицы с приватной подсетью
resource "aws_route_table_association" "private_route_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# Создание security group с доступом по SSH (порт 22)
resource "aws_security_group" "allow_ssh" {
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group для ALB
resource "aws_security_group" "alb_sg" {
  vpc_id = aws_vpc.main.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# Security Group для базы данных RDS
resource "aws_security_group" "rds_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/18"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# Создание Launch Template
resource "aws_launch_template" "example" {
  name_prefix   = "example-launch-template"
  image_id      = "ami-04f76ebf53292ef4d"
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.allow_ssh.id]
    subnet_id                   = aws_subnet.private_subnet.id
  }

  tags = {
    Name = "example-instance"
  }
}

# Создание Auto Scaling Group
resource "aws_autoscaling_group" "example" {
  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }

  min_size           = 3
  max_size           = 4
  desired_capacity   = 3
  vpc_zone_identifier = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]

  tag {
    key                 = "Name"
    value               = "my-instance"
    propagate_at_launch = true
  }

  target_group_arns = [aws_lb_target_group.private_tg.arn]

  lifecycle {
    create_before_destroy = true
  }
}

# Создание приватного Application Load Balancer (ALB)
resource "aws_lb" "private_alb" {
  name               = "private-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "private-alb"
  }
}

# Target Group для ALB
resource "aws_lb_target_group" "private_tg" {
  name     = "private-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
    matcher             = "200"
  }

  tags = {
    Name = "private-target-group"
  }
}

# Listener для ALB
resource "aws_lb_listener" "private_listener" {
  load_balancer_arn = aws_lb.private_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.private_tg.arn
  }

  tags = {
    Name = "private-listener"
  }
}

# Настройка для базы данных RDS (PostgreSQL)
resource "aws_db_instance" "postgres_instance" {
  allocated_storage    = 20 # ГБ
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = "db.t4g.micro"
  db_name              = "mydb"
  username             = "Mary"
  password             = "zefir50612"
  parameter_group_name = "default.postgres16"
  skip_final_snapshot  = true
  publicly_accessible  = false
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name = aws_db_subnet_group.rds_subnet_group.name

  tags = {
    Name = "rds-postgres"
  }
}

# Привязка подсетей для RDS
resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_subnet.id, aws_subnet.private_subnet_2.id]

  tags = {
    Name = "rds-subnet-group"
  }
}
