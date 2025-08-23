#!/bin/bash
set -e

# Parameters
ENV=$1
HOST=$2
USER=$3
DEPLOY_PATH=$4
ARTIFACT_PATH="./artifacts"

echo "Starting deployment to $ENV environment on host $HOST"

# Find the JAR file
JAR_FILE=$(find $ARTIFACT_PATH -name "*.jar" | head -n 1)

if [ -z "$JAR_FILE" ]; then
    echo "No JAR file found in artifacts"
    exit 1
fi

echo "Found artifact: $JAR_FILE"

# Create deployment directory on remote host
ssh -o StrictHostKeyChecking=no $USER@$HOST \
    "mkdir -p $DEPLOY_PATH && mkdir -p $DEPLOY_PATH/backups"

# Create backup of current deployment
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ssh -o StrictHostKeyChecking=no $USER@$HOST \
    "cd $DEPLOY_PATH && if [ -f *.jar ]; then mv *.jar backups/hello-world-backup-$TIMESTAMP.jar; fi"

# Transfer the JAR file
echo "Uploading artifact to $HOST..."
scp -o StrictHostKeyChecking=no $JAR_FILE $USER@$HOST:$DEPLOY_PATH/

# Create environment file
echo "Creating environment configuration for $ENV"
cat > deploy.env << EOF
DEPLOY_ENV=$ENV
DEPLOY_TIMESTAMP=$(date)
GIT_COMMIT=${{ github.event.workflow_run.head_sha }}
EOF

scp -o StrictHostKeyChecking=no deploy.env $USER@$HOST:$DEPLOY_PATH/

# Create startup script
echo "Creating startup script"
cat > start-app.sh << 'EOF'
#!/bin/bash
cd $(dirname "$0")
nohup java -jar hello-world-*.jar > app.log 2>&1 &
echo $! > app.pid
EOF

chmod +x start-app.sh
scp -o StrictHostKeyChecking=no start-app.sh $USER@$HOST:$DEPLOY_PATH/

# Stop previous application if running
echo "Stopping previous application"
ssh -o StrictHostKeyChecking=no $USER@$HOST \
    "cd $DEPLOY_PATH && if [ -f app.pid ]; then kill \$(cat app.pid) 2>/dev/null || true; fi"

# Start the application
echo "Starting application on $HOST"
ssh -o StrictHostKeyChecking=no $USER@$HOST \
    "cd $DEPLOY_PATH && chmod +x start-app.sh && ./start-app.sh"

# Verify deployment
echo "Verifying deployment..."
sleep 3
ssh -o StrictHostKeyChecking=no $USER@$HOST \
    "cd $DEPLOY_PATH && ps aux | grep java | grep -v grep"

echo "Deployment to $ENV completed successfully!"
