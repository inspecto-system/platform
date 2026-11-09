# Общие конфигурации качества кода

Канонические конфигурации линтеров для всех репозиториев (CODE_QUALITY.md §3).

| Каталог | Используется в | Как применяется |
|---|---|---|
| `go/.golangci.yml` | media-service, report-service | Копия в корне репозитория; CI (`go.yml`) падает при расхождении с этим файлом |

Конфигурации Checkstyle, PMD и SpotBugs живут в `core-service` (единственный Java-репозиторий), правила ktlint и detekt — в `android`, ESLint и Prettier — в `web`, ruff и mypy — в `ml`: у каждого языка один репозиторий-владелец, поэтому копий нет.

## Переиспользуемые CI-workflow

| Workflow | Назначение | Подключение |
|---|---|---|
| `.github/workflows/java-gradle.yml` | Сборка, Spotless, Checkstyle, PMD, SpotBugs, тесты, JaCoCo | `uses: inspecto-system/platform/.github/workflows/java-gradle.yml@main` |
| `.github/workflows/go.yml` | golangci-lint, сборка, тесты с `-race`, порог покрытия, govulncheck | `uses: inspecto-system/platform/.github/workflows/go.yml@main` |
| `.github/workflows/container.yml` | Сборка образа из Dockerfile сервиса, проверка непривилегированного пользователя, Trivy (High/Critical с исправлением блокируют) | `uses: inspecto-system/platform/.github/workflows/container.yml@main` с `image: inspecto/<сервис>` |
| `.github/workflows/node.yml` | Prettier, ESLint, `tsc`, Vitest с порогами покрытия, `next build`, по желанию Playwright | `uses: inspecto-system/platform/.github/workflows/node.yml@main` |
| `.github/workflows/python.yml` | ruff format, ruff (в том числе правила bandit `S`), mypy strict, pytest с порогом покрытия из `pyproject.toml`; зависимости — `uv sync --locked` | `uses: inspecto-system/platform/.github/workflows/python.yml@main` с `working-directory: <каталог проекта>` |
| `.github/workflows/android.yml` | ktlint, detekt, Android Lint, unit-тесты, Kover, `assembleDebug` | `uses: inspecto-system/platform/.github/workflows/android.yml@main` |
| `.github/workflows/security.yml` | Gitleaks, Dependency Review, CodeQL | `uses: inspecto-system/platform/.github/workflows/security.yml@main` |

Вызывающий workflow должен выдать права не меньше тех, что запрашивает переиспользуемый: `contents: write` для `java-gradle.yml` и `android.yml` (отправка графа зависимостей), `security-events: write` для `security.yml` (CodeQL), иначе запуск завершается ошибкой `startup_failure`.

Каждый вызывающий workflow задаёт `concurrency` с `cancel-in-progress: true`: новый коммит в ветку отменяет устаревшие запуски и не занимает очередь GitHub Actions. CodeQL — самая долгая проверка — запускается при слиянии в `main` и еженедельно, а не на каждый коммит PR; Gitleaks и Dependency Review выполняются на каждом PR.
