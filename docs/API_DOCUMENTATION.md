# Документация API Inspecto

> Статус: каталог API v0.1 (этап проектирования). Формальные спецификации OpenAPI 3.1 — [`api/*.yaml`](../api/) (версия контрактов 0.1.0). При расхождении источником истины является OpenAPI-спецификация, а этот документ обновляется в том же PR.

## 1. Общие правила

| Правило | Значение |
|---|---|
| Базовый URL | `https://<host>/api/v1` — единая точка входа через nginx (ADR-013) |
| Формат | JSON, UTF-8; загрузка фото — `multipart/form-data`; PDF — `application/pdf` |
| Аутентификация | `Authorization: Bearer <access JWT>` (ADR-007); исключения: регистрация, вход, обновление токена |
| Идентификаторы | UUID |
| Время | ISO 8601 в UTC (`2026-11-04T16:02:00Z`) |
| Пагинация | `?page=0&size=20` (максимум 100); ответ `{ "items": [...], "page": 0, "size": 20, "total": 57 }` |
| Оптимистическая блокировка | Поле `version` в теле `PATCH`; при несовпадении — `409 VERSION_CONFLICT` |
| Трассировка | Заголовок `X-Request-Id` (принимается или генерируется, возвращается в ответе и в ошибках) |
| Идемпотентность | `POST /photos` и `POST /reports` принимают `Idempotency-Key` (повтор с тем же ключом возвращает исходный результат) |
| Локализация | Ответы содержат коды; тексты для пользователя формирует клиент (ADR-019). Названия справочников — по `Accept-Language` |

### Формат ошибок (RFC 9457)

```json
{
  "type": "https://inspecto.dev/problems/validation-error",
  "title": "Validation failed",
  "status": 400,
  "code": "VALIDATION_ERROR",
  "detail": "Request contains invalid fields",
  "requestId": "0b6f…",
  "errors": [{ "field": "address", "code": "NOT_BLANK" }]
}
```

| HTTP | Код | Когда |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Нарушены правила полей |
| 400 | `UNSUPPORTED_MEDIA_TYPE`, `IMAGE_DIMENSIONS_TOO_LARGE`, `PHOTO_LIMIT_EXCEEDED` | Ошибки загрузки фото |
| 413 | `IMAGE_TOO_LARGE` | Тело запроса больше лимита |
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED`, `INVALID_CREDENTIALS` | Нет или недействителен токен, неверный логин/пароль |
| 403 | `FORBIDDEN` | Роль не позволяет действие (например, INSPECTOR меняет системную категорию) |
| 404 | `NOT_FOUND` | Ресурса нет **или он чужой** (ADR-009) |
| 409 | `VERSION_CONFLICT`, `EMAIL_TAKEN`, `CATEGORY_CODE_TAKEN`, `RESOURCE_IN_USE`, `INVALID_STATE_TRANSITION`, `ALREADY_OBSERVED`, `REPORT_NOT_READY` | Конфликт версий или состояния; код системной категории занят; ресурс используется (помещение в осмотрах или с дефектами, категория с дефектами, черновик с наблюдениями других осмотров); дефект уже наблюдался в этом осмотре; отчёт ещё не готов |
| 423 | `ACCOUNT_LOCKED` | Временная блокировка после неудачных входов |
| 429 | `RATE_LIMITED` | Превышен лимит запросов (заголовок `Retry-After`) |
| 503 | `DEPENDENCY_UNAVAILABLE` | Недоступен зависимый сервис (media, report, ml) |
| 500 | `INTERNAL_ERROR` | Непредвиденная ошибка; детали только в логах по `requestId` |

## 2. core-service (внешний API)

### Аутентификация и профиль

| Метод | Путь | Назначение | Ответ |
|---|---|---|---|
| POST | `/auth/register` | Регистрация `{email, password, fullName}` | `201` профиль |
| POST | `/auth/login` | Вход `{email, password, client: "web"\|"android"}` | `200 {accessToken, expiresIn, refreshToken?}`; для web refresh-токен приходит в cookie |
| POST | `/auth/refresh` | Обновление: web — cookie + `X-CSRF-Protection: 1`; android — `{refreshToken}` | `200` новая пара токенов |
| POST | `/auth/logout` | Отзыв текущего refresh-токена | `204` |
| GET | `/users/me` | Профиль | `200` |
| PATCH | `/users/me` | `{fullName, locale, version}` | `200` |
| POST | `/users/me/password` | Смена пароля `{currentPassword, newPassword}`; отзывает все сессии | `204` |
| DELETE | `/users/me` | Удаление аккаунта и всех данных, требует `{password}` | `202` (очистка файлов асинхронно) |
| GET | `/.well-known/jwks.json` | Открытые ключи для проверки JWT | `200` JWKS |

Требования к паролю: ≥ 10 символов, не из списка распространённых паролей.

### Объекты и помещения

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/properties?archived=false&page&size&query` | Список своих объектов |
| POST | `/properties` | Создание `{name, type, address, city?, areaSqm?, notes?}` → `201` |
| GET | `/properties/{id}` | Карточка: объект, помещения, число осмотров, открытых дефектов |
| PATCH | `/properties/{id}` | Изменение полей + `version` |
| POST | `/properties/{id}/archive`, `/properties/{id}/unarchive` | Архивирование |
| DELETE | `/properties/{id}` | Физическое удаление со всеми данными → `202` |
| GET | `/properties/{id}/rooms` | Помещения |
| POST | `/properties/{id}/rooms` | `{name, roomType, sortOrder?}` |
| PATCH/DELETE | `/rooms/{id}` | Изменение / удаление (запрещено, если помещение есть в осмотрах или у него есть дефекты, → `409 RESOURCE_IN_USE`) |
| GET | `/properties/{id}/statistics` | Распределение дефектов по категориям, серьёзности, статусам и осмотрам |

