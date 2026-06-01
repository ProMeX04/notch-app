package payments

import (
	"net/url"
	"strings"
	"testing"
)

func TestCreateVNPayPayment(t *testing.T) {
	cfg := VNPayConfig{
		TmnCode:    "NOTCH001",
		HashSecret: "SECRET123",
		PaymentURL: "https://sandbox.vnpayment.vn/paymentv2/vpcpay.html",
		Amount:     99000,
	}

	args := CreatePaymentArgs{
		TxnRef:    "notchpro_test_123",
		OrderInfo: "Notch Pro Upgrade",
		ReturnURL: "http://localhost:5173/billing/vnpay/return",
		IPAddr:    "127.0.0.1",
	}

	result, err := CreateVNPayPayment(args, cfg)
	if err != nil {
		t.Fatalf("CreateVNPayPayment failed: %v", err)
	}

	if result.OrderID != args.TxnRef {
		t.Errorf("OrderID = %q, want %q", result.OrderID, args.TxnRef)
	}

	if !strings.HasPrefix(result.PaymentURL, cfg.PaymentURL) {
		t.Errorf("PaymentURL = %q, does not start with %q", result.PaymentURL, cfg.PaymentURL)
	}

	parsed, err := url.Parse(result.PaymentURL)
	if err != nil {
		t.Fatalf("Failed to parse output URL: %v", err)
	}

	q := parsed.Query()
	if q.Get("vnp_TmnCode") != cfg.TmnCode {
		t.Errorf("vnp_TmnCode = %q, want %q", q.Get("vnp_TmnCode"), cfg.TmnCode)
	}
	if q.Get("vnp_Amount") != "9900000" { // 99000 * 100
		t.Errorf("vnp_Amount = %q, want %q", q.Get("vnp_Amount"), "9900000")
	}
	if q.Get("vnp_SecureHash") == "" {
		t.Error("vnp_SecureHash is missing in checkout URL")
	}
}

func TestVerifyVNPayPayload(t *testing.T) {
	hashSecret := "MY_SECRET_KEY"

	// Mock valid payload values (simulated output from CreateVNPayPayment)
	params := url.Values{}
	params.Set("vnp_Version", "2.1.0")
	params.Set("vnp_Command", "pay")
	params.Set("vnp_TmnCode", "NOTCH001")
	params.Set("vnp_Amount", "9900000")
	params.Set("vnp_TxnRef", "tx_12345")
	params.Set("vnp_OrderInfo", "Upgrade")
	params.Set("vnp_ResponseCode", "00")
	params.Set("vnp_TransactionStatus", "00")

	// Sign the mock payload
	cfg := VNPayConfig{
		TmnCode:    "NOTCH001",
		HashSecret: hashSecret,
		PaymentURL: "https://vnpay.vn",
		Amount:     99000,
	}
	paymentResult, err := CreateVNPayPayment(CreatePaymentArgs{
		TxnRef:    "tx_12345",
		OrderInfo: "Upgrade",
		IPAddr:    "127.0.0.1",
		ReturnURL: "http://localhost:5173",
	}, cfg)
	if err != nil {
		t.Fatalf("failed to create signature: %v", err)
	}
	u, _ := url.Parse(paymentResult.PaymentURL)
	validParams := u.Query()

	// Verify valid signature
	if !VerifyVNPayPayload(validParams, hashSecret) {
		t.Error("VerifyVNPayPayload failed to verify a valid signature")
	}

	// Verify uppercase signature matching
	uppercaseParams := url.Values{}
	for k, v := range validParams {
		if k == "vnp_SecureHash" {
			uppercaseParams[k] = []string{strings.ToUpper(v[0])}
		} else {
			uppercaseParams[k] = v
		}
	}
	if !VerifyVNPayPayload(uppercaseParams, hashSecret) {
		t.Error("VerifyVNPayPayload failed to verify an uppercase signature")
	}

	// Verify rejection of invalid signature
	invalidParams := url.Values{}
	for k, v := range validParams {
		invalidParams[k] = v
	}
	invalidParams.Set("vnp_SecureHash", "invalid_hash_value")
	if VerifyVNPayPayload(invalidParams, hashSecret) {
		t.Error("VerifyVNPayPayload verified an invalid signature")
	}

	// Verify mismatched length
	shortHashParams := url.Values{}
	for k, v := range validParams {
		shortHashParams[k] = v
	}
	shortHashParams.Set("vnp_SecureHash", "too_short")
	if VerifyVNPayPayload(shortHashParams, hashSecret) {
		t.Error("VerifyVNPayPayload verified a short mismatched hash")
	}
}
