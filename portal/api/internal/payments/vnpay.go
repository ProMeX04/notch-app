package payments

import (
	"context"
	"crypto/hmac"
	"crypto/sha512"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type VNPayConfig struct {
	TmnCode    string
	HashSecret string
	PaymentURL string
	Amount     int
}

type CreatePaymentArgs struct {
	TxnRef    string
	OrderInfo string
	ReturnURL string
	IPAddr    string
}

type CreatePaymentResult struct {
	PaymentURL string
	OrderID    string
}

type ProcessResult struct {
	OK      bool
	Code    string
	Message string
	Success bool
}

// CreateVNPayPayment generates a signed VNPay payment URL.
func CreateVNPayPayment(args CreatePaymentArgs, cfg VNPayConfig) (CreatePaymentResult, error) {
	if cfg.TmnCode == "" || cfg.HashSecret == "" || cfg.PaymentURL == "" {
		return CreatePaymentResult{}, errors.New("VNPAY is not configured on the server")
	}

	createDate := time.Now().Format("20060102150405")
	amountStr := strconv.Itoa(cfg.Amount * 100)

	params := url.Values{}
	params.Set("vnp_Version", "2.1.0")
	params.Set("vnp_Command", "pay")
	params.Set("vnp_TmnCode", cfg.TmnCode)
	params.Set("vnp_Amount", amountStr)
	params.Set("vnp_CurrCode", "VND")
	params.Set("vnp_TxnRef", args.TxnRef)
	params.Set("vnp_OrderInfo", args.OrderInfo)
	params.Set("vnp_OrderType", "other")
	params.Set("vnp_Locale", "vn")
	params.Set("vnp_ReturnUrl", args.ReturnURL)
	params.Set("vnp_IpAddr", args.IPAddr)
	params.Set("vnp_CreateDate", createDate)

	// Sort keys
	var keys []string
	for k := range params {
		keys = append(keys, k)
	}
	sort.Strings(keys)

	// Build query string matching URLSearchParams in Next.js.
	// URLSearchParams.toString() encodes spaces as "+" which is standard query string format.
	var queryParts []string
	for _, k := range keys {
		val := params.Get(k)
		if val != "" {
			queryParts = append(queryParts, url.QueryEscape(k)+"="+url.QueryEscape(val))
		}
	}
	signData := strings.Join(queryParts, "&")

	// Calculate secure hash
	mac := hmac.New(sha512.New, []byte(cfg.HashSecret))
	mac.Write([]byte(signData))
	secureHash := hex.EncodeToString(mac.Sum(nil))

	params.Set("vnp_SecureHash", secureHash)

	// Construct payment URL
	var finalParts []string
	for _, k := range keys {
		val := params.Get(k)
		if val != "" {
			finalParts = append(finalParts, url.QueryEscape(k)+"="+url.QueryEscape(val))
		}
	}
	finalParts = append(finalParts, "vnp_SecureHash="+url.QueryEscape(secureHash))

	paymentUrl := fmt.Sprintf("%s?%s", cfg.PaymentURL, strings.Join(finalParts, "&"))

	return CreatePaymentResult{
		PaymentURL: paymentUrl,
		OrderID:    args.TxnRef,
	}, nil
}

// VerifyVNPayPayload verifies the signature of a VNPay callback request in a timing-safe manner.
func VerifyVNPayPayload(params url.Values, hashSecret string) bool {
	if hashSecret == "" {
		return false
	}

	provided := strings.TrimSpace(params.Get("vnp_SecureHash"))
	if provided == "" {
		return false
	}

	// Filter out non-vnp parameters or signature parameters
	var keys []string
	for k := range params {
		if strings.HasPrefix(k, "vnp_") && k != "vnp_SecureHash" && k != "vnp_SecureHashType" {
			keys = append(keys, k)
		}
	}
	sort.Strings(keys)

	var queryParts []string
	for _, k := range keys {
		val := params.Get(k)
		if val != "" {
			queryParts = append(queryParts, url.QueryEscape(k)+"="+url.QueryEscape(val))
		}
	}
	signData := strings.Join(queryParts, "&")

	mac := hmac.New(sha512.New, []byte(hashSecret))
	mac.Write([]byte(signData))
	expected := hex.EncodeToString(mac.Sum(nil))

	a := []byte(provided)
	b := []byte(expected)
	if len(a) != len(b) {
		return false
	}

	return subtle.ConstantTimeCompare(a, b) == 1
}

// ProcessVNPayResult handles the transactional processing of the webhook callback.
func ProcessVNPayResult(ctx context.Context, dbPool dbPoolWrapper, params url.Values) (ProcessResult, error) {
	orderID := params.Get("vnp_TxnRef")
	responseCode := params.Get("vnp_ResponseCode")
	transactionStatus := params.Get("vnp_TransactionStatus")
	amountRaw := params.Get("vnp_Amount")

	var amountCent int
	if amountRaw != "" {
		if val, err := strconv.Atoi(amountRaw); err == nil {
			amountCent = val
		}
	}
	amount := amountCent / 100

	tx, err := dbPool.Begin(ctx)
	if err != nil {
		return ProcessResult{}, err
	}
	defer tx.Rollback(ctx)

	// Fetch transaction
	var txID string
	var txAmount int
	var txStatus string
	var txUserID *string
	var guestEmail *string

	err = tx.QueryRow(ctx, `
		SELECT "id", "amount", "status", "userId", "guestEmail"
		FROM "PaymentTransaction"
		WHERE "orderId" = $1
	`, orderID).Scan(&txID, &txAmount, &txStatus, &txUserID, &guestEmail)

	if err == pgx.ErrNoRows {
		return ProcessResult{OK: false, Code: "01", Message: "Order not found"}, nil
	} else if err != nil {
		return ProcessResult{}, err
	}

	if txAmount != amount {
		return ProcessResult{OK: false, Code: "04", Message: "Invalid amount"}, nil
	}

	if txStatus == "paid" {
		return ProcessResult{OK: true, Code: "02", Message: "Order already confirmed", Success: true}, nil
	}

	isSuccess := responseCode == "00" && transactionStatus == "00"

	// Marshal notifications params as json
	notificationMap := make(map[string]string)
	for k := range params {
		notificationMap[k] = params.Get(k)
	}
	notificationJSON, err := json.Marshal(notificationMap)
	if err != nil {
		return ProcessResult{}, err
	}

	status := "failed"
	if isSuccess {
		status = "paid"
	}

	var paidAt *time.Time
	if isSuccess {
		now := time.Now()
		paidAt = &now
	}

	providerRef := params.Get("vnp_TransactionNo")
	var providerRefPtr *string
	if providerRef != "" {
		providerRefPtr = &providerRef
	}

	_, err = tx.Exec(ctx, `
		UPDATE "PaymentTransaction"
		SET "status" = $1, "providerRef" = $2, "paidAt" = $3, "rawNotification" = $4, "updatedAt" = NOW()
		WHERE "id" = $5
	`, status, providerRefPtr, paidAt, notificationJSON, txID)
	if err != nil {
		return ProcessResult{}, err
	}

	if isSuccess {
		if txUserID != nil {
			_, err = tx.Exec(ctx, `
				UPDATE "User"
				SET "isPro" = true, "updatedAt" = NOW()
				WHERE "id" = $1
			`, *txUserID)
			if err != nil {
				return ProcessResult{}, err
			}
		} else if guestEmail != nil {
			// Check if guest has registered in the system
			var existingUserID string
			err = tx.QueryRow(ctx, `
				SELECT "id"
				FROM "User"
				WHERE LOWER("email") = LOWER($1)
			`, *guestEmail).Scan(&existingUserID)

			if err == nil {
				// Transition transaction and upgrade user
				_, err = tx.Exec(ctx, `
					UPDATE "PaymentTransaction"
					SET "userId" = $1, "updatedAt" = NOW()
					WHERE "id" = $2
				`, existingUserID, txID)
				if err != nil {
					return ProcessResult{}, err
				}

				_, err = tx.Exec(ctx, `
					UPDATE "User"
					SET "isPro" = true, "updatedAt" = NOW()
					WHERE "id" = $1
				`, existingUserID)
				if err != nil {
					return ProcessResult{}, err
				}
			} else if err != pgx.ErrNoRows {
				return ProcessResult{}, err
			}
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return ProcessResult{}, err
	}

	message := "Payment Failed"
	if isSuccess {
		message = "Confirm Success"
	}

	return ProcessResult{
		OK:      true,
		Code:    "00",
		Message: message,
		Success: isSuccess,
	}, nil
}

// dbPoolWrapper bridges pgxpool.Pool interface so we can mock/run database calls
type dbPoolWrapper interface {
	Begin(ctx context.Context) (pgx.Tx, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

type RealDbPool struct {
	Pool *pgxpool.Pool
}

func (r *RealDbPool) Begin(ctx context.Context) (pgx.Tx, error) {
	return r.Pool.Begin(ctx)
}

func (r *RealDbPool) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	return r.Pool.QueryRow(ctx, sql, args...)
}

// WrapPool is a helper to wrap pgxpool
func WrapPool(pool *pgxpool.Pool) dbPoolWrapper {
	return &poolWrapper{pool: pool}
}

type poolWrapper struct {
	pool *pgxpool.Pool
}

func (pw *poolWrapper) Begin(ctx context.Context) (pgx.Tx, error) {
	return pw.pool.Begin(ctx)
}

func (pw *poolWrapper) QueryRow(ctx context.Context, sql string, args ...any) pgx.Row {
	return pw.pool.QueryRow(ctx, sql, args...)
}
