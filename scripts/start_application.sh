#!/bin/bash
cd /app
docker pull ${REPOSITORY_URI}:${IMAGE_TAG}
docker run -d -p 5000:5000 ${REPOSITORY_URI}:${IMAGE_TAG} 