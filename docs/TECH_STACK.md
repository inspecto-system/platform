# Технологический стек Inspecto

## 1. Сводка

| Компонент | Технологии | Обоснование |
|---|---|---|
| core-service | Java (LTS), Spring Boot, Spring Security, Spring Data JPA (Hibernate), Flyway, springdoc-openapi, MapStruct, Gradle (Kotlin DSL) | Индустриальный стандарт для транзакционной бизнес-логики; основной стек разработчика; зрелая экосистема безопасности |
| media-service | Go, chi (маршрутизация), pgx (PostgreSQL), golang-migrate, AWS SDK for Go v2 (S3), стандартная библиотека и `golang.org/x/image` для изображений (ADR-025), golang-jwt + keyfunc (проверка JWT по JWKS) | Сервис ввода-вывода и обработки изображений: конкурентность, малый образ, быстрый старт |
| report-service | Go, chi, pgx, golang-migrate, AWS SDK for Go v2 (S3), `html/template` | Фоновые задания и работа с файлами; `html/template` автоматически экранирует данные |
| PDF-рендеринг | Gotenberg (headless Chromium) | Качественная вёрстка HTML/CSS, кириллица, разрывы страниц (ADR-012) |
| ml-service | Python, FastAPI, ONNX Runtime, Pillow, Pydantic | Лёгкий CPU-инференс без PyTorch в проде |
| ML-исследование | PyTorch, timm, scikit-learn; обучение локально на CPU (ADR-027) | Стандарт для transfer learning; метрики sklearn |
| Web | Next.js (App Router), React, TypeScript (strict), Tailwind CSS, shadcn/ui, TanStack Query, next-intl, openapi-typescript | Типобезопасность от контракта до UI; доступные компоненты |
| Android | Kotlin, Jetpack Compose, ViewModel, Hilt, Room, Retrofit + OkHttp, kotlinx.serialization, CameraX, WorkManager, Coil, DataStore | Современный рекомендуемый стек Android |
| База данных | PostgreSQL 16 | Требование проекта; транзакции, `jsonb`, надёжность |
| Хранилище файлов | SeaweedFS (S3 API) | Отделение файлов от БД (ADR-006, ADR-024), совместимость с облачным S3 |
| Точка входа | nginx | TLS, маршрутизация, rate limiting, заголовки безопасности (ADR-013) |
| Контракты | OpenAPI 3.1, Spectral, openapi-generator (Kotlin), openapi-typescript | Contract-first (ADR-014) |
| Инфраструктура | Docker, docker compose | ADR-020 |
| CI/CD | GitHub Actions | Встроен в GitHub, бесплатен для публичных репозиториев |

## 2. Политика версий

- Используются **актуальные стабильные версии** на момент создания каждого компонента; для Java — актуальная LTS-версия, совместимая со всеми анализаторами из CODE_QUALITY.md (Checkstyle, PMD, SpotBugs, JaCoCo).
- Точные версии фиксируются при создании каркаса компонента (lock-файлы, Gradle version catalog, `go.mod`, `package-lock.json`) и записываются в раздел 4 этого документа.
- Обновление зависимостей — через Dependabot (еженедельно), каждое обновление проходит полный CI.

## 3. Распределение ответственности между языками

| Язык | Где | Почему именно здесь |
|---|---|---|
| **Java** | core-service | Самая сложная бизнес-логика, транзакции, безопасность — используется сильнейший стек разработчика и Spring Security |
| **Go** | media-service, report-service | Инфраструктурные сервисы с файлами и фоновыми задачами: эффективная конкурентность (горутины для воркеров и загрузок), статические бинарники, образы < 30 МБ |
| **Python** | ml-service, исследование | ML-экосистема (PyTorch, timm, ONNX) доступна только здесь в полном объёме |
| **Kotlin** | Android | Официальный язык Android |
| **TypeScript** | Web | Типобезопасность клиента, генерация типов из OpenAPI |

## 4. Зафиксированные версии

Заполняется по мере создания компонентов.

| Компонент | Ключевые версии | Дата фиксации |
|---|---|---|
| — | — | — |

## 5. Сознательно не используются

| Технология | Причина |
|---|---|
| Kubernetes | Масштаб проекта не требует оркестрации; docker compose достаточно (ADR-020) |
| Kafka / RabbitMQ | Асинхронность решается таблицами заданий (ADR-010, ADR-011) |
| Redis | Нет задачи: сессии — JWT, кеш прав — в памяти сервиса с коротким TTL |
| Отдельный API Gateway (Spring Cloud Gateway) | nginx покрывает маршрутизацию, TLS и rate limiting (ADR-013) |
| GraphQL | REST проще для контрактов, кеширования и тестирования |
| Сторонние AI API для классификации | Требование проекта: собственная обученная модель и реальная оценка |
