# База данных Inspecto

> Статус: проект схемы v0.1 (этап проектирования). После реализации миграций документ синхронизируется с ними; источник истины — миграции в репозиториях сервисов.

## 1. Распределение данных

СУБД — PostgreSQL 16, один экземпляр, отдельная база на сервис (ADR-005). Общих таблиц и межбазовых внешних ключей нет: ссылки между сервисами — это UUID, целостность которых обеспечивается внутренними API.

| База | Владелец | Пользователь СУБД | Содержимое |
|---|---|---|---|
| `inspecto_core` | core-service | `core_app` | Пользователи, токены, объекты, помещения, справочники, осмотры, чек-листы, дефекты, наблюдения, история, ML-подсказки, задания очистки |
| `inspecto_media` | media-service | `media_app` | Метаданные фотографий |
| `inspecto_report` | report-service | `report_app` | Задания генерации отчётов и метаданные PDF |

Файлы (фото, PDF) — в SeaweedFS (ADR-006), в базах только ключи объектов.

Пользователи СУБД сервисов не являются владельцами схемы: миграции выполняются отдельным пользователем `*_migrator`, а приложение получает только `SELECT/INSERT/UPDATE/DELETE` (см. SECURITY.md).

## 2. Общие соглашения

- Первичные ключи — `uuid` (UUIDv7, генерируется приложением: монотонно возрастает, хорошо индексируется, не раскрывает количество записей).
- Время — `timestamptz` в UTC; дата осмотра — `timestamptz`.
- Перечисления — `text` с `CHECK`-ограничением (проще эволюция, чем `enum`-типы PostgreSQL).
- Оптимистическая блокировка — столбец `version bigint` на изменяемых сущностях.
- `created_at`, `updated_at` — на всех изменяемых таблицах.
- Имена таблиц — множественное число, `snake_case`.
- Каскадное удаление внутри базы — `ON DELETE CASCADE` только по агрегатам (объект → помещения → …), иначе `RESTRICT`.

## 3. База `inspecto_core`

### 3.1. Пользователи и аутентификация

#### users

| Столбец | Тип | Ограничения | Описание |
|---|---|---|---|
| id | uuid | PK | |
| email | text | UNIQUE (по `lower(email)`), NOT NULL | Логин |
| password_hash | text | NOT NULL | Argon2id |
| full_name | text | NOT NULL | |
| role | text | CHECK IN (`ADMIN`,`INSPECTOR`,`CLIENT`) | ADR-009 |
| locale | text | DEFAULT `ru` | ADR-019 |
| failed_login_attempts | int | DEFAULT 0 | Защита от перебора |
| locked_until | timestamptz | NULL | |
| created_at, updated_at | timestamptz | | |
| version | bigint | | |

#### refresh_tokens

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK → users ON DELETE CASCADE | |
| family_id | uuid | Семейство ротации; при повторном использовании отзывается всё семейство |
| token_hash | text UNIQUE | SHA-256 от токена; сам токен не хранится |
| expires_at | timestamptz | |
| revoked_at | timestamptz NULL | |
| created_at | timestamptz | |
| user_agent | text NULL | Для списка сессий |

**service_clients** — клиенты для сервисных токенов (media, report, ml): `id`, `client_id` UNIQUE, `secret_hash`, `scopes text[]`, `created_at`.

### 3.2. Объекты и помещения

#### properties

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| owner_id | uuid FK → users ON DELETE CASCADE | Владелец |
| name | text NOT NULL | Название («Квартира на Ленина») |
| type | text CHECK IN (`APARTMENT`,`HOUSE`,`COMMERCIAL`,`OTHER`) | |
| address | text NOT NULL | Адрес одной строкой |
| city | text NULL | |
| area_sqm | numeric(8,2) NULL | Площадь |
| notes | text NULL | |
| archived_at | timestamptz NULL | Архивирование (ADR-018) |
| created_at, updated_at, version | | |

Индексы: `(owner_id, archived_at)`.

**rooms**: `id`, `property_id` FK → properties ON DELETE CASCADE, `name`, `room_type` CHECK IN (`LIVING`,`KITCHEN`,`BATHROOM`,`TOILET`,`HALLWAY`,`BALCONY`,`OTHER`), `sort_order int`, `archived_at`, `created_at`, `updated_at`, `version`. Индекс `(property_id, sort_order)`.

**property_access** *(этап расширения, роль CLIENT)*: `property_id`, `user_id`, `access_level` CHECK IN (`VIEW`), `granted_by`, `created_at`; PK `(property_id, user_id)`.

### 3.3. Справочники

