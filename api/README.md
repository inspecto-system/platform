# Контракты API Inspecto

Формальные спецификации OpenAPI 3.1 (contract-first, ADR-014). Человекочитаемый каталог — [docs/API_DOCUMENTATION.md](../docs/API_DOCUMENTATION.md); при расхождении источник истины — эти файлы.

| Файл | Сервис | Содержимое |
|---|---|---|
| `common.yaml` | — | Общие схемы, параметры, ответы об ошибках (RFC 9457), схемы безопасности |
| `core.yaml` | core-service | Аутентификация, объекты, осмотры, дефекты, сравнение, подсказки; внутренние `/internal/v1/**` |
| `media.yaml` | media-service | Фотографии; внутренние `/internal/v1/photos/**` |
| `report.yaml` | report-service | PDF-отчёты; внутренний `/internal/v1/reports` |
| `ml.yaml` | ml-service | Классификация фото (только внутренний API) |

## Версионирование

- Версия контрактов — поле `info.version` (одинаковое во всех файлах) и git-тег `api-vX.Y.Z` на коммит в `main`.
- MINOR — обратно совместимые изменения (новые endpoints, необязательные поля); MAJOR — несовместимые (новый префикс `/api/v2`).
- Клиенты (Android, Web) и серверы генерируют код из **тегированной** версии.

## Проверки

```bash
npx @stoplight/spectral-cli@6 lint api/*.yaml --fail-severity error   # правила OpenAPI
python3 api/scripts/check_refs.py                                     # $ref, operationId, параметры путей, JSON Schema
```

Обе проверки выполняются в CI (`.github/workflows/api.yml`).

## Правило изменения

Изменение контракта — отдельный PR в `platform`, который сливается **до** PR сервера и клиентов (ADR-021); `docs/API_DOCUMENTATION.md` обновляется в том же PR.
