# Ứng dụng quản lý siêu thị mini bằng Flutter

Flutter + Node.js/Express + MySQL. Hive lưu cache trên thiết bị. Repo chứa source hiện tại và dữ liệu mẫu để cài trên máy khác; không chứa database đang dùng, `.env`, mật khẩu MySQL hoặc khóa thanh toán riêng của tác giả.

## 1. Chuẩn bị

| Công cụ | Yêu cầu |
| --- | --- |
| Git | Clone và cập nhật source |
| Flutter | Khuyến nghị **3.44.2 stable**, phiên bản trên máy tác giả; Dart đi kèm **3.12.2** |
| Node.js | Khuyến nghị **22.x**; máy tác giả dùng **22.15.1** |
| MySQL | **8.0 trở lên**; bật dịch vụ và nhớ mật khẩu quản trị |
| Android Studio | Android SDK, Android Emulator hoặc điện thoại Android |
| Xcode + CocoaPods | Chỉ cần cho iOS, chỉ chạy được trên macOS |

Tải công cụ: [Flutter](https://docs.flutter.dev/install), [Node.js](https://nodejs.org/en/download), [MySQL](https://dev.mysql.com/downloads/mysql/), [Git](https://git-scm.com/downloads), [Android Studio](https://developer.android.com/studio).

```bash
git --version
node --version
npm --version
mysql --version
flutter --version
flutter doctor
```

Xử lý các mục Android/iOS còn thiếu trong `flutter doctor`. Khi đã có Android SDK, chạy `flutter doctor --android-licenses`. Hướng dẫn demo chính dưới đây dành cho Android/iOS; các nền tảng khác cần kiểm tra tương thích package riêng.

## 2. Tải source

```bash
git clone https://github.com/Sangisme108/dalnn-.git
cd dalnn-
```

Mở **thư mục gốc `dalnn-`** bằng Android Studio hoặc VS Code, không chỉ mở `lib`. Cũng có thể chọn **Code > Download ZIP** trên GitHub và giải nén; bản ZIP không hỗ trợ `git pull`.

## 3. Tạo database trên máy mới

Bật MySQL. Từ **thư mục gốc `dalnn-`**, chạy trên macOS/Linux hoặc Windows Command Prompt:

```bash
mysql --default-character-set=utf8mb4 -h 127.0.0.1 -P 3306 -u root -p < backend_nodejs/database/setup.sql
```

Nhập mật khẩu MySQL của **máy bạn**. Thay `3306` và `root` nếu dùng cổng/tài khoản khác. User import cần quyền tạo database, bảng và sửa schema.

Nếu dùng **Windows PowerShell**:

```powershell
cmd /c "mysql --default-character-set=utf8mb4 -h 127.0.0.1 -P 3306 -u root -p < backend_nodejs/database/setup.sql"
```

`setup.sql` dùng lệnh `SOURCE` của MySQL CLI nên phải chạy từ thư mục gốc repo. File tạo `mini_supermarket`, import schema/dữ liệu mẫu rồi áp dụng các migration hiện có, gồm cột giờ nhận hàng. Dùng quy trình này cho **database demo mới**; migration có thể cập nhật dữ liệu nếu áp dụng vào database có sẵn. Không cần chạy `database_reset.sql` để cài lần đầu: file reset sẽ xóa dữ liệu.

Kiểm tra:

```bash
mysql -h 127.0.0.1 -P 3306 -u root -p mini_supermarket -e "SHOW TABLES; SHOW COLUMNS FROM orders LIKE 'pickup_time';"
```

Nếu `mysql` không được nhận diện, thêm thư mục `bin` của MySQL vào PATH hoặc dùng đường dẫn đầy đủ đến `mysql`/`mysql.exe`. Mẫu có sản phẩm, kho và tài khoản demo; lịch sử kinh doanh của tác giả không nằm trong repo. Tạo đơn mới trong app để kiểm tra báo cáo.

## 4. Cấu hình và chạy backend

Terminal thứ nhất, từ thư mục gốc repo:

```bash
cd backend_nodejs
npm ci
```

Tạo `.env` trên macOS/Linux:

```bash
cp .env.example .env
```

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Mở **`backend_nodejs/.env`**, điền cấu hình MySQL trên máy bạn:

```dotenv
PORT=3000
DB_HOST=127.0.0.1
DB_PORT=3306
DB_USER=root
DB_PASSWORD=mat_khau_mysql_cua_ban
DB_NAME=mini_supermarket
DB_SSL=false
JWT_SECRET=thay_bang_chuoi_ngau_nhien_rieng_cua_ban
JWT_EXPIRES_IN=7d
```

Mật khẩu chứa `#` hoặc khoảng trắng nên đặt trong dấu nháy kép. Tạo chuỗi JWT riêng bằng:

```bash
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

`DB_SSL=false` cho MySQL local. MySQL cloud cần TLS thì đặt `DB_SSL=true` và dùng host/port/user/password của dịch vụ. Backend nạp `.env` trong `backend_nodejs`, không dùng `.env.example` ở thư mục gốc.

Chạy và giữ terminal mở:

```bash
npm start
```

Mở [http://localhost:3000](http://localhost:3000) để kiểm tra API. Mở tiếp [http://localhost:3000/api/test-db](http://localhost:3000/api/test-db): phải trả `success: true` và danh sách vai trò để xác nhận kết nối MySQL. Thông báo server khởi động chưa đủ để xác nhận database hoạt động.

## 5. Chạy Flutter

Terminal thứ hai tại **thư mục gốc `dalnn-`**:

```bash
flutter pub get
flutter devices
```

Bật emulator hoặc kết nối điện thoại. Chọn địa chỉ API:

| Thiết bị | `API_BASE_URL` |
| --- | --- |
| Android Emulator của Android Studio | `http://10.0.2.2:3000` |
| iOS Simulator trên cùng Mac | `http://127.0.0.1:3000` |
| Android/iPhone thật | `http://IP_LAN_MAY_CHAY_BACKEND:3000` |

Android Emulator:

```bash
flutter run -d DEVICE_ID --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

iOS Simulator:

```bash
flutter run -d DEVICE_ID --dart-define=API_BASE_URL=http://127.0.0.1:3000
```

Thay `DEVICE_ID` bằng ID trong `flutter devices`, hoặc bỏ `-d DEVICE_ID` khi chỉ có một thiết bị. Luôn truyền `API_BASE_URL` để tránh IP mặc định của máy tác giả.

### Điện thoại thật

Máy chạy backend và điện thoại phải cùng Wi-Fi/LAN. Tìm IP máy tính bằng `ipconfig` trên Windows, hoặc Wi-Fi > Details > TCP/IP trên macOS. Ví dụ máy có IP `192.168.1.20`:

```bash
flutter run -d DEVICE_ID --dart-define=API_BASE_URL=http://192.168.1.20:3000
```

Trước tiên mở `http://192.168.1.20:3000/api/test-db` trong trình duyệt điện thoại. Nếu không được, kiểm tra IP, firewall/cổng 3000, VPN và mạng khách có chặn liên lạc giữa thiết bị hay không. `localhost` trên điện thoại là chính điện thoại, không phải máy tính.

### iOS trên macOS

Cài Xcode/CocoaPods và xử lý yêu cầu của `flutter doctor`. Sau `flutter pub get`, nếu cần cài Pods:

```bash
cd ios
pod install
cd ..
```

iPhone thật: mở `ios/Runner.xcworkspace` trong Xcode, chọn Team của bạn ở Signing & Capabilities, đổi Bundle Identifier nếu bị trùng và bật Developer Mode trên iPhone. Chạy Flutter với IP LAN như trên. Windows không build được iOS.

## 6. Tài khoản demo

Tài khoản được tạo khi import SQL vào **database mới**; mật khẩu đã đối chiếu với bcrypt hash trong source:

| Vai trò | Email | Mật khẩu demo |
| --- | --- | --- |
| Chủ siêu thị / admin | `a@gmail.com` | `123` |
| Nhân viên | `b@gmail.com` | `123` |
| Khách hàng | `c@gmail.com` | `123` |

Chỉ dùng tài khoản mẫu để demo local. Đổi mật khẩu trước khi đưa hệ thống lên Internet. `INSERT IGNORE` không đổi mật khẩu tài khoản cùng email trong database đã tồn tại.

## 7. Kiểm tra các chức năng

1. `/api/test-db` trả `success: true`.
2. Đăng nhập admin, xem sản phẩm/kho, thử nhập kho, đưa hàng lên kệ và kiểm kê.
3. Tạo đơn tại quầy, chọn tiền mặt, xác nhận thu tiền, xem lịch sử/doanh thu.
4. Đăng nhập khách hàng để đặt đơn online; dùng nhân viên xử lý đơn.
5. Quét mã bằng điện thoại có camera, cấp quyền Camera; mã phải tồn tại trong database. Có thể nhập mã thủ công để kiểm tra API.

## 8. Tích hợp cần cấu hình riêng

- **Email/SMS OTP:** điền SMTP/Twilio trong `.env`. Demo local có thể đặt `ALLOW_OTP_CONSOLE_FALLBACK=true` để đọc OTP ở terminal backend; gửi thật thì đặt `false`.
- **VNPay:** cần tài khoản sandbox, `VNP_TMN_CODE`, `VNP_HASH_SECRET` và URL callback/IPN public HTTPS trỏ tới backend. Chưa cấu hình thì chưa kiểm thử đầy đủ VNPay được.
- **Chuyển khoản:** thông tin QR trong `lib/utils/payment_config.dart`; tài khoản nhận tiền/webhook trong `.env`. Kiểm tra người nhận trước khi thử, không chuyển tiền thật chỉ để test giao diện.
- **Dữ liệu giống hệt máy tác giả:** cần bản export database và ảnh upload tương ứng được chia sẻ riêng sau khi loại dữ liệu nhạy cảm. SQL mẫu không sao chép lịch sử kinh doanh đang dùng.

## 9. Lỗi thường gặp

| Lỗi | Cách xử lý |
| --- | --- |
| Không kết nối backend | Backend phải đang chạy; kiểm tra `API_BASE_URL`, Wi-Fi và firewall |
| `Access denied for user` | Kiểm tra user/password MySQL trong `.env`, rồi khởi động lại backend |
| MySQL `ECONNREFUSED` | Bật MySQL, dùng đúng cổng; local thường là 3306 |
| Server không hỗ trợ SSL | MySQL local: `DB_SSL=false`, khởi động lại backend |
| Thiếu database/bảng/`pickup_time` | Import `setup.sql` từ thư mục gốc và đọc lỗi import |
| Cổng 3000 đang được dùng | Dừng server trùng hoặc đổi `PORT` và `API_BASE_URL` theo cùng cổng |
| Có sản phẩm nhưng không đăng nhập được | Sản phẩm có thể từ cache; kiểm tra `/api/test-db` và tài khoản MySQL |
| iPhone không build được | Kiểm tra Xcode, Pods, Team signing, Developer Mode |
| Camera không mở | Cấp quyền trong cài đặt thiết bị; thử mã thủ công |

## 10. Cập nhật và cấu trúc

Bản clone bằng Git, từ thư mục gốc:

```bash
git pull --ff-only origin main
flutter pub get
cd backend_nodejs
npm ci
```

Có thay đổi local thì commit hoặc stash trước khi pull. Khi cập nhật schema, sao lưu database rồi áp dụng migration mới phù hợp; không reset database đang dùng.

```text
lib/                           Giao diện, model và service Flutter
assets/                        Ảnh và dữ liệu địa chỉ
backend_nodejs/src/            REST API và nghiệp vụ
backend_nodejs/uploads/        Ảnh sản phẩm upload
backend_nodejs/.env.example    Mẫu cấu hình backend
backend_nodejs/database/       Setup, migrations và seed
database.sql                   Schema và dữ liệu mẫu
android/ và ios/               Cấu hình điện thoại
test/                          Kiểm thử Flutter hiện có
```

`node_modules`, build, Pods và `.env` được cài/tạo trên từng máy, không đưa lên GitHub. Chạy `flutter test` để kiểm tra Flutter. Trong `backend_nodejs`, `npm run test:vnpay` chỉ kiểm tra ký VNPay offline, không xác nhận thanh toán thật.
