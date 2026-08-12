# gost-docker

Минимальный Docker-образ [gost](https://gost.run/) на базе `scratch` — HTTP/SOCKS-прокси с базовой аутентификацией.

В финальный образ попадают только бинарник `gost` и готовый `config.yml`. Порт, логин и пароль зашиваются **на этапе сборки** (build-args). Entrypoint не используется: `CMD ["/gost", "-C", "/config.yml"]`.

Главный артефакт сборки: **`dist/<IMAGE_NAME>.tar`** (по умолчанию `dist/gost-proxy.tar`).

## Требования

- Docker
- `curl` (для тестов)
- Бинарник `gost-linux-amd64` в корне репозитория

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
| `IMAGE_NAME` | Имя Docker-образа и файла архива (`dist/<IMAGE_NAME>.tar`) |

При смене `PROXY_*` нужна пересборка образа.

### Конфиг gost

| Файл | Назначение |
|------|------------|
| `config.minimal.yml` | Минимальный шаблон (референс) |
| `config.yml` | Рабочий конфиг — **именно он** попадает в образ при сборке |

Плейсхолдеры `__PROXY_PORT__`, `__PROXY_USER__`, `__PROXY_PASS__` подставляются на этапе `docker build`. Расширяйте `config.yml` под свои нужды; если файла нет, `build-image.sh` / `tests.sh` скопируют его из `config.minimal.yml`.

## Сборка

```bash
./build-image.sh
```

Скрипт:

1. читает `.env` и использует `config.yml`;
2. собирает образ `${IMAGE_NAME}:${IMAGE_TAG}` (`IMAGE_TAG` по умолчанию `latest`);
3. сохраняет архив в **`dist/${IMAGE_NAME}.tar`**.

Пример с другим тегом:

```bash
IMAGE_TAG=1.0.0 ./build-image.sh
```

## Запуск

```bash
docker load -i dist/gost-proxy.tar
docker run -d -p 9997:9997 gost-proxy
```

Порты в `-p` должны совпадать с `PROXY_PORT` из `.env` (в примере — `9997`).

## Тесты

Одна команда собирает артефакт, проверяет его и подчищает только созданное:

```bash
./tests.sh
```

Что делает скрипт:

1. собирает временный образ `${IMAGE_NAME}:testconnect-<pid>` из `config.yml`;
2. сохраняет **`dist/${IMAGE_NAME}.tar`**;
3. проверяет, что архив существует, не пуст и успешно `docker load`;
4. запускает контейнер **из загруженного артефакта**;
5. выполняет smoke-кейсы прокси (AAA);
6. в конце удаляет только этот контейнер и тег образа (`dist/*.tar` не трогает).

Кейсы:

0. артефакт `dist/<IMAGE_NAME>.tar` валиден (файл + `docker load`);
1. при валидных `PROXY_PORT` / `PROXY_USER` / `PROXY_PASS` запрос проксируется;
2. при неверном пароле запрос не проходит.

Опционально: `PROXY_HOST` (по умолчанию `127.0.0.1`), `TEST_URL` (по умолчанию `https://github.com`; в CI задаётся в workflow).

## CI

При пуше в `main` GitHub Actions прогоняет `./tests.sh` (workflow [`.github/workflows/tests.yml`](.github/workflows/tests.yml)). В репозитории должен быть закоммичен `gost-linux-amd64`.

## Структура

| Файл / путь | Назначение |
|-------------|------------|
| `Dockerfile` | Мультистейдж: рендер `config.yml` → `scratch` |
| `config.minimal.yml` | Минимальный шаблон конфига |
| `config.yml` | Расширяемый конфиг для сборки (`__PROXY_*__`) |
| `render-config.sh` | Подстановка build-args в конфиг на этапе сборки |
| `build-image.sh` | Сборка образа и экспорт в `dist/<IMAGE_NAME>.tar` |
| `dist/` | Каталог артефактов (в git не коммитится) |
| `tests.sh` | Smoke-тесты с фокусом на `dist/*.tar` и автоочисткой |
| `.github/workflows/tests.yml` | CI: тесты при пуше в `main` |
| `.env.example` | Пример переменных окружения |

## Как это работает

1. Стадия `config` (BusyBox): `render-config.sh` собирает итоговый конфиг из `config.yml` и build-args.
2. Стадия `scratch`: в образ копируются только `/gost` и `/config.yml`.
3. Контейнер стартует командой `CMD ["/gost", "-C", "/config.yml"]`.
4. `build-image.sh` / `tests.sh` сохраняют образ в `dist/<IMAGE_NAME>.tar` — это основной артефакт.
