# Paloma Morse 🕊️

Кроссплатформенный тренажёр азбуки Морзе с аппаратной поддержкой телеграфных ключей.

Красивый glassmorphism-интерфейс, C++ движок генерации звука, WebSocket-мост, автообновление.

---

## Скачать

| Платформа | Ссылка | Формат |
|:---|:---|:---|
| 🍎 **macOS** (Apple Silicon) | [Скачать DMG](https://github.com/sk1bid/Paloma-Morze/releases/latest/download/Paloma-Morse-0.1.0-beta.25-arm64.dmg) | `.dmg` |
| 🪟 **Windows** | [Скачать Setup](https://github.com/sk1bid/Paloma-Morze/releases/latest/download/Paloma-Morse.Setup.0.1.0-beta.25.exe) | `.exe` |
| 🐧 **Linux** | [Скачать AppImage](https://github.com/sk1bid/Paloma-Morze/releases/latest/download/Paloma-Morse-0.1.0-beta.25.AppImage) | `.AppImage` |

> Все сборки всегда доступны на [странице релизов](https://github.com/sk1bid/Paloma-Morze/releases/latest).

---

## Установка и запуск

### 🍎 macOS
1. Скачайте `.dmg` файл
2. Откройте его и перетащите **Paloma Morse** в папку **Applications**
3. При первом запуске: ПКМ → «Открыть» (нужно из-за отсутствия подписи Apple)

### 🪟 Windows
1. Скачайте `.exe` установщик
2. Запустите — Windows может показать предупреждение SmartScreen, нажмите «Подробнее» → «Выполнить в любом случае»
3. Приложение установится и появится ярлык на рабочем столе

### 🐧 Linux
1. Скачайте `.AppImage` файл
2. Выдайте права на запуск:
   ```bash
   chmod +x Paloma-Morse-*.AppImage
   ```
3. Запустите:
   ```bash
   ./Paloma-Morse-*.AppImage
   ```

---

## Подключение телеграфного ключа

1. Подключите ключ по USB (Arduino / ESP32 с прошивкой PALOMA)
2. Индикатор в шапке приложения:
   - 🔴 **Красный** — ключ не подключён
   - 🟢 **Зелёный** — ключ готов
   - 🟢✨ **Яркий зелёный** — ключ зажат, передача
3. Переподключение происходит автоматически

---

## Обновление

Приложение **само проверяет обновления** при запуске. Если доступна новая версия — появится уведомление с кнопкой «Обновить».

Также можно проверить вручную: нажмите на версию в правом верхнем углу.

---

## Технические детали

- **UI**: React + Vite + Electron
- **Движок**: C++ (miniaudio) — генерация звука, работа с COM-портами
- **Мост**: WebSocket (Node.js) между UI и C++ движком
- **Сборка**: GitLab CI → автоматическое зеркалирование на GitHub
- **Поддержка**: Windows x64, macOS ARM64, Linux x64

---

*Создано с 🕊️ by Paloma Engine*