#### defect_categories

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| code | text NULL | Машинный код системной категории (`CRACK`, `PEELING`, …); используется ML |
| owner_id | uuid NULL FK → users ON DELETE CASCADE | `NULL` — системная категория |
| names | jsonb NOT NULL | Переводы: `{"ru": "Трещина", "en": "Crack"}` |
| element_group | text NULL | Подсказка, к какой группе элементов относится |
| is_active | boolean | Отключённая категория не предлагается, но сохраняется у существующих дефектов |
| created_at, updated_at | | |

Ограничения: `UNIQUE (code) WHERE owner_id IS NULL`; `CHECK (owner_id IS NOT NULL OR code IS NOT NULL)`.

**checklist_templates**: `id`, `code` UNIQUE, `names jsonb`, `is_system boolean`, `owner_id NULL`, `created_at`.

**checklist_template_items**: `id`, `template_id` FK, `element_group` CHECK IN (`WALLS`,`CEILING`,`FLOOR`,`WINDOWS`,`DOORS`,`PLUMBING`,`ELECTRICAL`,`OTHER`), `titles jsonb`, `sort_order`.

Шкала серьёзности фиксирована и хранится как перечисление в `defects.severity` (ADR-017): `COSMETIC`, `MINOR`, `MAJOR`, `CRITICAL`.

### 3.4. Осмотры и чек-листы

#### inspections

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| property_id | uuid FK → properties ON DELETE CASCADE | |
| inspector_id | uuid FK → users | Кто проводит |
| title | text NULL | |
| inspected_at | timestamptz NOT NULL | Дата осмотра |
| status | text CHECK IN (`DRAFT`,`IN_PROGRESS`,`COMPLETED`) | |
| notes | text NULL | |
| completed_at | timestamptz NULL | |
| created_at, updated_at, version | | |

Индекс `(property_id, inspected_at DESC)`.

#### inspection_checklist_items

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| inspection_id | uuid FK → inspections ON DELETE CASCADE | |
| room_id | uuid FK → rooms | |
| template_item_id | uuid NULL FK | `NULL` — пользовательский пункт |
| element_group | text | |
| title | text NOT NULL | Копия названия на момент осмотра (шаблон может измениться) |
| result | text CHECK IN (`NOT_CHECKED`,`OK`,`DEFECT`,`NOT_APPLICABLE`) DEFAULT `NOT_CHECKED` | |
| comment | text NULL | |
| sort_order | int | |
| updated_at, version | | |

### 3.5. Дефекты (ADR-003)

**defects** — дефект объекта, существует дольше одного осмотра.

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| property_id | uuid FK → properties ON DELETE CASCADE | |
| room_id | uuid FK → rooms | |
| category_id | uuid FK → defect_categories | |
| element_group | text | |
| title | text NOT NULL | Краткое описание |
| description | text NULL | |
| severity | text CHECK IN (`COSMETIC`,`MINOR`,`MAJOR`,`CRITICAL`) | |
| current_status | text CHECK IN (`OPEN`,`RESOLVED`) | Денормализация последнего наблюдения |
| first_inspection_id | uuid FK → inspections | Где обнаружен впервые |
| created_by | uuid FK → users | |
| created_at, updated_at, version | | |

Индексы: `(property_id, current_status)`, `(room_id)`.

**defect_observations** — состояние дефекта в конкретном осмотре.

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| defect_id | uuid FK → defects ON DELETE CASCADE | |
| inspection_id | uuid FK → inspections ON DELETE CASCADE | |
| checklist_item_id | uuid NULL FK | Пункт чек-листа, при проверке которого наблюдался |
| status | text CHECK IN (`OPEN`,`RESOLVED`) | `RESOLVED` — только явное подтверждение пользователя |
| severity | text | Серьёзность на момент наблюдения |
| comment | text NULL | |
| observed_by | uuid FK → users | |
| created_at, updated_at, version | | |

Ограничение `UNIQUE (defect_id, inspection_id)` — одно наблюдение дефекта в осмотре.

**observation_photos**: `id`, `observation_id` FK ON DELETE CASCADE, `photo_id uuid` (ссылка на `inspecto_media.photos`, без FK), `caption`, `sort_order`, `created_at`. `UNIQUE (photo_id)` — фото принадлежит одному наблюдению.

**defect_status_history**: `id`, `defect_id` FK ON DELETE CASCADE, `from_status NULL`, `to_status`, `inspection_id NULL`, `changed_by`, `changed_at`, `comment`. Append-only.

