# Paloma Morse 🕊️🛰️

Кроссплатформенный тренажер азбуки Морзе с аппаратной поддержкой ключей.

## Технологии
- **Engine**: C++ (Miniaudio) — низкая задержка, чистая частота 300-1200Гц.
- **Frontend**: React + Vite (Glassmorphism UI).
- **Desktop**: Electron — работает как нативное приложение.
- **CI/CD**: GitLab Pipelines (автосборка `.exe`, `.dmg`, `.AppImage`).

## Структура
- `ui/` — исходники интерфейса и моста (bridge.cjs).
- `morze_engine_v2.cpp` — основной аудио-движок.
- `apak/` — справочные материалы и словари.

## Запуск
```bash
cd ui
npm install
npm start
```

## Сборка (через GitLab CI)
Просто создайте тег версии для автоматического релиза:
```bash
git tag v0.1.0-beta
git push origin v0.1.0-beta
```

