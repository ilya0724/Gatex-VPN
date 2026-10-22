# GateX bot: download the GateX app + task «+30 дней за установку»

Asked by Ilya on 2026-10-22: Happ stays the main app, our GateX app (Windows, Linux, Android)
is an optional fallback in the bot, and a new task gives +30 days for installing it on a PC or
an Android phone.

Bot: NL `/root/vpn_bot` (aiogram 3.30.0, Python 3.12), service `vpn_bot`. Texts live in `i18n.py`.
The menu redesign from 2026-10-21 (banners, `show_screen` helper, «Задания» with the nick task)
is already live, see `bot-menu/SPEC.md` on branch `claude/project-thread-pg7pa9`. Build on it,
don't re-do it.

## 0. Backup first

- `/root/gatex-app-backup-20261022/orig/`: every file you touch plus `.env`.
- After the change: `diff -u orig/X X > /root/gatex-app-backup-20261022/diff-X.patch` per file.
- `rollback.sh`: reverse the patches with `patch -R` (not a plain copy of orig, other threads may
  have changed the same files later), remove new files, restore `.env` keys, `systemctl restart vpn_bot`.
  Print clearly if a hunk is rejected.

## 1. How the bot knows the app is installed (no app change needed)

The app fetches the subscription with these headers, and Remnawave stores the device in its
HWID list (the cabinet already reads it via `GET {RW}/hwid/devices/{uuid or id}`):

- `User-Agent: Happ/3.10.0 GateX/1.3.0 (Android)` (also `(Windows)`, `(Linux)`; on a retry plain `GateX/1.3.0 (Android)`)
- `x-hwid`, `x-device-os: Android|Windows|Linux`, `x-device-model`

So a device counts as «GateX installed» when its `userAgent` contains `gatex/` (case-insensitive)
and its `platform` (or the OS in the UA brackets) is Android, Windows or Linux.
Reuse the bot's existing Remnawave client (`remna_client.py`); add one `hwid_devices(user)` call if
there is none. First check on the live panel that HWID devices really come back with `userAgent`
(look at any Happ user). If they don't, stop and report instead of guessing.

## 2. «📲 Приложение GateX» screen

Where: if «🔗 Подключиться» opens a bot screen, add the button there below the Happ options.
If «Подключиться» is a direct WebApp/URL button, keep it as is and put
`📲 Приложение GateX` in the main menu row with `🌐 Наш сайт`. Happ stays first everywhere.

Banner `connect`. Caption (HTML, keep under 1024 chars):

```
<b>Приложение GateX</b> · запасной вариант
Основное приложение у нас Happ. Если Happ не подключается или хочется своё, поставьте GateX: Windows, Android или Linux. Для iPhone и Mac пока только Happ.

<blockquote>1. Скачайте и установите приложение.
2. Скопируйте ссылку подписки ниже и вставьте её в GateX.
3. Нажмите «Подключить».</blockquote>
🔑 Ваша ссылка: <code>{sub_url}</code>

⭐ За установку +30 дней, см. «Задания».
```

- `{sub_url}`: the same subscription URL the bot/cabinet gives to Happ (subscription proxy if
  there is one). No panel user: replace the link line with
  «Сначала получите пробный период: подпишитесь на канал в начале бота».
- Buttons: `🪟 Windows` · `🤖 Android` (one row), `🐧 Linux (.deb)`, `⭐ Задание +30 дней`
  (opens «Задания»), `◀️ Назад`. Download buttons are URL buttons from `.env`.
- Store `app_screen_opened_at` on the user when the screen opens (used by the sweep in 4).

## 3. Task in «Задания»

Add a second block under the nick task:

```
<blockquote><b>📲 Приложение GateX · +30 дней</b>
Установите GateX на компьютер или Android, добавьте в него свою ссылку подписки и нажмите «Проверить приложение». Один раз на аккаунт.</blockquote>
Статус: {⏳ не выполнено | ✅ выполнено, +30 дней начислено}
```

Buttons: `✅ Проверить приложение` (callback), `📲 Скачать GateX` (opens the screen in 2).
Hide the block and buttons once granted? No: keep it with ✅ status, drop the check button.

### Rules

- Needs an existing panel user (trial or paid). Otherwise the same answer as the nick task.
- Not for people excluded by the ban-vpn list (same check referral.py uses).
- Match a device as in section 1.
- Once per Telegram account: atomic Mongo flip `app_bonus_granted_at` null → now.
- Once per device: collection `app_bonus_devices` with a unique index on
  `sha256("gatex-app:" + hwid)`; store user id, platform, time. If the insert hits a duplicate,
  undo the user flip and answer «Это устройство уже получило бонус на другом аккаунте.»
  If the user has several GateX devices, try them in order until one is new.
- Grant +`APP_BONUS_DAYS` (default 30) with the existing helper the nick/referral bonus uses
  (panel expireAt + Mongo). If the subscription has expired, count from now, never from the past.
- If granting days fails after the flips, undo both flips and tell the user to try later.
- No revoke when the app is removed later (the panel can't tell reliably).
- «Проверить приложение» rate limit: once per 30 s per user.
- Success: «🎉 GateX найден ({Android|Windows|Linux}) — +30 дней. Подписка до {date}.»
  Not found: «Пока не вижу GateX среди ваших устройств. Откройте приложение, вставьте ссылку подписки и через минуту нажмите «Проверить» ещё раз.»
- Admin notification on each grant: one line with user id, platform, new date.

## 4. Sweep (so the bonus also comes without pressing the button)

Every 20 min: users with `app_screen_opened_at` in the last 3 days and no `app_bonus_granted_at`.
Run the same check; on success grant and send the success message with the `tasks` banner and a
`🏠 Меню` button. Skip on any panel error (never grant on a guess).

## 5. Config (.env)

```
GATEX_APP_ENABLED=admin      # 0 = hidden, admin = only ADMIN_ID sees screen and task, 1 = everyone
APP_BONUS_DAYS=30
GATEX_APP_URL_WINDOWS=https://github.com/ilya0724/Gatex-VPN/releases/latest/download/GateX-Setup.exe
GATEX_APP_URL_ANDROID=https://github.com/ilya0724/Gatex-VPN/releases/latest/download/GateX.apk
GATEX_APP_URL_LINUX=https://github.com/ilya0724/Gatex-VPN/releases/latest/download/gatex_amd64.deb
```

Read them at use time (no restart needed to flip `GATEX_APP_ENABLED`), like `REMINDERS_ENABLED`.
The release with these file names doesn't exist yet; it comes from the app thread. Deploy with
`GATEX_APP_ENABLED=admin`.

## 6. Test, then restart

- `py_compile` on every changed file.
- Unit test grant logic with a fake user and a mocked panel: no device, Happ-only device, GateX
  Android device, same hwid on a second user, already granted, ban-vpn, panel error. Don't touch
  real users' days.
- `systemctl restart vpn_bot`, `journalctl -u vpn_bot -n 100` clean.
- Send the new screen and the updated «Задания» to ADMIN_ID only.

## 7. Report

Write `C:\Users\ilyab\.ssh\APP_BOT_REPORT.md`: changed files, new fields/collection, env vars,
backup path, rollback command, test results, where the button ended up, anything uncertain.
