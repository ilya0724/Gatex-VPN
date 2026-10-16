# Личный кабинет GateX (Telegram Mini App)

Кабинет открывается из бота @gatexvpn_bot. Пользователь видит статус подписки,
ссылку для Happ и пошаговую настройку. При первом входе кабинет сам ведёт по шагам:
установить Happ → добавить подписку одной кнопкой → включить VPN.

Демо на примерных данных: `python3 cabinet/scripts/build_preview.py preview.html`
и открыть файл в браузере (переключатель «Демо-данные» вверху справа).

## Что внутри

| Путь | Что это |
|---|---|
| `web/` | Сам кабинет: `index.html`, `app.css`, `app.js`, без сборки и фреймворков |
| `web/open.html` | Передаёт ссылку `happ://add/…` системе (Telegram сам открывает только http/https) |
| `web/vendor/qrcode.js` | Генератор QR-кодов (qrcode-generator 1.4.4, MIT) |
| `server/app.py` | Бэкенд на aiohttp: раздаёт `web/` и отвечает на `POST /api/me` |
| `deploy/` | systemd-юнит и кусок конфига nginx |

### Экраны
- **Главная**: статус (активна / скоро закончится / закончилась / нет подписки), дата окончания, трафик, устройства «2 из 3», последнее подключение, кнопки «Продлить» и «Установка и настройка».
- **Настройка**: мастер из трёх шагов под устройство (iPhone, Android, Windows, macOS, Linux, ТВ). Для другого устройства показывает QR-код и кнопку «Себе в Telegram».
- **Профиль**: имя и ID, **мои устройства** (модель, система, приложение, последняя активность, кнопка «Отвязать» с подтверждением), основная и резервная ссылки подписки, продление, рефералка, канал, повтор обучения.
- **Помощь**: частые вопросы (включая белые списки и сервер «🇵🇱 Обход БС») и связь с поддержкой.

Тема следует теме Telegram (тёмная или светлая). Флаг «обучение пройдено» хранится
в Telegram CloudStorage и localStorage, поэтому на втором устройстве приветствие не повторяется.

## Откуда данные

Оба запроса несут `initData` от Telegram, подпись проверяется токеном бота (HMAC, срок 24 часа).

`POST /api/me`:
1. Ищем пользователя в Remnawave: `GET /api/users/by-telegram-id/{id}`. Если записей несколько, берём активную с самой поздней датой.
2. Устройства: `GET /api/hwid/devices/{userUuid}`.
3. Отдаём статус, дату, трафик, лимит устройств, ссылки подписки и список устройств. Ответ кешируется на 30 секунд.

`POST /api/devices/delete` с `id` устройства: сервер заново читает устройства пользователя, находит своё
и вызывает `POST /api/hwid/devices/delete`. Чужое устройство так не отвязать: id сверяется только со своим списком.

UUID пользователя и сырые HWID на страницу не попадают, вместо HWID отдаётся хеш.
Отвязка устройства — единственная запись в панель. Оплата и рефералка пока ведут в бота (`BUY_URL`, `REFERRAL_URL`).

## Запуск

```bash
python3 -m venv /opt/gatex-cabinet/venv
/opt/gatex-cabinet/venv/bin/pip install -r cabinet/server/requirements.txt
cp cabinet/server/.env.example cabinet/server/.env   # заполнить BOT_TOKEN, RW_API_TOKEN
cd cabinet/server && set -a && . ./.env && set +a && /opt/gatex-cabinet/venv/bin/python app.py   # 127.0.0.1:8095
```

Предлагаемая схема на проде (ещё не развёрнуто):
1. Код в `/opt/gatex-cabinet` на FR (там же панель, API на `127.0.0.1:3001`).
2. `deploy/gatex-cabinet.service` → `/etc/systemd/system/`, `systemctl enable --now gatex-cabinet`.
3. `deploy/nginx-cabinet.conf` в server-блок `app.fast-cloude-cdn.online`, `nginx -t && systemctl reload nginx`.
4. В @BotFather: Menu Button → `https://app.fast-cloude-cdn.online:8443/cabinet/` (или кнопка с `web_app` в боте).

## Тесты

```bash
cd cabinet/server
pip install -r requirements-dev.txt
pytest -q
```