### Справочники

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/defect-categories` | Системные + свои категории |
| POST | `/defect-categories` | Своя категория `{name}` |
| PATCH/DELETE | `/defect-categories/{id}` | Своя категория (удаление запрещено, если есть дефекты, → `409 RESOURCE_IN_USE`, можно деактивировать) |
| POST/PATCH | `/admin/defect-categories[/{id}]` | Системные категории (только ADMIN) |
| GET | `/checklist-templates` | Шаблоны чек-листов с пунктами |
| GET | `/dictionaries/severities` | Шкала серьёзности с переводами |

### Осмотры и чек-листы

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/properties/{id}/inspections` | История осмотров объекта (новые первыми) |
| POST | `/properties/{id}/inspections` | Создание `{inspectedAt, title?, notes?, roomIds[], templateCodes[]}` → `201` с чек-листом |
| GET | `/inspections/{id}` | Осмотр с чек-листом по помещениям и наблюдениями |
| PATCH | `/inspections/{id}` | Заголовок, дата, заметки, статус `IN_PROGRESS` |
| POST | `/inspections/{id}/complete` | Завершение (`COMPLETED`); после завершения изменения запрещены |
| DELETE | `/inspections/{id}` | Удаление (только `DRAFT`) |
| POST | `/inspections/{id}/checklist-items` | Пользовательский пункт `{roomId, elementGroup, title}` |
| PATCH | `/checklist-items/{id}` | `{result, comment, version}` |

