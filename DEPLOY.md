# Deployment Documentation

## Overview

This project uses a two-stage GitHub Actions deployment system that builds ARM64 releases and deploys them to a dedicated server with zero-downtime deployments.

## Infrastructure

### Server Details
- **Host**: `129.213.36.237`
- **OS**: Ubuntu 24.04 ARM64
- **Domain**: `rss-assistant.codehannah.nyc`
- **Services**: PostgreSQL, Caddy (reverse proxy)

### Users
- **ubuntu**: Default admin user
- **deploy**: Dedicated deployment user with passwordless sudo access

## Deployment Architecture

### GitHub Actions Workflows

#### 1. Build Release (`.github/workflows/release.yml`)
- **Triggers**: Pull requests to main, workflow dispatch, workflow call
- **Runner**: `ubuntu-24.04-arm` (for ARM64 compatibility)
- **Process**:
  1. Sets up Elixir 1.18 + OTP 27
  2. Installs dependencies with caching
  3. Builds production assets
  4. Creates mix release with included ERTS and tarball output
  5. Creates tarball artifact
  6. Uploads artifact for 30 days

#### 2. Deploy (`.github/workflows/deploy.yml`)
- **Triggers**: Pushes to main, workflow dispatch
- **Process**:
  1. Calls build workflow to create release
  2. Downloads release artifact
  3. Uploads tarball to server via SSH
  4. Executes deployment script on server
  5. Comments on PR with deployment URL

### Server Configuration

#### Application Structure
```
/opt/rss-assistant/          # Application directory (owned by deploy:deploy)
├── bin/rss_assistant        # Release binary
├── lib/                     # Application code
├── releases/                # Release metadata
└── ...                      # Other release files
```

#### SystemD Service
- **Service**: `rss-assistant.service`
- **User**: `deploy`
- **Port**: `4000`
- **Environment**:
  - `PHX_SERVER=true`
  - `MIX_ENV=prod`
  - `DATABASE_URL=postgresql://deploy@localhost/rss_assistant`
  - `SECRET_KEY_BASE` (generated per deployment)

#### Database
- **Type**: PostgreSQL
- **Database**: `rss_assistant`
- **User**: `deploy` (superuser role)
- **Authentication**: Trust for localhost connections

#### Reverse Proxy
- **Service**: Caddy
- **Config**: `/etc/caddy/Caddyfile`
- **Routing**: `rss-assistant.codehannah.nyc` → `localhost:4000`
- **TLS**: Automatic via Let's Encrypt

### Deployment Script

The server contains a deployment script at `/home/deploy/deploy.sh` that handles the actual deployment process with zero-downtime and rollback capabilities.

#### Script Features:
- **Zero-downtime deployment**: Service continues running during deployment
- **Backup and rollback**: Creates backup before deployment, rolls back on failure
- **Verification**: Checks service health before considering deployment successful
- **Clean error handling**: Provides clear status messages and handles failures gracefully

## Deployment Process

1. **Build Phase**:
   - GitHub Actions builds ARM64 release with ERTS
   - Creates compressed tarball artifact with automatic tarball generation

2. **Deploy Phase**:
   - Downloads release artifact from GitHub Actions
   - Uploads tarball to server via SSH (using hardcoded host keys)
   - Executes deployment script on server which:
     1. Creates backup of current deployment
     2. Extracts new release to temporary location
     3. Runs database migrations with new release
     4. Replaces old deployment atomically
     5. Restarts service
     6. Verifies service is running
     7. Cleans up or rolls back on failure

## Security Considerations

### SSH Access
- Uses SSH key authentication (stored in `DEPLOY_SSH_KEY` secret)
- Hardcoded host keys in workflow to prevent MITM attacks
- Deploy user has passwordless sudo for service management

### Database Security
- PostgreSQL configured with trust authentication for localhost
- Deploy user has superuser privileges for migrations
- Database isolated to localhost connections only

### Application Security
- `SECRET_KEY_BASE` regenerated on each deployment
- Environment variables managed via systemd
- Application runs as non-root `deploy` user

## Required GitHub Secrets

- `DEPLOY_SSH_KEY`: Private SSH key for deploy user authentication

## Manual Operations

### Server Setup (One-time)
```bash
# Create deploy user
sudo useradd -m -s /bin/bash deploy
sudo usermod -aG sudo deploy
echo "deploy ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/deploy

# Create application directory
sudo mkdir -p /opt/rss-assistant
sudo chown deploy:deploy /opt/rss-assistant

# Setup PostgreSQL
sudo -u postgres createuser -s deploy
sudo -u postgres createdb rss_assistant

# Configure PostgreSQL trust auth
sudo sed -i "s/scram-sha-256/trust/" /etc/postgresql/*/main/pg_hba.conf
sudo systemctl reload postgresql

# Setup SSH key for deploy user
sudo mkdir -p /home/deploy/.ssh
# Copy public key to /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
```

### Service Management
```bash
# Check service status
sudo systemctl status rss-assistant

# View logs
sudo journalctl -u rss-assistant -f

# Manual restart
sudo systemctl restart rss-assistant
```

### Manual Deployment
```bash
# Run deployment script manually (as deploy user)
/home/deploy/deploy.sh <tarball-filename>

# The script handles all aspects of deployment including:
# - Backup creation
# - Zero-downtime deployment  
# - Migration execution
# - Service restart
# - Rollback on failure
```

### Database Operations
```bash
# Connect to database
psql -U deploy -d rss_assistant

# Manual migration
cd /opt/rss-assistant
export DATABASE_URL=postgresql://deploy@localhost/rss_assistant
export SECRET_KEY_BASE=$(openssl rand -base64 32)
./bin/rss_assistant eval "RssAssistant.Release.migrate"
```

## Troubleshooting

### Common Issues
1. **Service won't start**: Check systemd logs and environment variables
2. **Database connection failed**: Verify PostgreSQL trust configuration  
3. **Migration errors**: Ensure deploy user has database permissions
4. **Asset loading issues**: Check that assets were built correctly
5. **Deployment script fails**: Check `/tmp/` for deployment artifacts and verify permissions
6. **Service doesn't restart after deployment**: Check deployment script output and systemd status

### Log Locations
- **Application**: `sudo journalctl -u rss-assistant`
- **Caddy**: `sudo journalctl -u caddy`
- **PostgreSQL**: `/var/log/postgresql/`
- **Deployment**: Output is shown in GitHub Actions logs

### Deployment Rollback
If a deployment fails, the script automatically attempts to rollback to the previous version. Manual rollback can be performed by:
```bash
# Check if backup exists
ls -la /opt/rss-assistant-backup/

# Manually restore backup (if needed)
sudo systemctl stop rss-assistant
sudo rm -rf /opt/rss-assistant/*  
sudo cp -r /opt/rss-assistant-backup/* /opt/rss-assistant/
sudo chown -R deploy:deploy /opt/rss-assistant
sudo systemctl start rss-assistant
```