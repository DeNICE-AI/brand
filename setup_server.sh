#!/bin/bash
# Скрипт настройки сервера для DeNICE-AI
# Запускать от имени root на сервере 78.17.16.170

set -e

echo "=== 1. Создание пользователя denice ==="
if id "denice" &>/dev/null; then
    echo "Пользователь denice уже существует"
else
    useradd -m -s /bin/bash denice
    usermod -aG sudo denice
    # Копируем SSH ключ от root к denice
    mkdir -p /home/denice/.ssh
    if [ -f /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys /home/denice/.ssh/
    fi
    chown -R denice:denice /home/denice/.ssh
    chmod 700 /home/denice/.ssh
    chmod 600 /home/denice/.ssh/authorized_keys || true
fi

echo "=== 2. Установка зависимостей ==="
apt update
apt install -y python3-pip python3-venv git ufw

echo "=== 3. Клонирование и настройка проекта ==="
if [ -d "/opt/brand" ]; then
    echo "Директория /opt/brand уже существует. Обновляю код..."
    cd /opt/brand
    git config --global --add safe.directory /opt/brand
    git pull
else
    git clone https://github.com/DeNICE-AI/brand.git /opt/brand
    cd /opt/brand
fi

chown -R denice:denice /opt/brand

echo "=== 4. Настройка виртуального окружения ==="
sudo -u denice bash -c 'cd /opt/brand && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt'

echo "=== 5. Создание системного сервиса systemd и .env ==="

# Создаем пустой .env для пользователя
if [ ! -f /opt/brand/.env ]; then
    echo "GIGACHAT_CLIENT_ID=ваш_id" > /opt/brand/.env
    echo "GIGACHAT_CLIENT_SECRET=ваш_секрет" >> /opt/brand/.env
    chown denice:denice /opt/brand/.env
fi

cat > /etc/systemd/system/denice-bot.service << 'EOF'
[Unit]
Description=DeNICE-AI Backend FastAPI
After=network.target

[Service]
User=denice
WorkingDirectory=/opt/brand
Environment="PATH=/opt/brand/venv/bin"
ExecStart=/opt/brand/venv/bin/uvicorn backend.app:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable denice-bot.service

echo "=== 6. Настройка Firewall ==="
ufw allow 8000/tcp || true

echo "================================================"
echo "Установка завершена! Проект находится в /opt/brand"
echo "Обязательно пропишите свои ключи GigaChat в файл /opt/brand/.env :"
echo "nano /opt/brand/.env"
echo "После этого перезапустите сервис: systemctl restart denice-bot"
echo "================================================"