### Дефекты и наблюдения

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/properties/{id}/defects?status=OPEN&roomId&severity` | Дефекты объекта |
| POST | `/inspections/{id}/defects` | Новый дефект с первым наблюдением `{roomId, checklistItemId?, categoryId, elementGroup, title, description?, severity, suggestionId?}` → `201` |
| GET | `/defects/{id}` | Дефект с наблюдениями и фото |
| PATCH | `/defects/{id}` | Категория, описание, серьёзность |
| GET | `/defects/{id}/history` | История статусов |
| GET | `/inspections/{id}/open-defects` | Дефекты, открытые до этого осмотра, с наблюдением в текущем осмотре (если уже сделано) |
| POST | `/inspections/{id}/observations` | Наблюдение существующего дефекта `{defectId, status: OPEN\|RESOLVED, comment?, severity?}`; одно на дефект в осмотре, иначе `409 ALREADY_OBSERVED` |
| PATCH | `/observations/{id}` | Изменение наблюдения |
| POST | `/observations/{id}/photos` | Привязка загруженного фото `{photoId, caption?}` |
| DELETE | `/observations/{id}/photos/{photoId}` | Отвязка (фото удаляется media через 24 ч) |

### Сравнение и подсказки

| Метод | Путь | Назначение |
|---|---|---|
| GET | `/inspections/compare?base={a}&target={b}` | Сравнение двух осмотров одного объекта (ADR-004) |
| POST | `/category-suggestions` | Подсказка категории по фото `{photoId}` → `200 {suggestionId, modelVersion, items:[{categoryId, code, name, probability}]}` или `200 {items: []}` при недоступности ML |

Пример ответа сравнения:

```json
{
  "base": { "id": "…", "inspectedAt": "2026-11-10T09:00:00Z" },
  "target": { "id": "…", "inspectedAt": "2026-12-01T09:00:00Z" },
  "summary": { "new": 2, "resolved": 5, "remaining": 3, "notChecked": 1 },
  "defects": [
    { "defectId": "…", "state": "RESOLVED", "title": "Трещина над окном", "severity": "MINOR", "room": "Кухня" },
    { "defectId": "…", "state": "NEW", "reopened": false, "title": "Скол плитки", "severity": "COSMETIC", "room": "Ванная" }
  ],
  "bySeverity": { "COSMETIC": { "new": 1, "resolved": 2, "remaining": 1, "notChecked": 0 } },
  "byCategory": [ { "categoryId": "…", "new": 1, "resolved": 2, "remaining": 0, "notChecked": 1 } ]
}
```

Ошибки: `400 VALIDATION_ERROR` (осмотры разных объектов или `base` позже `target`), `404` (нет доступа).

## 3. media-service (внешний API)

| Метод | Путь | Назначение | Ответ |
|---|---|---|---|
| GET | `/photos/limits` | Лимиты: допустимые типы, максимальный размер, максимум фото на наблюдение | `200` |
| POST | `/photos` | `multipart/form-data`: `file`, `propertyId` | `201 {id, contentType, width, height, sizeBytes}` |
| GET | `/photos/{id}/content?variant=original\|preview\|thumb` | JPEG (все варианты хранятся в JPEG, ADR-025), `Cache-Control: private` | `200 image/jpeg` |
| DELETE | `/photos/{id}` | Удаление неприкреплённого фото (только загрузившим) | `204`; прикреплённое — `409 RESOURCE_IN_USE` |

## 4. report-service (внешний API)

| Метод | Путь | Назначение | Ответ |
|---|---|---|---|
| POST | `/reports` | `{inspectionId, locale?}` | `202 {id, status: "QUEUED"}` + `Location` |
| GET | `/reports/{id}` | Статус задания | `200 {id, status, pageCount?, sizeBytes?, errorCode?}` |
| GET | `/reports?inspectionId=` | Ранее сформированные отчёты осмотра | `200` список |
| GET | `/reports/{id}/file` | PDF, `Content-Disposition: attachment` | `200 application/pdf`; не готов — `409 REPORT_NOT_READY` |

Рекомендуемый интервал опроса статуса — 2 с, до 60 с.

## 5. Внутренние API (не публикуются через nginx)

Требуют сервисный токен (аудитория `inspecto-internal`, ADR-007).

| Сервис | Метод | Путь | Вызывающий | Назначение |
|---|---|---|---|---|
| core | POST | `/internal/v1/auth/service-token` | media, report, ml | Получение сервисного токена (client credentials) |
| core | GET | `/internal/v1/access/properties/{id}?userId=&action=read\|write` | media, report | Проверка права пользователя на объект |
| core | GET | `/internal/v1/inspections/{id}/report-data` | report | Агрегат осмотра для отчёта (объект, помещения, чек-лист, дефекты, наблюдения, id фото) |
| media | GET | `/internal/v1/photos/{id}` | core | Метаданные фото (проверка владельца и объекта) |
| media | POST | `/internal/v1/photos/{id}/attach` | core | Пометить фото прикреплённым |
| media | GET | `/internal/v1/photos/{id}/content?variant=preview` | report, ml | Байты изображения |
| media | DELETE | `/internal/v1/photos?propertyId=` / `?ownerId=` | core (outbox) | Массовое удаление |
| report | DELETE | `/internal/v1/reports?propertyId=` / `?requestedBy=` | core (outbox) | Массовое удаление отчётов |
| ml | POST | `/internal/v1/classify` | core | `{photoId}` → `{modelVersion, predictions: [{code, probability}]}` (top-3) |
| ml | GET | `/internal/v1/model` | core | Версия и классы модели |
| все | GET | `/health/live`, `/health/ready` | docker compose | Проверки состояния |

Таймауты внутренних вызовов: 2 с (метаданные, доступ), 10 с (байты изображений, данные отчёта), 3 с (классификация). Повторы — только для идемпотентных запросов, до 2 раз.
