#!/bin/bash
set -e  # Exit on error
set -x  # Print commands as they're executed

echo "Starting application deployment..."

# Stop any existing containers
echo "Stopping existing containers..."
docker stop $(docker ps -a -q) 2>/dev/null || true
docker rm $(docker ps -a -q) 2>/dev/null || true

# Get AWS region and account ID
echo "Getting AWS metadata..."
AWS_REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
if [ -z "$AWS_REGION" ]; then
    echo "Failed to get AWS region"
    exit 1
fi

AWS_ACCOUNT_ID=$(curl -s http://169.254.169.254/latest/meta-data/identity-credentials/ec2/info | grep -o '"accountId" *: *"[^"]*"' | cut -d'"' -f4)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "Failed to get AWS account ID"
    exit 1
fi

# Set repository URI
REPOSITORY_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/threat-detection"
echo "Repository URI: ${REPOSITORY_URI}"

# Login to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${REPOSITORY_URI}

# Pull the latest image
echo "Pulling latest image..."
docker pull ${REPOSITORY_URI}:latest

# Run the container
echo "Starting container..."
docker run -d --name threat-detection \
    --restart always \
    -p 5000:5000 \
    ${REPOSITORY_URI}:latest

# Wait for container to start
echo "Waiting for container to start..."
sleep 5

# Check if container is running
if [ "$(docker ps -q -f name=threat-detection)" ]; then
    echo "Container started successfully"
    docker ps
    docker logs threat-detection
else
    echo "Container failed to start"
    echo "Docker logs:"
    docker logs threat-detection
    echo "Docker PS output:"
    docker ps -a
    echo "System logs:"
    journalctl -u docker.service --no-pager | tail -n 50
    exit 1
fi

# Test the application
echo "Testing application..."
curl -f http://localhost:5000/health || {
    echo "Health check failed"
    docker logs threat-detection
    exit 1
}

echo "Deployment completed successfully" 