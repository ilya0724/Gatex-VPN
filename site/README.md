# Сайт GateX VPN

Одностраничный промо-сайт: `index.html`, без сборки и зависимостей (шрифты Google Fonts, всё остальное внутри файла).

Адрес: https://gatexx.ru (хостинг reg.ru). В корень сайта кладутся все файлы этой папки, кроме README.md: `index.html`, `.htaccess`, `robots.txt`, `sitemap.xml`, `og.png` (картинка для превью ссылки), `apple-touch-icon.png`, `favicon.ico`.

Редирект на HTTPS включается в панели хостинга (настройки сайта), не в `.htaccess`: за фронтовым nginx reg.ru Apache не видит HTTPS, и правило по `%{HTTPS}` зацикливается.

Цены в скрипте внизу страницы (`PRICES`) повторяют `plans.py` бота; при смене тарифов править оба места.
