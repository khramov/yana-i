# Deploying Next.js + SQLite to Hetzner

This guide covers deploying your Next.js application (with SQLite database) on Hetzner Cloud.

## Table of Contents

1. [Infrastructure Setup](#infrastructure-setup)
2. [Server Configuration](#server-configuration)
3. [Application Deployment](#application-deployment)
4. [Reverse Proxy (Nginx)](#reverse-proxy-nginx)
5. [SSL/TLS Certificates](#ssltls-certificates)
6. [Monitoring & Maintenance](#monitoring--maintenance)
7. [Troubleshooting](#troubleshooting)

---

## Infrastructure Setup

### Choose a Server

**Recommended for small-to-medium Next.js apps:**
- **Hetzner Cloud VPS**: CX23 (2 vCPU, 4GB RAM) or larger
- **Location**: Choose closest to your users (EU, US, Asia)
- **OS**: Ubuntu 26.04 LTS
- **Storage**: Standard disk is fine for SQLite

### Create the Server

1. Log in to [Hetzner Cloud Console](https://console.hetzner.cloud)
2. Click **Create** → **Cloud Server**
3. Select:
   - Image: **Ubuntu 26.04**
   - Type: **CX23** (2 vCPU, 4GB RAM)
   - Location: Your preferred region
   - SSH Key: Add your public key (don't use password)
4. Click **Create**
5. Note the server's IP address

### Initial SSH Access

```bash
ssh root@<your_server_ip>
```

---

## Server Configuration

### 1. Update System

```bash
apt update && apt upgrade -y
apt install -y curl wget git build-essential
```

### 2. Create Application User (optional but recommended)

```bash
useradd -m -s /bin/bash poke
usermod -aG sudo poke
```

Switch to the app user:
```bash
sudo -u poke -i
```

### 3. Install Node.js 20

```bash
sudo snap install node --classic
node --version
npm --version
```

### 4. Install Nginx

```bash
sudo apt install -y nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

---

## Application Deployment

### 1. Clone Repository

```bash
cd /home/poke

ssh-keygen -t ed25519 -C "deployment-key" -f ./github_deploy_key -N ""
eval "$(ssh-agent -s)"
ssh-add github_deploy_key

git clone <your-repo-url> poke
cd poke
```

### 2. Install Dependencies

```bash
npm ci  # Install locked dependencies
```

### 3. Build for Production

```bash
npm run build
```

This creates `.next/` directory with the optimized build.

Since `next.config.ts` sets `output: "standalone"`, the standalone server does **not** include static assets — copy them in manually after every build:

```bash
cp -r .next/static .next/standalone/.next/static
cp -r public .next/standalone/public
```

Without this step, the app runs but all CSS/JS chunks 404 and pages render unstyled.

### 4. Create Systemd Service

Create `/etc/systemd/system/nextjs.service`:

```ini
[Unit]
Description=Next.js Application
After=network.target

[Service]
Type=simple
User=poke
WorkingDirectory=/home/poke/poke
Environment="NODE_ENV=production"
Environment="PORT=3000"
ExecStart=/snap/bin/node /home/poke/poke/.next/standalone/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable nextjs
sudo systemctl start nextjs
sudo systemctl status nextjs  # Verify it's running
```

View logs:
```bash
sudo journalctl -u nextjs -f
```

### 5. Database Permissions

The SQLite database file (`data/yana.db`) needs to be readable/writable by the `poke`:

```bash
sudo chown -R poke:poke /home/poke/poke/data
sudo chmod 755 /home/poke/poke/data
sudo chmod 644 /home/poke/poke/data/*.db*
```

---

## Reverse Proxy (Nginx)

Configure Nginx to proxy requests to Next.js and handle SSL.

Create `/etc/nginx/sites-available/poke`:

```nginx
upstream nextjs {
    server 127.0.0.1:3000;
}

server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    # Redirect HTTP to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name yourdomain.com www.yourdomain.com;

    # SSL certificates (see next section)
    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;

    client_max_body_size 10M;

    # All routes → Next.js
    location / {
        proxy_pass http://nextjs;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
    }
}
```

Enable the site:

```bash
sudo ln -s /etc/nginx/sites-available/poke /etc/nginx/sites-enabled/
sudo nginx -t  # Test configuration
sudo systemctl reload nginx
```

---

## SSL/TLS Certificates

Use **Let's Encrypt** (free, automatic renewal).

### Install Certbot

```bash
sudo apt install -y certbot python3-certbot-nginx
```

### Generate Certificate

```bash
sudo certbot certonly --nginx -d yourdomain.com -d www.yourdomain.com
```

Follow the prompts. Certificates are saved to `/etc/letsencrypt/live/yourdomain.com/`.

### Auto-Renewal

Certbot renewal runs automatically via cron. Verify:

```bash
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

Test renewal (dry-run):

```bash
sudo certbot renew --dry-run
```

---

## Monitoring & Maintenance

### 1. Check Service Status

```bash
sudo systemctl status nextjs
sudo systemctl status nginx
```

### 2. View Logs

**Next.js:**
```bash
sudo journalctl -u nextjs -f
```

**Nginx:**
```bash
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### 3. Monitor Resources

```bash
htop  # CPU, memory, processes
df -h  # Disk usage
free -m  # RAM usage
```

### 4. Set Up Firewall

```bash
sudo ufw enable
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw status
```

### 5. Automated Backups

Back up the SQLite database regularly:

```bash
# Add to crontab -e (as poke or root)
0 2 * * * cp /home/poke/poke/data/yana.db /home/poke/backups/yana_$(date +\%Y\%m\%d).db
```

Create the backups directory first:
```bash
sudo mkdir -p /home/poke/backups
sudo chown poke:poke /home/poke/backups
```

---

## Deployment Workflow

### For Code Updates:

```bash
# SSH to server
ssh root@<your_server_ip>

# Pull latest code
cd /home/poke/poke
git pull origin main

# Rebuild
npm ci
npm run build
cp -r .next/static .next/standalone/.next/static
cp -r public .next/standalone/public

# Restart service
sudo systemctl restart nextjs

# Verify
curl https://yourdomain.com/
```

### Automated Deployment (Optional)

Use a CI/CD tool (GitHub Actions, GitLab CI) to automate the above steps, or set up a webhook to trigger a deploy script.

---

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 3000
sudo lsof -i :3000
sudo kill -9 <PID>
```

### Nginx 502 Bad Gateway

- Check if Next.js is running: `sudo systemctl status nextjs`
- Check logs: `sudo journalctl -u nextjs -n 50`
- Verify `upstream nextjs` in nginx config points to `127.0.0.1:3000`

### SQLite Database Locked

- Ensure only one process accesses the database (Next.js server)
- Check file permissions: `ls -la /home/poke/poke/data/yana.db*`
- Restart Next.js: `sudo systemctl restart nextjs`

### Out of Memory

- Monitor with `free -h` and `htop`
- Consider upgrading server size (CX23 → CX31)
- Check Next.js memory usage in logs

### SSL Certificate Issues

```bash
sudo certbot renew --force-renewal
sudo systemctl reload nginx
```

---

## Production Checklist

- [ ] Database file (`data/yana.db`) has correct permissions (poke can read/write)
- [ ] NODE_ENV is set to `production` in systemd service
- [ ] Firewall enabled (ufw) with ports 22, 80, 443 open
- [ ] SSL certificate active and auto-renewal configured
- [ ] Backups of SQLite database configured
- [ ] Service starts on reboot (`systemctl enable nextjs`)
- [ ] Domain DNS A record points to server IP
- [ ] Nginx config tested (`nginx -t`)
- [ ] Error logging set up (optional: Sentry, LogRocket)

---

## Additional Resources

- [Hetzner Cloud Docs](https://docs.hetzner.cloud)
- [Next.js Production Deployment](https://nextjs.org/docs/app/building-your-application/deploying)
- [Nginx Reverse Proxy](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)
- [Let's Encrypt](https://letsencrypt.org)
- [SQLite Backup](https://www.sqlite.org/backup.html)
