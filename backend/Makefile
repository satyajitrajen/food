verify:
	go vet ./...
	go test ./...
	go build ./...

# Build the landing/console app and copy it into the embed folder.
# (Requires Node: `cd ../landing && npm install` once.)
web:
	cd ../landing && npm run build
	rm -rf internal/web/webroot
	mkdir -p internal/web/webroot
	cp -R ../landing/dist/. internal/web/webroot/

run:
	@echo "local dev: FOODPOS_DEV=1 (or set FOODPOS_JWT_SECRET)"
	go run ./cmd/server

seed:
	go run ./cmd/seed

clean:
	go clean
	-rm -f foodpos.db foodpos.db-wal foodpos.db-shm

.PHONY: verify run seed clean
