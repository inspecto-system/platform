# Стандарты качества кода Inspecto

> Обязательны для всех репозиториев организации `inspecto-system` с первого коммита каждого компонента. Отключение проверки ради успешной сборки запрещено; исключение из правила оформляется точечным подавлением в коде с комментарием-обоснованием и проходит ревью.

## 1. Общие принципы

- **SOLID, DRY, KISS**, разделение ответственности (слои: API → сервис → репозиторий/клиент; бизнес-логика не зависит от фреймворка там, где это разумно).
- Понятные имена: сущности и методы называются терминами предметной области из DATABASE.md (`Inspection`, `DefectObservation`, а не `Data`, `Item2`).
- Нет неиспользуемого кода, полей, классов, зависимостей; нет закомментированного кода; нет временных обходных решений в основной ветке.
- Ошибки не глотаются: каждое исключение либо обрабатывается осмысленно, либо преобразуется в доменную ошибку с кодом из API_DOCUMENTATION.md, либо пробрасывается.
- Контроль сложности: цикломатическая сложность метода ≤ 10, длина метода ≤ 50 строк, число параметров ≤ 5 (проверяется анализаторами, см. ниже).
- Единообразие внутри компонента: один стиль структуры пакетов, один способ обработки ошибок, один способ логирования.
- Логи — структурированные (JSON), без паролей, токенов и персональных данных (SECURITY.md).

## 2. Обязательные проверки CI

Запускаются на каждый `push` и `pull_request` во всех репозиториях. PR не готов к слиянию, если упала любая проверка.

| Проверка | Java (core) | Go (media, report) | Kotlin (Android) | TypeScript (Web) | Python (ml) |
|---|---|---|---|---|---|
| Форматирование | Spotless (google-java-format) | gofmt, goimports (через golangci-lint) | ktlint | Prettier | ruff format |
| Линтинг | Checkstyle | golangci-lint | detekt, Android Lint | ESLint (typescript-eslint, react-hooks) | ruff |
| Статический анализ | PMD, SpotBugs (+ find-sec-bugs) | go vet, staticcheck, gosec (в составе golangci-lint) | detekt, Android Lint | `tsc --noEmit` (strict) | mypy (strict) |
| Неиспользуемый код | PMD (`UnusedPrivateField`, `UnusedPrivateMethod`, `UnusedLocalVariable`), компилятор `-Xlint:all -Werror` | `unused` (U1000), `ineffassign`, `unparam` | detekt `UnusedPrivateMember`, Android Lint `UnusedResources` | ESLint `no-unused-vars`, `noUnusedLocals`, `noUnusedParameters` | ruff `F401`, `F841` |
| Сборка | `./gradlew build` | `go build ./...` | `./gradlew assembleDebug` | `next build` | сборка образа |
| Unit-тесты | JUnit 5 | `go test -race` | JUnit 5 / MockK | Vitest + React Testing Library | pytest |
| Интеграционные тесты | Testcontainers (PostgreSQL, MinIO) | testcontainers-go | Room in-memory, MockWebServer | Playwright (с CP5) | pytest + тестовая модель |
| Покрытие | JaCoCo | `go test -cover` + проверка порога | Kover | Vitest coverage (v8) | pytest-cov |
| Уязвимости зависимостей | Dependency Review (граф зависимостей Gradle отправляется в GitHub) + Dependabot | Dependency Review + Dependabot, govulncheck | Dependency Review + Dependabot | Dependency Review + Dependabot | Dependency Review + Dependabot |
| Безопасность кода | CodeQL | CodeQL, gosec | CodeQL | CodeQL | CodeQL, bandit (ruff `S`) |
| Секреты | Gitleaks | Gitleaks | Gitleaks | Gitleaks | Gitleaks |
| Контейнеры | Trivy (образ, с появлением Dockerfile) | Trivy | — | Trivy | Trivy |
| Контракт API | Проверка ответов по OpenAPI в интеграционных тестах | То же | Генерация клиента из тегированной версии | То же | То же |

