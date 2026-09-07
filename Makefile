verify:
	go vet ./...
	go test ./...
	go build ./...

run:
	go run ./cmd/server

run-seed:
	FOODPOS_SEED=1 go run ./cmd/server

clean:
	go clean
	-rm -f foodpos.db foodpos.db-wal foodpos.db-shm

.PHONY: verify run run-seed clean
