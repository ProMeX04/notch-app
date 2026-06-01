# Hướng dẫn deploy Portal LÊN CÁC NỀN TẢNG MIỄN PHÍ (100% FREE)

Hướng dẫn này chỉ ra các nền tảng đám mây tốt nhất hiện nay cho phép bạn deploy cả Frontend Vite React và Go API hoàn toàn miễn phí mà không cần trả phí hàng tháng.

---

## 1. Triển khai Frontend (Vite + React) lên Vercel (MIỄN PHÍ)

Vercel cung cấp gói **Hobby Tier** miễn phí trọn đời cho các trang web tĩnh và ứng dụng Single Page Application (Vite).

### Các bước thực hiện:
1. Truy cập [Vercel](https://vercel.com) và đăng nhập bằng tài khoản GitHub của bạn.
2. Click **Add New** > **Project**.
3. Chọn repository dự án này.
4. Cấu hình dự án (Project Configuration):
   - **Framework Preset**: Chọn **Vite**.
   - **Root Directory**: Nhập `portal/web`.
   - **Build Command**: `npm run build`
   - **Output Directory**: `dist`
5. Thêm biến môi trường (Environment Variables) trong tab **Environment Variables**:
   - Tên biến: `VITE_PORTAL_API_URL`
   - Giá trị: URL Go backend của bạn (ví dụ: `https://notch-api.koyeb.app` hoặc `https://notch-api.onrender.com`).
6. Click **Deploy**.

*Lưu ý:* Vercel đã tự động nhận diện file [vercel.json](file:///Users/promex04/Documents/NO/notch-app/portal/web/vercel.json) mà chúng ta đã cấu hình để xử lý SPA routing không bị lỗi 404 khi F5.

---

## 2. Triển khai Go Backend API MIỄN PHÍ

Đối với Go backend, bạn có hai lựa chọn miễn phí tốt nhất hiện nay: **Koyeb** và **Render**.

### Lựa chọn A: Koyeb (Khuyên dùng - KHÔNG BỊ NGỦ ĐÔNG)
Koyeb cung cấp 1 Nano Instance (512MB RAM, 0.1 vCPU) miễn phí trọn đời. Điểm cộng lớn nhất của Koyeb so với Render là **ứng dụng chạy liên tục 24/7 và không bị ngủ đông** (không bị delay lần gọi đầu tiên).

#### Các bước triển khai:
1. Đăng ký tài khoản miễn phí tại [Koyeb](https://www.koyeb.com).
2. Chọn **Create App** > **GitHub**.
3. Chọn repository của bạn.
4. Ở phần cấu hình dịch vụ (Service configuration):
   - **Builder**: Chọn **Dockerfile** (Koyeb sẽ tự động đọc file `portal/api/Dockerfile` để build).
   - **Root Directory**: Nhập `portal/api`.
5. Thêm các biến môi trường (Environment Variables):
   - `DATABASE_URL`: URL PostgreSQL (ví dụ Supabase connection string).
   - `JWT_SECRET`: Chuỗi khóa ngẫu nhiên bảo mật JWT.
   - `GOOGLE_DRIVE_HANDOFF_ENCRYPTION_KEY`: Chuỗi mã hóa Drive (Base64 32-byte).
   - `FRONTEND_URL`: URL trang web Vercel vừa deploy ở Mục 1.
   - `PORTAL_DEV_ORIGINS`: Địa chỉ trang web Vercel (để CORS cho phép gọi API).
   - `PORT`: `3000` (được Koyeb map tự động).
6. Ở mục **Exposed Ports**: Đảm bảo cấu hình Port `3000` (Protocol: HTTP, Path: `/`).
7. Click **Deploy**.

---

### Lựa chọn B: Render (Miễn phí - Có ngủ đông)
Render cung cấp gói **Free Web Services** nhưng nếu không có request trong vòng 15 phút, app sẽ tạm thời "ngủ đông". Khi có request mới, Render sẽ mất khoảng 30-50 giây để khởi động lại dịch vụ.

#### Các bước triển khai:
1. Đăng ký tài khoản tại [Render](https://render.com).
2. Click **New +** > **Web Service**.
3. Kết nối với repo GitHub của bạn.
4. Cấu hình dịch vụ:
   - **Name**: `notch-portal-api`
   - **Runtime**: Chọn **Docker** (Render sẽ tự động dùng file `portal/api/Dockerfile`).
   - **Root Directory**: Nhập `portal/api`.
   - **Instance Type**: Chọn **Free** ($0/month).
5. Click **Advanced** để thêm các biến môi trường (Environment Variables) tương tự như bên Koyeb:
   - `DATABASE_URL`, `JWT_SECRET`, `GOOGLE_DRIVE_HANDOFF_ENCRYPTION_KEY`, `FRONTEND_URL`, `PORTAL_DEV_ORIGINS`.
6. Click **Create Web Service**.

---

## 3. Tổng kết các thông tin cần chuẩn bị

Để deploy thành công cả 2 phần, hãy điền chéo các URL của nhau:

| Dịch vụ | Biến môi trường cần điền | Ý nghĩa |
|---|---|---|
| **Vercel (Vite)** | `VITE_PORTAL_API_URL` | Điền URL API của Koyeb hoặc Render (ví dụ: `https://[app-name].koyeb.app`) |
| **Go API (Koyeb/Render)** | `FRONTEND_URL` | Điền URL web của Vercel (ví dụ: `https://[project].vercel.app`) |
| **Go API (Koyeb/Render)** | `PORTAL_DEV_ORIGINS` | Điền URL web của Vercel (phục vụ CORS API) |
| **Go API (Koyeb/Render)** | `DATABASE_URL` | Điền PostgreSQL Connection String |
