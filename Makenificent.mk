.DEFAULT_GOAL := help

DATABASE_NAME ?= shopware
DUMPFILE ?= dump.sql.zip
MEDIA_FILE ?= media.tar
THUMBNAIL_FILE ?= thumbnail.tar
BUNDLES_DIR ?= public/bundles
THEME_DIR ?= public/theme
THEME_PLUGIN ?=
PLUGINS_FOLDER = src/custom/plugins
SAMPLE_PLUGINS = $(PLUGINS_FOLDER)/DockwareSamplePlugin $(PLUGINS_FOLDER)/SwagPlatformDemoData

DOCKER_SERVICE_NAME ?= project
DOCKER_CONTAINER_NAME ?= project-dev
DOCKER_COMPOSE_FILE = docker-compose.override.yml
INSIDE_DOCKER = $(shell cat /proc/1/cgroup 2> /dev/null | grep "docker" | wc -l | sed 's/^ *//')

# Execution prefix. Empty when inside container, contains a docker-compose exec
# wrapper when outside of a container
EXEC =
DOCKER_COMPOSE_ARGS ?=

ifneq ($(INSIDE_DOCKER), 0)
	INSIDE_DOCKER = 1
else
	EXEC = docker-compose exec -T $(DOCKER_SERVICE_NAME) $(DOCKER_COMPOSE_ARGS)
endif

# PHP linter
DOCKER_PHP_LINTER_IMAGE = registry.guthand.com/guthand/infrastructure/docker-libary/php:linter
PHP_LINTER_EXEC = @docker run -i --rm -v $$(pwd):/code -w /code ${DOCKER_PHP_LINTER_IMAGE}
CACHE = .cache

# Plugins
PLUGIN_LIST = $(foreach plugin, $(filter-out $(SAMPLE_PLUGINS), $(wildcard $(PLUGINS_FOLDER)/*)), $(notdir $(plugin)))

build-app-default: install storefront install-plugins download-src ## make build-app
install-default: stop build start copy-configs upload-plugins change-permissions download-src ## make install
reload-default: stop start copy-configs ## make reload
storefront-default: delete-storefront build-storefront ## make storefront

$(DOCKER_COMPOSE_FILE):
	@cp ./sandbox/$@ .

.PHONY: build
build-default: ## make build
	docker-compose build

start-default: $(DOCKER_COMPOSE_FILE) ## make start
	docker-compose up -d --remove-orphans

stop-default: ## make stop
	docker-compose down

ssh-default: ## make ssh
	docker exec -it $(DOCKER_CONTAINER_NAME) bash

destroy-default: ## make destroy
	docker-compose down -v

change-permissions-default: ## make change-permissions
	${EXEC} bash -c "sudo chown -R dockware:www-data /var/www/html"

copy-configs-default: ## make upload-configs
	if [ -f "sandbox/.env" ]; then docker cp sandbox/.env  $(DOCKER_CONTAINER_NAME):/var/www/html/.; fi
	if [ -d "sandbox/config/packages" ]; then docker cp sandbox/config/packages  $(DOCKER_CONTAINER_NAME):/var/www/html/config; fi

download-src-default: ## make download-src
	docker cp $(DOCKER_CONTAINER_NAME):/var/www/html/. ./src

build-storefront-default: ## make build-storefront
	${EXEC}  bin/build-js.sh
	${EXEC}  bin/console theme:compile

delete-storefront-default: ## make delete-storefront
	if docker exec $(DOCKER_CONTAINER_NAME) [ -d "$(THEME_DIR)" ]; then ${EXEC}  rm -r $(THEME_DIR); fi
	if docker exec $(DOCKER_CONTAINER_NAME) [ -d "$(BUNDLES_DIR)" ]; then ${EXEC}  rm -r $(BUNDLES_DIR); fi

init-db-default: ## make init-db
	unzip sandbox/$(DUMPFILE)
	${EXEC}  mysql -uroot -proot -e "DROP DATABASE IF EXISTS ${DATABASE_NAME}"
	${EXEC}  mysql -uroot -proot -e "CREATE DATABASE ${DATABASE_NAME}"
	${EXEC}  mysql -uroot -proot $(DATABASE_NAME) < dump.sql
	rm -rf dump.sql

db-dump-default: ## make db-dump
	${EXEC} mysqldump -uroot -proot $(DATABASE_NAME) > dump.sql
	zip dump.sql.zip dump.sql
	mv dump.sql.zip sandbox/dump.sql.zip
	rm -rf dump.sql

install-plugins-default: ## make install-plugins
	${EXEC} bin/console plugin:refresh
	$(foreach plugin, $(PLUGIN_LIST), ${EXEC} bin/console plugin:install -n --activate $(plugin);)
	${EXEC} bin/console cache:clear
	${EXEC} bin/build-storefront.sh
	if [ -d "$(PLUGINS_FOLDER)/$(THEME_PLUGIN)" ]; then\
		${EXEC} bin/console theme:change -n --all $(THEME_PLUGIN);\
	fi

upload-plugins-default: ## make upload-plugins
	docker cp src/custom/plugins/ $(DOCKER_CONTAINER_NAME):/var/www/html/custom/.

$(CACHE):
	@mkdir -p .cache
	
update-php-linter-image:
	docker pull $(DOCKER_PHP_LINTER_IMAGE)

phpcs-default: ## make phpcs
	${PHP_LINTER_EXEC} phpcs

phpcbf-default: ## make phpcbf
	${PHP_LINTER_EXEC} phpcbf --version

phpcs-fix-default: $(CACHE) ## make phpcs-fix
	${PHP_LINTER_EXEC} php-cs-fixer fix

psalm-default: $(CACHE) ## make psalm
	${PHP_LINTER_EXEC} psalm --show-info=false

php-lint-default: phpcs phpcbf phpcs-fix psalm ## make php-lint

.PHONY: help
help:
	@echo "Makenificent.mk"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makenificent.mk | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
	@echo "Makefile"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

%: %-default
	@ true
