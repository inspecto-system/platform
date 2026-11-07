# Резервное копирование (T-507)

Одна копия — один зашифрованный файл `inspecto-ГГГГММДД-ЧЧММСС.tar.age`: три базы PostgreSQL
(`pg_dump`, custom format) и бакеты `photos` и `reports` SeaweedFS. Шифрование — [age](https://age-encryption.org)
(открытый формат, ключ X25519): копию делает открытый ключ, восстанавливает только закрытый.
Копии старше 14 дней удаляются при следующем запуске (`BACKUP_RETENTION_DAYS`): так удалённые
пользователями данные исчезают и из копий (SECURITY.md §9).

Инструменты запускаются в контейнерах (`alpine` с `age`, `amazon/aws-cli` для S3 с ключом
`S3_ADMIN_*` из `deploy/.env`), на машине нужен только Docker. Команды — из каталога `platform`,
при запущенном compose (в Git Bash работают как есть).

```bash
sh deploy/backup/keygen.sh     # один раз: ключ deploy/backup.key (сохраните копию отдельно от копий!)
sh deploy/backup/backup.sh     # копия в deploy/backups/
sh deploy/backup/restore.sh deploy/backups/inspecto-20261107-134315.tar.age
```

`restore.sh` останавливает core, media, report и nginx, заменяет базы (`pg_restore --clean`) и
приводит бакеты к содержимому копии (объекты, появившиеся после неё, удаляются), затем запускает
сервисы. Пути меняются переменными `BACKUP_DIR` и `BACKUP_KEY_FILE`.

`verify.sh` — проверка восстановления на чистый compose: создаёт аккаунт с объектом, дефектом, фото
и PDF-отчётом, делает копию, **удаляет весь compose вместе с томами**, поднимает чистый, восстанавливает
и сравнивает данные и байты файлов. Поэтому запускается только с `VERIFY_DESTROYS_DATA=yes`; в CI —
`.github/workflows/backup.yml` (раз в неделю, вручную и при изменении `deploy/`).

`deploy/backups/` и `deploy/backup.key` не попадают в git.
