# Развёртывание Inspecto

## Инфраструктура для разработки

`compose.dev.yaml` поднимает то, что нужно сервисам при запуске из IDE:

| Компонент | Адрес на машине разработчика | Назначение |
|---|---|---|
| PostgreSQL 16 | `127.0.0.1:5432` (только TLS) | Базы `inspecto_core`, `inspecto_media`, `inspecto_report`; на каждую — пользователи `<сервис>_migrator` (миграции) и `<сервис>_app` (работа сервиса) |
| SeaweedFS S3 | `http://127.0.0.1:8333` | Бакеты `photos` (media-service) и `reports` (report-service); у каждого сервиса свои ключи доступа только к своему бакету |
| Gotenberg | `http://127.0.0.1:3000` | HTML → PDF для report-service; Chromium не может обращаться к сети |

Порты публикуются только на `127.0.0.1`.

### Запуск

Нужен Docker Desktop (или Docker Engine с плагином compose).

```bash
cp deploy/.env.example deploy/.env    # затем замените пароли
docker compose -f deploy/compose.dev.yaml --env-file deploy/.env up -d --wait
```

Остановка: `docker compose -f deploy/compose.dev.yaml --env-file deploy/.env down` (добавьте `-v`, чтобы удалить данные).

### Подключение к базе

```bash
psql "host=127.0.0.1 port=5432 dbname=inspecto_core user=core_app sslmode=require"
```

Сертификат PostgreSQL самоподписанный (создаётся при первом запуске), поэтому в разработке используется `sslmode=require`; в эксплуатации — `verify-full` с доверенным сертификатом.

### Проверка

Workflow `.github/workflows/compose.yml` при каждом изменении `deploy/` поднимает инфраструктуру на GitHub-runner и проверяет: TLS-подключение, права ролей (приложение не выполняет DDL, сервис не подключается к чужой базе, соединения без TLS отклоняются), изоляцию бакетов S3 и генерацию PDF.
