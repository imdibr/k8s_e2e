# modules/vpc/main.tf
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "devops-intern-vpc" }
}

data "aws_availability_zones" "azs" {}

# Public subnets
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  map_public_ip_on_launch = true
  tags = {
    Name                                        = "public-${count.index+1}"
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/devops-intern-cluster" = "shared"
  }
}

# Private subnets 
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  availability_zone = data.aws_availability_zones.azs.names[count.index]
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, 10 + count.index)
  tags = {
    Name                                        = "private-${count.index+1}"
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/devops-intern-cluster" = "shared"
  }
}

# IGW for public subnets
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "devops-intern-igw" }
}

# Elastic IP
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# NAT Gateway 
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public[0].id
  tags = { Name = "devops-intern-nat" }
}

# RT for public subnets
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}
resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

# RT for private subnets
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "private-rt" }
}
resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private_rt.id
}