Пересечения инструментов настраиваются так, чтобы одно нарушение не сообщалось несколькими анализаторами: стиль — только форматтер и Checkstyle/ktlint/ESLint; ошибки — PMD/SpotBugs/staticcheck/detekt.

Репозиторий `platform` проверяет Markdown (markdownlint), OpenAPI (Spectral) и секреты (Gitleaks).

## 3. Единые правила для всех репозиториев

- Переиспользуемые workflow GitHub Actions лежат в `platform/.github/workflows/` (`java-gradle.yml`, `go.yml`, `security.yml`; `workflow_call`) и подключаются из сервисных репозиториев одной строкой; общие конфигурации линтеров — в `platform/quality/` (см. `quality/README.md`).
- Версии инструментов закреплены (не `latest`); действия GitHub Actions закреплены по SHA коммита.
- Кеширование зависимостей (Gradle, Go modules, npm, pip) обязательно; запуск только по изменённым путям там, где это безопасно.
- Защита ветки `main`: только через PR, обязательные проверки CI, запрет force push (ADR-021).
- Сообщения коммитов — Conventional Commits: `feat(core): …`, `fix(media): …`, `docs: …`, `test: …`, `ci: …`, `refactor: …`.
- Ветки: `feat/<кратко>`, `fix/<кратко>`, `docs/<кратко>`, `ci/<кратко>`.
- Шаблон PR: что сделано · какие файлы · как проверить · какие тесты выполнены · известные проблемы · связанные PR в других репозиториях.

## 4. Требования к тестам

- Каждая публичная операция бизнес-логики имеет unit-тесты на успешный путь и на каждую документированную ошибку.
- Для каждого внешнего endpoint — интеграционный тест: успех, валидация, `401`, доступ к чужому ресурсу (`404`).
- Тесты независимы, детерминированы (фиксированное время через `Clock`, фиксированные seed), не зависят от порядка запуска и от сети.
- Имена тестов описывают поведение: `shouldReturnNotFoundWhenPropertyBelongsToAnotherUser`.
- Моки — только для внешних границ (HTTP-клиенты других сервисов, время); базы и MinIO — настоящие через Testcontainers.
- Сломанный тест не отключается: либо исправляется код, либо тест (с объяснением в PR).

## 5. Покрытие тестами

| Область | Минимум | Контроль |
|---|---|---|
| Критичная бизнес-логика: сравнение осмотров, статусы дефектов и наблюдений, права доступа, аутентификация и токены, обработка изображений, задания отчётов | **80 % строк и ветвей** | Правила JaCoCo / проверки порога на уровне пакетов `…domain`, `…security`, `…comparison`; в Go — пакеты `internal/service`, `internal/imaging`, `internal/jobs` |
| Остальной код компонента | 60 % строк | Общий порог; не должен снижаться относительно `main` |
| DTO, конфигурация, сгенерированный код | Не учитываются | Исключены из отчёта |

Покрытие — ориентир, а не цель: тест без проверок (assert) ради процента недопустим и отклоняется на ревью.

## 6. Локальный запуск проверок

| Компонент | Команда |
|---|---|
| core-service | `./gradlew spotlessApply check` (форматирование, Checkstyle, PMD, SpotBugs, тесты, JaCoCo) |
| media-service, report-service | `make lint test` (golangci-lint, govulncheck, `go test -race -cover`) |
| android | `./gradlew ktlintCheck detekt lint testDebugUnitTest koverVerify` |
| web | `npm run format:check && npm run lint && npm run typecheck && npm test` |
| ml | `ruff format --check . && ruff check . && mypy . && pytest --cov` |
| platform | `npx markdownlint-cli2 "**/*.md"` |

Точные команды фиксируются в README каждого репозитория при создании каркаса.

## 7. Ревью

- Ревью выполняют Claude (самопроверка перед открытием PR, комментарии в PR) и владелец проекта; слияние — только владелец.
- Чек-лист ревью: соответствие контракту и документации; проверка прав на каждый ресурс; обработка ошибок; тесты на ошибки; отсутствие секретов и персональных данных в логах; обновлена документация (PROGRESS, TASKS, при необходимости ARCHITECTURE/DATABASE/API/DECISIONS).
