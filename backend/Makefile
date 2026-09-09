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
	go run ./cmd/server

run-seed:
	FOODPOS_SEED=1 go run ./cmd/server

clean:
	go clean
	-rm -f foodpos.db foodpos.db-wal foodpos.db-shm

.PHONY: verify run run-seed clean