**defect_idempotency_keys** (core V8, T-308): `id`, `user_id` FK ON DELETE CASCADE, `key text` (8–64 символа), `defect_id` FK ON DELETE CASCADE, `created_at`. `UNIQUE (user_id, key)` — `Idempotency-Key` из `POST /inspections/{id}/defects`: повтор с тем же ключом возвращает созданный дефект. Одновременные повторы упорядочиваются блокировкой `pg_advisory_xact_lock` по ключу.

### 3.6. ML и служебные таблицы

#### ml_suggestions

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| photo_id | uuid | |
| requested_by | uuid FK → users ON DELETE CASCADE | |
| model_version | text | |
| predictions | jsonb | `[{"code":"CRACK","probability":0.81}, …]` |
| defect_id | uuid NULL FK ON DELETE SET NULL | Дефект, для которого применена подсказка |
| chosen_category_id | uuid NULL | Что выбрал пользователь |
| decision | text NULL CHECK IN (`ACCEPTED_TOP1`,`ACCEPTED_OTHER`,`REJECTED`) | Метрика полезности подсказок |
| created_at, decided_at | | |

**outbox_events** — задания очистки файлов при удалении (ADR-018): `id`, `type` (`DELETE_PROPERTY_FILES`, `DELETE_USER_FILES`, `DELETE_PHOTO` — отвязанное фото или фото удалённого черновика), `payload jsonb`, `status` (`PENDING`,`DONE`,`FAILED`), `attempts`, `next_attempt_at`, `last_error`, `created_at`. Обработчик core забирает задания `FOR UPDATE SKIP LOCKED` и повторяет неудачные с удваивающейся задержкой (10 с … 1 ч) до успеха; `FAILED` не используется.

## 4. База `inspecto_media`

### photos

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| owner_id | uuid | Пользователь, загрузивший фото |
| property_id | uuid | Для проверки прав и массового удаления |
| status | text CHECK IN (`UPLOADED`,`ATTACHED`) | Неприкреплённые удаляются через 24 ч |
| original_key | text | Ключ сжатого оригинала в бакете `photos` |
| preview_key | text | ≈1280 px — для просмотра и PDF |
| thumb_key | text | ≈320 px |
| content_type | text | Формат хранения — всегда `image/jpeg` (ADR-025); загружать можно JPEG, PNG и WebP |
| size_bytes | bigint | Размер сохранённого оригинала |
| width, height | int | Размеры оригинала после поворота по EXIF |
| sha256 | text | SHA-256 сохранённого оригинала, контроль целостности |
| idempotency_key | text NULL | Ключ `Idempotency-Key`: повтор загрузки возвращает то же фото |
| created_at, attached_at | timestamptz | |

Индексы: `(property_id)`, `(owner_id)`, `(status, created_at)`; `UNIQUE (owner_id, idempotency_key)`.

## 5. База `inspecto_report`

### report_jobs

| Столбец | Тип | Описание |
|---|---|---|
| id | uuid PK | |
| inspection_id | uuid | |
| property_id | uuid | Для массового удаления |
| requested_by | uuid | |
| locale | text | |
| status | text CHECK IN (`QUEUED`,`RUNNING`,`DONE`,`FAILED`) | |
| attempts | int | |
| next_attempt_at | timestamptz | |
| object_key | text NULL | Ключ PDF в бакете `reports` |
| size_bytes | bigint NULL | |
| page_count | int NULL | |
| error_code | text NULL | |
| created_at, started_at, finished_at | timestamptz | |

Индексы: `(status, next_attempt_at)`, `(inspection_id, created_at DESC)`.

## 6. ER-диаграмма

Исходники диаграмм — [`architecture/diagrams/er-core.mmd`](architecture/diagrams/er-core.mmd) и [`architecture/diagrams/er-services.mmd`](architecture/diagrams/er-services.mmd); отрисованные версии входят в архитектурный PDF.

## 7. Обоснование структуры

1. **Дефект отделён от осмотра** (ADR-003): позволяет сравнивать осмотры по `defect_id` и строить историю без цепочек копий.
2. **Название пункта чек-листа копируется в осмотр**: изменение шаблона не меняет проведённые осмотры (юридическая значимость отчёта).
3. **`current_status` денормализован**: списки открытых дефектов объекта — частый запрос; поле обновляется в той же транзакции, что и наблюдение.
4. **Переводы в `jsonb`** вместо отдельных таблиц: справочников мало, языков два; запросы проще (ADR-019).
5. **Ссылки на фото без FK**: фото принадлежат другой базе; целостность — через внутренний `attach` и задания очистки.
6. **Отдельные базы сервисов**: компрометация одного сервиса не даёт доступа к данным других.
