#!/bin/bash

# Stop any existing containers
docker stop $(docker ps -a -q) 2>/dev/null || true
docker rm $(docker ps -a -q) 2>/dev/null || true

# Get AWS region and account ID
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info | grep -o '"accountId" *: *"[^"]*"' | cut -d'"' -f4)

# Set repository URI
REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/threat-detection"

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${REPOSITORY_URI}

# Pull and run the latest image
docker pull ${REPOSITORY_URI}:latest
docker run -d --name threat-detection --restart always -p 5000:5000 ${REPOSITORY_URI}:latest

# Check if container is running
if [ "$(docker ps -q -f name=threat-detection)" ]; then
    echo "Container started successfully"
else
    echo "Container failed to start"
    docker logs threat-detection
    exit 1
fi 