# Include variables from the .envrc file
include .envrc

# ==================================================================================== #
# HELPERS
# ==================================================================================== #

## help: print this help message
.PHONY: help
help:
	@echo 'Usage:'
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' | sed -e 's/^/ /'

.PHONY: confirm
confirm:
	@echo 'Are you sure? [y/N]' && read ans && [ $${ans: -N} = y ]

# ==================================================================================== #
# DEVELOPMENT
# ==================================================================================== #


## run/api: run the cmd/api application
.PHONY: run/api
run/api:
	go run ./cmd/api -db-dsn=${LIGHTEN_DB_DSN}

## db/psql: connect to the database using psql
.PHONY: db/psql
db/psql:
	psql ${LIGHTEN_DB_DSN}

## db/migrations/new name=$1: create a new database migration
.PHONY: db/migrations/new
db/migrations/new:
	@echo 'Creating migration files for ${name}'
	migrate create -seq -dir=./migrations -ext=.sql ${name}

## db/migrations/up: apply all database migrations
.PHONY: db/migrations/up
db/migrations/up: confirm
	@echo 'Running up migrations...'
	migrate -path=./migrations -database=${LIGHTEN_DB_DSN} up

# ==================================================================================== #
# QUALITY CONTROL
# ==================================================================================== #

## audit: tidy dependencies and format, vet and test all code
.PHONY: audit
audit:
	@echo 'Tidying and verifying module dependencies...'
	go mod tidy
	go mod verify
	@echo 'Formatting code...'
	go fmt ./...
	@echo 'Vetting code...'
	go vet ./...
	staticcheck ./...
	@echo 'Running tests...'
	go test -race -vet=off ./...

# ==================================================================================== # 
# BUILD
# ==================================================================================== #

current_time = $(shell date -Iseconds)
git_description = $(shell git describe --always --dirty --tags --long)
linker_flags = '-s -X main.buildTime=${current_time} -X main.version=${git_description}'

## build/api: build the cmd/api application
.PHONY: build/api
build/api:
	@echo 'Building cmd/api...'
	go build -ldflags=${linker_flags} -o=./bin/api ./cmd/api
	GOOS=linux GOARCH=amd64 go build -ldflags=${linker_flags} -o=./bin/linux_amd64/api ./cmd/api

# ==================================================================================== # 
# PRODUCTION
# ==================================================================================== #

production_host_ip = '188.166.102.183'

## production/connect: connect to the production server
.PHONY: production/connect
production/connect:
	ssh lighten@${production_host_ip}

## production/deploy/api: deploy the api to production
.PHONY: production/deploy/api
production/deploy/api:
	rsync -rP --delete ./bin/linux_amd64/api ./migrations lighten@${production_host_ip}:~
	ssh -t lighten@${production_host_ip} 'migrate -path ~/migrations -database $$LIGHTEN_DB_DSN up'

## production/configure/api.service: configure the production systemd api.service file
.PHONY: production/configure/api.service
production/configure/api.service:
	rsync -P ./remote/production/api.service lighten@${production_host_ip}:~
	ssh -t lighten@${production_host_ip} '\
	 sudo mv ~/api.service /etc/systemd/system/ \
	 && sudo systemctl enable api \
	 && sudo systemctl restart api \
	'

## production/configure/caddyfile: configure the production Caddyfile
.PHONY: production/configure/caddyfile
production/configure/caddyfile:
	rsync -P ./remote/production/Caddyfile lighten@${production_host_ip}:~
	ssh -t lighten@${production_host_ip} '\
	 sudo mv ~/Caddyfile /etc/caddy/ \
	 && sudo systemctl reload caddy \
	'