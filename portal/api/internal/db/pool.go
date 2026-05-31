package db

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Pool struct {
	pool *pgxpool.Pool
}

func Open(ctx context.Context, databaseURL string) (*Pool, error) {
	if databaseURL == "" {
		return &Pool{}, nil
	}
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, err
	}
	return &Pool{pool: pool}, nil
}

func (p *Pool) Ping(ctx context.Context) error {
	if p == nil || p.pool == nil {
		return errors.New("database is not configured")
	}
	return p.pool.Ping(ctx)
}

func (p *Pool) Close() {
	if p != nil && p.pool != nil {
		p.pool.Close()
	}
}

func (p *Pool) Raw() *pgxpool.Pool {
	if p == nil {
		return nil
	}
	return p.pool
}
