package payments

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"notch/portal/api/internal/auth"
	"notch/portal/api/internal/config"
	"notch/portal/api/internal/db"
	"notch/portal/api/internal/events"
	"notch/portal/api/internal/httpjson"
)

type Handler struct {
	Config        config.PaymentConfig
	FrontendURL   string
	DB            *db.Pool
	Authenticator auth.Authenticator
	EventLog      *events.Logger
}

func NewHandler(cfg config.PaymentConfig, frontendURL string, dbPool *db.Pool, authenticator auth.Authenticator, eventLog *events.Logger) *Handler {
	return &Handler{
		Config:        cfg,
		FrontendURL:   frontendURL,
		DB:            dbPool,
		Authenticator: authenticator,
		EventLog:      eventLog,
	}
}

func (h *Handler) Create(w http.ResponseWriter, req *http.Request) {
	authCtx, err := h.Authenticator.AuthenticateRequest(req.Context(), req)
	if err != nil {
		h.logEvent(req, "payment.vnpay_create_rejected", "rejected", "web", nil, nil, nil, http.StatusUnauthorized, map[string]any{
			"reason": "invalid_session",
		})
		httpjson.Detail(w, http.StatusUnauthorized, "Invalid or expired session token.")
		return
	}

	ipAddress := req.Header.Get("X-Forwarded-For")
	if ipAddress == "" {
		ipAddress = req.RemoteAddr
	}
	if idx := strings.Index(ipAddress, ":"); idx != -1 {
		ipAddress = ipAddress[:idx]
	}
	ipAddress = strings.TrimSpace(strings.Split(ipAddress, ",")[0])
	if ipAddress == "" {
		ipAddress = "127.0.0.1"
	}

	orderId := fmt.Sprintf("notchpro_%d_%s", time.Now().UnixNano(), generateRandomString(8))
	orderInfo := "Notch Pro upgrade via VNPAY"
	returnUrl := fmt.Sprintf("%s/billing/vnpay/return", strings.TrimSuffix(h.FrontendURL, "/"))

	payment, err := CreateVNPayPayment(CreatePaymentArgs{
		TxnRef:    orderId,
		OrderInfo: orderInfo,
		ReturnURL: returnUrl,
		IPAddr:    ipAddress,
	}, VNPayConfig{
		TmnCode:    h.Config.VNPayTMNCode,
		HashSecret: h.Config.VNPayHashSecret,
		PaymentURL: h.Config.VNPayPaymentURL,
		Amount:     h.Config.VNPayProAmount,
	})

	if err != nil {
		h.logEvent(req, "payment.vnpay_create_failed", "failure", "web", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusInternalServerError, map[string]any{
			"error": err.Error(),
		})
		httpjson.Detail(w, http.StatusInternalServerError, err.Error())
		return
	}

	rawResponse, _ := json.Marshal(map[string]string{"paymentUrl": payment.PaymentURL})
	txID := generateRandomString(24)

	_, err = h.DB.Raw().Exec(req.Context(), `
		INSERT INTO "PaymentTransaction" (
			"id", "provider", "status", "amount", "currency", "orderId", "requestId",
			"payUrl", "orderInfo", "rawResponse", "createdAt", "updatedAt", "userId"
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NOW(), $11
		)
	`, txID, "vnpay", "pending", h.Config.VNPayProAmount, "VND", payment.OrderID, payment.OrderID, payment.PaymentURL, orderInfo, string(rawResponse), authCtx.User.ID)

	if err != nil {
		h.logEvent(req, "payment.vnpay_create_failed", "failure", "web", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusInternalServerError, map[string]any{
			"error": err.Error(),
		})
		httpjson.Detail(w, http.StatusInternalServerError, "Failed to persist transaction")
		return
	}

	h.logEvent(req, "payment.vnpay_create_succeeded", "success", "web", &authCtx.User.ID, &authCtx.SessionID, authCtx.DeviceID, http.StatusOK, map[string]any{
		"orderId":     payment.OrderID,
		"amount":      h.Config.VNPayProAmount,
		"currency":    "VND",
		"actorUserId": authCtx.User.ID,
	})

	httpjson.JSON(w, http.StatusOK, map[string]string{
		"pay_url":  payment.PaymentURL,
		"order_id": payment.OrderID,
	})
}

