# Развёртывание Inspecto

## Инфраструктура для разработки

`compose.dev.yaml` поднимает то, что нужно сервисам при запуске из IDE:

| Компонент | Адрес на машине разработчика | Назначение |
|---|---|---|
| PostgreSQL 16 | `127.0.0.1:5432` (только TLS; порт меняется переменной `POSTGRES_PORT`) | Базы `inspecto_core`, `inspecto_media`, `inspecto_report`; на каждую — пользователи `<сервис>_migrator` (миграции) и `<сервис>_app` (работа сервиса) |
| SeaweedFS S3 | `http://127.0.0.1:8333` | Бакеты `photos` (media-service) и `reports` (report-service); у каждого сервиса свои ключи доступа только к своему бакету |
| Gotenberg | `http://127.0.0.1:3000` | HTML → PDF для report-service; Chromium не может обращаться к сети |

Порты публикуются только на `127.0.0.1`.

С профилем `apps` (`--profile apps`) добавляются core (`8081`), media (`8082`), report (`8083`) и
единая точка входа **nginx** (ADR-013): `https://localhost:8443/api/v1/…` (HTTP `8080` перенаправляет на
HTTPS; порты — `NGINX_HTTPS_PORT`, `NGINX_HTTP_PORT`). Сертификат самоподписанный (задание `certs`,
имена `localhost`, `127.0.0.1`, `10.0.2.2`). nginx маршрутизирует `/api/v1/photos` → media,
`/api/v1/reports` → report, остальное `/api/v1` → core; `/internal/**` и актуаторы не публикуются;
заголовки безопасности, лимит частоты входа 5 в минуту с IP, тело до 1 МБ (фото — до 16 МБ). Прямые
порты сервисов остаются для запуска из IDE и debug-сборки Android.

### Запуск

Нужен Docker Desktop (или Docker Engine с плагином compose).

```bash
cp deploy/.env.example deploy/.env    # затем замените пароли
docker compose -f deploy/compose.dev.yaml --env-file deploy/.env up -d --wait
```

Остановка: `docker compose -f deploy/compose.dev.yaml --env-file deploy/.env down` (добавьте `-v`, чтобы удалить данные).

### Подключение к базе

```bash
psql "host=127.0.0.1 port=${POSTGRES_PORT:-5432} dbname=inspecto_core user=core_app sslmode=require"
```

Сертификат PostgreSQL самоподписанный (создаётся при первом запуске), поэтому в разработке используется `sslmode=require`; в эксплуатации — `verify-full` с доверенным сертификатом.

### Проверка

Workflow `.github/workflows/compose.yml` при каждом изменении `deploy/` поднимает инфраструктуру на GitHub-runner и проверяет: TLS-подключение, права ролей (приложение не выполняет DDL, сервис не подключается к чужой базе, соединения без TLS отклоняются), изоляцию бакетов S3 и генерацию PDF.
