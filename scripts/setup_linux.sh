#!/bin/bash

# Paloma Morse - Linux Setup Script
# Автоматическая настройка зависимостей и прав доступа для Ubuntu/Debian

set -e

echo "------------------------------------------------"
echo "🚀 Paloma Morse: Настройка окружения Linux"
echo "------------------------------------------------"

# 1. Проверка на root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Этот скрипт должен быть запущен через sudo!"
  echo "Попробуйте: sudo bash $0"
  exit 1
fi

REAL_USER=$SUDO_USER
if [ -z "$REAL_USER" ]; then
  REAL_USER=$(whoami)
fi

echo "📦 1/3 Обновление пакетов и установка зависимостей..."
apt-get update
apt-get install -y libasound2 libfuse2 alsa-utils

echo "🔑 2/3 Настройка групп доступа (dialout, audio)..."
usermod -aG dialout "$REAL_USER"
usermod -aG audio "$REAL_USER"

echo "🔊 3/3 Размьючивание звуковых каналов..."
amixer -c 0 sset 'Master' 100% unmute || true
amixer -c 0 sset 'Speaker' 100% unmute || true
amixer -c 0 sset 'Headphone' 100% unmute || true

echo "------------------------------------------------"
echo "✅ Настройка завершена успешно!"
echo "------------------------------------------------"
echo "📣 ВАЖНО: Чтобы права доступа вступили в силу,"
echo "нужно ПЕРЕЗАЙТИ в систему или выполнить команду:"
echo "newgrp dialout && newgrp audio"
echo ""
echo "Теперь вы можете запускать Paloma-Morse-*.AppImage"
echo "------------------------------------------------"