func (h *Handler) CreateGuest(w http.ResponseWriter, req *http.Request) {
	h.logEvent(req, "payment.vnpay_create_guest_rejected", "rejected", "web", nil, nil, nil, http.StatusForbidden, map[string]any{
		"reason": "login_required",
	})
	httpjson.Detail(w, http.StatusForbidden, "Vui lòng đăng nhập hoặc tạo tài khoản trước khi nâng cấp Pro.")
}

func (h *Handler) IPN(w http.ResponseWriter, req *http.Request) {
	params := req.URL.Query()

	if !VerifyVNPayPayload(params, h.Config.VNPayHashSecret) {
		h.logEvent(req, "payment.vnpay_ipn_rejected", "rejected", "payment_webhook", nil, nil, nil, http.StatusOK, map[string]any{
			"reason": "invalid_signature",
		})
		httpjson.JSON(w, http.StatusOK, map[string]string{
			"RspCode": "97",
			"Message": "Invalid signature",
		})
		return
	}

	result, err := ProcessVNPayResult(req.Context(), WrapPool(h.DB.Raw()), params)
	if err != nil {
		h.logEvent(req, "payment.vnpay_ipn_failed", "failure", "payment_webhook", nil, nil, nil, http.StatusInternalServerError, map[string]any{
			"error": err.Error(),
		})
		httpjson.JSON(w, http.StatusOK, map[string]string{
			"RspCode": "99",
			"Message": "Internal Error",
		})
		return
	}

	outcome := "failure"
	if result.OK {
		outcome = "success"
	}
	eventType := "payment.vnpay_ipn_processed"
	if result.Success {
		eventType = "payment.vnpay_ipn_paid"
	}

	h.logEvent(req, eventType, outcome, "payment_webhook", nil, nil, nil, http.StatusOK, map[string]any{
		"rspCode":           result.Code,
		"success":           result.Success,
		"orderId":           params.Get("vnp_TxnRef"),
		"responseCode":      params.Get("vnp_ResponseCode"),
		"transactionStatus": params.Get("vnp_TransactionStatus"),
	})

	httpjson.JSON(w, http.StatusOK, map[string]string{
		"RspCode": result.Code,
		"Message": result.Message,
	})
}

func (h *Handler) Return(w http.ResponseWriter, req *http.Request) {
	params := req.URL.Query()

	verified := VerifyVNPayPayload(params, h.Config.VNPayHashSecret)
	var success bool
	var needsSignup bool

	if verified {
		result, err := ProcessVNPayResult(req.Context(), WrapPool(h.DB.Raw()), params)
		if err == nil {
			success = result.Success

			orderID := params.Get("vnp_TxnRef")
			var hasUser bool
			var hasGuest bool
			err = h.DB.Raw().QueryRow(req.Context(), `
				SELECT "userId" IS NOT NULL, "guestEmail" IS NOT NULL
				FROM "PaymentTransaction"
				WHERE "orderId" = $1
			`, orderID).Scan(&hasUser, &hasGuest)
			if err == nil {
				needsSignup = !hasUser && hasGuest
			}
		}
	}

	httpjson.JSON(w, http.StatusOK, map[string]any{
		"verified":     verified,
		"success":      success,
		"needs_signup": needsSignup,
	})
}

func (h *Handler) logEvent(req *http.Request, eventType, outcome, source string, actorUserID, sessionID, deviceID *string, statusCode int, metadata map[string]any) {
	if h.EventLog == nil {
		return
	}
	h.EventLog.Log(req.Context(), req, events.Event{
		EventType:   eventType,
		Outcome:     outcome,
		Source:      source,
		ActorUserID: actorUserID,
		SessionID:   sessionID,
		DeviceID:    deviceID,
		StatusCode:  &statusCode,
		Metadata:    metadata,
	})
}

func generateRandomString(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	const letters = "abcdefghijklmnopqrstuvwxyz0123456789"
	var sb strings.Builder
	for _, bVal := range b {
		sb.WriteByte(letters[int(bVal)%len(letters)])
	}
	return sb.String()
}
