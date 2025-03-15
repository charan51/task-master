provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "security_ai" {
  ami           = "ami-08b5b3a93ed654d19" # Update with correct AMI ID
  instance_type = "t2.medium"

  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              docker run -d -p 5000:5000 ai-threat-detection
              EOF

  tags = {
    Name = "Security-AI-Instance"
  }
}
# Random string for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket for pipeline artifacts
resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "ai-threat-detection-artifacts-${random_string.suffix.result}"
  force_destroy = true
}

# ECR Repository
resource "aws_ecr_repository" "ai_threat_repo" {
  name                 = "ai-threat-detection-${random_string.suffix.result}"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

# IAM Role for CodePipeline
resource "aws_iam_role" "codepipeline_role" {
  name = "codepipeline-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "codepipeline.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_full_access" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodePipeline_FullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_s3" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_ecr" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

resource "aws_iam_role_policy_attachment" "codepipeline_codebuild" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
}

resource "aws_iam_role_policy" "codepipeline_codestar" {
  name   = "codepipeline-codestar-policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection"]
        Resource = aws_codestarconnections_connection.github_connection.arn
      }
    ]
  })
}

# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-role-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "codebuild.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeBuildAdminAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_s3" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
}

# CodeBuild Project
resource "aws_codebuild_project" "ai_threat_build" {
  name          = "ai-threat-detection-build-${random_string.suffix.result}"
  service_role  = aws_iam_role.codebuild_role.arn
  artifacts {
    type = "CODEPIPELINE"
  }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = aws_ecr_repository.ai_threat_repo.repository_url
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

# CodeStar Connection to GitHub
resource "aws_codestarconnections_connection" "github_connection" {
  name          = "github-connection-${random_string.suffix.result}"
  provider_type = "GitHub"
}

# CodePipeline
resource "aws_codepipeline" "ai_threat_pipeline" {
  name     = "ai-threat-detection-pipeline-${random_string.suffix.result}"
  role_arn = aws_iam_role.codepipeline_role.arn
  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }
  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId = "charan51/task-master"
        BranchName       = "main"
      }
    }
  }
  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.ai_threat_build.name
      }
    }
  }
}

# Security Group for EC2
resource "aws_security_group" "security_ai_sg" {
  name        = "security-ai-sg-${random_string.suffix.result}"
  description = "Allow SSH and port 5000"
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to your IP in production
  }
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to your IP in production
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance with New Name
resource "aws_instance" "security_ai_new" {
  ami                    = "ami-08b5b3a93ed654d19"  # Amazon Linux 2 AMI
  instance_type          = "t2.medium"
  vpc_security_group_ids = [aws_security_group.security_ai_sg.id]
  user_data              = <<-EOF
                          #!/bin/bash
                          yum update -y
                          yum install -y docker
                          systemctl start docker
                          systemctl enable docker
                          aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${aws_ecr_repository.ai_threat_repo.repository_url}
                          docker run -d -p 5000:5000 ${aws_ecr_repository.ai_threat_repo.repository_url}:latest
                          EOF
  tags = {
    Name = "Security-AI-Instance-New"
  }
}

# Outputs
output "codepipeline_name" {
  value = aws_codepipeline.ai_threat_pipeline.name
}

output "codestar_connection_arn" {
  value = aws_codestarconnections_connection.github_connection.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.ai_threat_repo.repository_url
}

output "ec2_public_ip" {
  value = aws_instance.security_ai_new.public_ip  # Updated to reference new name
}