# Fetch current public IP for security group rule
data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

# Ubuntu 22.04 AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] 

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Security Group
resource "aws_security_group" "jenkins_sg" {
  name        = "jenkins-sg"
  description = "Allow SSH and Jenkins HTTP from dynamic admin IP"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from my current IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  ingress {
    description = "Jenkins UI from my current IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jenkins-sg" }
}

# IAM Role for Jenkins
resource "aws_iam_role" "jenkins_role" {
  name = "jenkins-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.jenkins_assume.json
}

data "aws_iam_policy_document" "jenkins_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM policies for Jenkins
resource "aws_iam_role_policy_attachment" "jenkins_ecr" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "jenkins_eks" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "jenkins_worker_node" {
  role       = aws_iam_role.jenkins_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "jenkins-ec2-profile"
  role = aws_iam_role.jenkins_role.name
}

# Jenkins EC2 Instance
resource "aws_instance" "jenkins_server" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name
  key_name                    = "devops-key"
  associate_public_ip_address = true

  tags = { Name = "JenkinsServer" }

  user_data_base64 = base64encode(<<-EOF
#!/bin/bash
set -euxo pipefail

exec > /var/log/user-data.log 2>&1

echo "=== Bootstrap started: $(date) ==="

# 1. Swap (Crucial for t3.micro memory)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 2. Base packages
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl gnupg fontconfig \
  git docker.io unzip jq wget openjdk-17-jre

# 3. Jenkins via .war
mkdir -p /usr/share/jenkins
JENKINS_VERSION=$(curl -fsSL "https://updates.jenkins.io/stable/latestCore.txt")
curl -fsSL "https://updates.jenkins.io/download/war/$JENKINS_VERSION/jenkins.war" \
  -o /usr/share/jenkins/jenkins.war

useradd -m -d /var/lib/jenkins -s /bin/bash jenkins || true
chown -R jenkins:jenkins /var/lib/jenkins /usr/share/jenkins

# Create the Service File
cat > /etc/systemd/system/jenkins.service <<'JENKINS_SERVICE'
[Unit]
Description=Jenkins Automation Server
After=network.target

[Service]
Type=simple
User=jenkins
Group=jenkins
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xmx256m"
ExecStart=/usr/bin/java $JAVA_OPTS -jar /usr/share/jenkins/jenkins.war --httpPort=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
JENKINS_SERVICE

# 4. Docker & Tools
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu
usermod -aG docker jenkins

# AWS CLI (Fixed)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp/awscli
/tmp/awscli/aws/install
rm -rf /tmp/awscli /tmp/awscliv2.zip

# Kubectl
KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLO "https://dl.k8s.io/release/$KVER/bin/linux/amd64/kubectl"
install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# 5. Start Jenkins
systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

echo "=== Bootstrap complete: $(date) ==="
EOF
  )
}
