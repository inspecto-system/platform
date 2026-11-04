# Inspecto · platform

Общий репозиторий информационной системы **Inspecto** — системы для осмотра и приёмки объектов недвижимости.

Здесь находятся документация проекта, архитектура, контракты API, конфигурация развёртывания и общие CI-шаблоны для всех репозиториев организации [`inspecto-system`](https://github.com/inspecto-system).

## Репозитории системы

| Репозиторий | Назначение |
|---|---|
| `platform` | Документация, архитектура, OpenAPI-контракты, развёртывание, общие CI-шаблоны |
| `core-service` | Основной сервис (Java, Spring Boot) |
| `media-service` | Фотографии (Go) |
| `report-service` | PDF-отчёты (Go) |
| `web` | Веб-приложение (Next.js, TypeScript) |
| `android` | Android-приложение (Kotlin, Jetpack Compose) |
| `ml` | ML-исследование и сервис классификации дефектов (Python) |

## С чего начать

| Документ | Содержание |
|---|---|
| [docs/PROGRESS.md](docs/PROGRESS.md) | Текущее состояние и следующие шаги |
| [docs/PROJECT_PLAN.md](docs/PROJECT_PLAN.md) | План, сроки, контрольные точки |
| [docs/TASKS.md](docs/TASKS.md) | Задачи со статусами и критериями готовности |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Обзор архитектуры |
| [docs/architecture/INSPECTO_SYSTEM_ARCHITECTURE.pdf](docs/architecture/INSPECTO_SYSTEM_ARCHITECTURE.pdf) | Подробный архитектурный документ (PDF) |
| [docs/DECISIONS.md](docs/DECISIONS.md) | Журнал архитектурных решений |
| [docs/DATABASE.md](docs/DATABASE.md) | Схема данных |
| [docs/API_DOCUMENTATION.md](docs/API_DOCUMENTATION.md) | Каталог API |
| [docs/TECH_STACK.md](docs/TECH_STACK.md) | Технологии и обоснование |
| [docs/CODE_QUALITY.md](docs/CODE_QUALITY.md) | Стандарты качества и CI |
| [docs/TESTING.md](docs/TESTING.md) | Стратегия тестирования |
| [docs/SECURITY.md](docs/SECURITY.md) · [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) | Безопасность и модель угроз |
| [docs/ML_DOCUMENTATION.md](docs/ML_DOCUMENTATION.md) | ML-исследование |
| [docs/RESEARCH.md](docs/RESEARCH.md) | Аналоги, методика эксперимента, источники |
| [docs/THESIS_NOTES.md](docs/THESIS_NOTES.md) | Материалы для РПЗ и диплома |

## Процесс работы

Каждое изменение — отдельная ветка и Pull Request; CI обязателен; слияние в `main` выполняет владелец проекта (ADR-021).
