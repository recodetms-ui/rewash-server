#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  install.sh — تثبيت خادم RE-WASH بأمر واحد
#  يشغّله: bash install.sh   (من داخل مجلد rewash-server على الـ VPS)
#  يفترض: Node.js + PostgreSQL مثبّتان، وقاعدة rewash_db والمستخدم rewash جاهزان.
# ═══════════════════════════════════════════════════════════════════
set -e
cd "$(dirname "$0")"
GREEN='\033[0;32m'; YEL='\033[1;33m'; NC='\033[0m'
say(){ echo -e "${GREEN}==>${NC} $1"; }

DOMAIN="recode-systems.com"
DB_PASS="ReWash2026DB"          # نفس كلمة سر مستخدم قاعدة البيانات

say "1/7 تثبيت مكتبات الخادم (npm install)..."
npm install --omit=dev

say "2/7 توليد الأسرار وإنشاء ملف .env..."
JWT=$(node -e "console.log(require('crypto').randomBytes(48).toString('hex'))")
ADMIN=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
cat > .env <<EOF
PORT=3000
NODE_ENV=production
DATABASE_URL=postgresql://rewash:${DB_PASS}@localhost:5432/rewash_db
JWT_SECRET=${JWT}
JWT_EXPIRES_IN=7d
LICENSE_PUBLIC_KEY=AuKMXUJ0JiBd7vuarsDqwDEUUNwOj+vA/VPu8DDryYI=
ALLOWED_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}
ADMIN_API_KEY=${ADMIN}
EOF
echo "    ✓ .env أُنشئ"

say "3/7 إنشاء جداول قاعدة البيانات..."
npm run migrate

say "4/7 تثبيت pm2 وتشغيل الخادم دائماً..."
npm install -g pm2 >/dev/null 2>&1 || npm install -g pm2
pm2 delete rewash-server >/dev/null 2>&1 || true
pm2 start src/index.js --name rewash-server
pm2 save
pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || pm2 startup

say "5/7 تثبيت Nginx..."
apt-get install -y nginx >/dev/null 2>&1
cat > /etc/nginx/sites-available/rewash <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    client_max_body_size 12M;
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
ln -sf /etc/nginx/sites-available/rewash /etc/nginx/sites-enabled/rewash
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

say "6/7 فتح المنافذ في جدار الحماية..."
ufw allow 22/tcp  >/dev/null 2>&1 || true
ufw allow 80/tcp  >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

say "7/7 الحصول على شهادة SSL (HTTPS)..."
apt-get install -y certbot python3-certbot-nginx >/dev/null 2>&1
echo -e "${YEL}سيُطلب منك بريد إلكتروني والموافقة على الشروط...${NC}"
certbot --nginx -d ${DOMAIN} -d www.${DOMAIN} --non-interactive --agree-tos --register-unsafely-without-email --redirect || \
  echo -e "${YEL}تعذّر SSL تلقائياً. شغّل لاحقاً: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}${NC}"

echo ""
say "✅ اكتمل التثبيت!"
echo "──────────────────────────────────────────"
echo "  الخادم يعمل على: https://${DOMAIN}"
echo "  لوحة المالك:     https://${DOMAIN}/"
echo "  لوحة الإدارة:    https://${DOMAIN}/admin"
echo ""
echo -e "  ${YEL}مفتاح الإدارة (احفظه — تدخل به لوحة الإدارة):${NC}"
echo "  ${ADMIN}"
echo "──────────────────────────────────────────"
echo "  فحص: curl https://${DOMAIN}/api/health"
