# gost-docker

Минимальный Docker-образ [gost](https://gost.run/) на базе `scratch` — HTTP/SOCKS-прокси с базовой аутентификацией.

В финальный образ попадают только бинарник `gost` и готовый `config.yml`. Порт, логин и пароль зашиваются **на этапе сборки** (build-args). Entrypoint не используется: `CMD ["/gost", "-C", "/config.yml"]`.

Главные артефакты сборки: **`dist/<IMAGE_NAME>.amd64.tar`** и **`dist/<IMAGE_NAME>.arm64.tar`**.

## Требования

- Docker
- `curl` (для тестов)
- Бинарники `gost-linux-amd64` и `gost-linux-arm64` в корне репозитория

## Настройка

```bash
cp .env.example .env
```

Все параметры обязательны и читаются из `.env`:

| Переменная   | Описание |
|--------------|----------|
| `PROXY_PORT` | Порт прослушивания gost (зашивается в конфиг образа) |
| `PROXY_USER` | Логин прокси (зашивается в образ) |
| `PROXY_PASS` | Пароль прокси (зашивается в образ) |
| `IMAGE_NAME` | Имя Docker-образа; архивы — `dist/<IMAGE_NAME>.amd64.tar` и `.arm64.tar` |

При смене `PROXY_*` нужна пересборка образа.

### Конфиг gost

| Файл | Назначение |
|------|------------|
| `config.minimal.yml` | Минимальный шаблон (референс) |
| `config.yml` | Рабочий конфиг — **именно он** попадает в образ при сборке |

Плейсхолдеры `__PROXY_PORT__`, `__PROXY_USER__`, `__PROXY_PASS__` подставляются на этапе `docker build`. Расширяйте `config.yml` под свои нужды; если файла нет, `build-image.sh` скопирует его из `config.minimal.yml`.

## Сборка

```bash
./build-image.sh
```

Скрипт:

1. читает `.env` и использует `config.yml`;
2. собирает два образа: `${IMAGE_NAME}:${IMAGE_TAG}-amd64` и `${IMAGE_NAME}:${IMAGE_TAG}-arm64` (`IMAGE_TAG` по умолчанию `latest`);
3. сохраняет архивы в **`dist/${IMAGE_NAME}.amd64.tar`** и **`dist/${IMAGE_NAME}.arm64.tar`**.

Пример с другим тегом:

```bash
IMAGE_TAG=1.0.0 ./build-image.sh
```

## Запуск

```bash
docker load -i dist/gost-proxy.amd64.tar
docker run -d -p 9997:9997 gost-proxy:latest-amd64
```

Для ARM: `dist/gost-proxy.arm64.tar` и тег `gost-proxy:latest-arm64`.

Порты в `-p` должны совпадать с `PROXY_PORT` из `.env` (в примере — `9997`).

## Тесты

Одна команда собирает артефакт, проверяет его и подчищает только созданное:

```bash
./tests.sh
```

Тесты читают **`.env.test`**, а не ваш `.env` (порт `55123`, отдельные логин/пароль/имя образа). Сборка идёт под архитектуру Docker-хоста — без отдельной amd64/arm64 логики.

Что делает скрипт:

1. собирает образ из `config.yml` с фикстурой `.env.test`;
2. сохраняет **`dist/gost-test.tar`**;
3. проверяет, что архив существует, не пуст и успешно `docker load`;
4. запускает контейнер **из загруженного артефакта** на `127.0.0.1:55123`;
5. выполняет smoke-кейсы прокси (AAA);
6. в конце удаляет контейнер, тег образа и тестовый `dist/gost-test.tar` (архивы `build-image.sh` — `*.amd64.tar` / `*.arm64.tar` — не трогает).

Кейсы:

0. артефакт `dist/gost-test.tar` валиден (файл + `docker load`);
1. при валидных `PROXY_PORT` / `PROXY_USER` / `PROXY_PASS` из `.env.test` запрос проксируется;
2. при неверном пароле запрос не проходит.

Опционально: `TEST_URL` (по умолчанию `https://github.com`; в CI задаётся в workflow).

## CI

При пуше в `main` GitHub Actions прогоняет `./tests.sh` (workflow [`.github/workflows/tests.yml`](.github/workflows/tests.yml)). В репозитории должны быть закоммичены `gost-linux-amd64` и `gost-linux-arm64`.

## Структура

| Файл / путь | Назначение |
|-------------|------------|
| `Dockerfile` | Мультистейдж: рендер `config.yml` → `scratch` |
| `config.minimal.yml` | Минимальный шаблон конфига |
| `config.yml` | Расширяемый конфиг для сборки (`__PROXY_*__`) |
| `render-config.sh` | Подстановка build-args в конфиг на этапе сборки |
| `build-image.sh` | Сборка amd64 и arm64 образов, экспорт в `dist/<IMAGE_NAME>.<arch>.tar` |
| `dist/` | Каталог артефактов (в git не коммитится) |
| `tests.sh` | Smoke-тесты с фокусом на `dist/*.tar` и автоочисткой |
| `.github/workflows/tests.yml` | CI: тесты при пуше в `main` |
| `.env.example` | Пример переменных окружения |
| `.env.test` | Фикстура для `./tests.sh` |

## Как это работает

1. Стадия `config` (BusyBox): `render-config.sh` собирает итоговый конфиг из `config.yml` и build-args.
2. Стадия `scratch`: в образ копируются только `/gost` и `/config.yml`.
3. Контейнер стартует командой `CMD ["/gost", "-C", "/config.yml"]`.
4. `build-image.sh` сохраняет образы в `dist/<IMAGE_NAME>.amd64.tar` и `.arm64.tar`.
