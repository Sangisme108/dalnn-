# Chẩn đoán đăng nhập Owner — 06/11/2026

## Lỗi code đã tái hiện và sửa

Sau bản sửa JWT, `ApiService.login` thêm bước xóa phiên/cache của tài khoản cũ trước khi lưu JWT mới. Mục đích cô lập tài khoản là đúng, nhưng `DBService.clearPrivateCache` dùng `Hive.box(name)` mặc định dynamic cho các box đã mở bằng kiểu cụ thể.

Test chạy với cùng kiểu box như `DBService.init` cho kết quả:

```text
Backend response: HTTP 200, user và token hợp lệ (fixture)
HiveError: The box "users" is already open and of type Box<User>.
DBService.clearPrivateCache → clearAuthSession → ApiService.login
```

`PasswordLoginScreen` bắt lỗi này, gọi `connectionErrorMessage`, và hàm đó mặc định trả “Email hoặc mật khẩu không đúng” cho mọi lỗi không giống lỗi mạng. Vì vậy xác thực thành công vẫn bị báo sai mật khẩu ở client. Đây là regression ở phần xóa cache của bản sửa JWT, không phải kết luận rằng người dùng nhập sai mật khẩu.

Đã sửa:

- Mỗi box được xóa bằng đúng kiểu `User`, `Order`, `InventoryItem`, `InventoryHistoryEntry`; cart và cache ca làm vẫn dùng dynamic đúng với nơi mở box.
- Giữ việc xóa cache riêng tư khi đổi tài khoản, không bỏ cô lập phiên để tránh lỗi.
- Kiểm tra cấu trúc response đăng nhập trước khi truy cập `user`/token. Response sai không bị TypeError rồi gán nhầm thành lỗi mật khẩu.
- Nếu server đã xác thực nhưng không lưu được phiên, báo rõ lỗi lưu phiên trên thiết bị. Lỗi không xác định không tự quy thành sai mật khẩu.
- Không tự trim mật khẩu khi gửi; giữ nguyên ký tự khách nhập. Identifier vẫn trim như trước. Chặn gọi submit lặp trong lúc đang xử lý.

## Đối chiếu code trước/sau JWT

Đã đọc bản commit `645d15d`, `f58cd97` và source hiện tại:

- Backend login đều tìm tài khoản active, ưu tiên `password_hash` rồi mới dùng `password` khi trường hash rỗng; cùng hàm kiểm tra bcrypt/plaintext legacy. Không có thay đổi làm bcrypt `$2b$` mất tương thích.
- Trước JWT, Flutter lưu token trực tiếp nếu có. Sau JWT, bắt buộc có token và gọi `clearAuthSession()` trước khi lưu; chính bước cache mới gây exception.
- Không sửa thứ tự ưu tiên cột mật khẩu, không thử mật khẩu cũ ở cột phụ nếu cột hash không khớp, không nới lỏng JWT hoặc bỏ xác thực.

## Đã kiểm tra trên TiDB và backend đang chạy

Chỉ đọc, không in email/định danh/hash/mật khẩu/JWT:

| Kiểm tra | Kết quả |
|---|---|
| Database được chọn so với DB_NAME đã cấu hình | Khớp |
| Engine thực tế | TiDB |
| Cấu hình kết nối TLS | Được bật |
| Tài khoản Owner | Một tài khoản, đang active |
| Identifier của Owner qua đúng truy vấn login | Tìm thấy đúng bản ghi |
| Hai trường password và password_hash | Cùng bcrypt `$2b$`, giá trị đồng nhất, không có khoảng trắng thừa |
| JWT_SECRET | Có cấu hình; không in giá trị |
| GET profile qua backend đang nghe cổng 3000 | HTTP 200, khớp bản ghi Owner đọc từ cấu hình DB; token tạm chỉ trong bộ nhớ |
| POST login với mật khẩu ngẫu nhiên không phải mật khẩu người dùng | HTTP 401, không trả token; digest so sánh nội bộ xác nhận hai trường mật khẩu không đổi |

Đã xác nhận tiến trình cổng 3000 chạy từ đúng thư mục backend dự án. Không đổi `.env`, schema, trạng thái người dùng hoặc mật khẩu.

**Không biết và không thử mật khẩu thật của bạn**, nên không khẳng định mật khẩu đó đúng/sai. Kiểm tra 401 ở trên là negative test cố ý, không phải thất bại của mật khẩu cũ. Kiểm tra HTTP200 và chuyển màn hình được thực hiện bằng fixture tài khoản/API giả trong test, không tạo tài khoản hoặc reset trên TiDB.

## Kiểm thử

- **168 test Flutter đạt**, gồm 5 test đăng nhập mới: HTTP200 với typed cache, HTTP401/500, response200 sai cấu trúc, lỗi local không bị gán sai mật khẩu, màn hình Owner đăng nhập/sync/lưu phiên/chuyển vào ứng dụng và giữ nguyên khoảng trắng mật khẩu.
- Test backend synthetic: bcrypt 2a/2b, legacy comparison, 200/401, ưu tiên hash chính, JWT access purpose, không lộ hash trong DTO và không ghi mật khẩu trong các ca bcrypt. Chạy source route/service thật với pool giả, không gửi email/SMS.
- **350 kiểm tra HTTP JWT qua 108 route/alias đạt**.
- Analyze 4 file Flutter liên quan: không error/warning; còn 9 info cũ về dấu ngoặc và print. Exit code của analyze vẫn là 1 vì các info, không coi là kết quả lint sạch.

Trước sửa, bộ test tái hiện lỗi Hive sau HTTP200, TypeError khi response sai và thông báo mật khẩu sai cho lỗi local. Sau sửa, cả 5 test và toàn bộ hồi quy đều đạt.

## File thay đổi

- `../lib/services/db_service.dart`: clear private cache đúng kiểu Hive.
- `../lib/services/api_service.dart`: kiểm tra response, tách lỗi lưu phiên và bỏ thông báo sai mật khẩu cho lỗi chung.
- `../lib/screens/password_login_screen.dart`: giữ nguyên mật khẩu và chặn submit lặp.
- `../test/login_regression_test.dart`: 5 test Flutter/API/widget.
- `scripts/test-login-auth.js`: kiểm thử backend dữ liệu giả.
- `LOGIN_DIAGNOSIS.md`: báo cáo này.

Không sửa auth route/service trên backend hoặc các nghiệp vụ P1/P2. Không cần restart backend cho bản sửa client này.

## Kiểm tra lại và khôi phục an toàn nếu vẫn lỗi

1. **Hot Restart Flutter**, mở lại màn hình đăng nhập Owner và nhập tài khoản/mật khẩu cũ ngay trong ứng dụng. Không gửi mật khẩu qua chat. Không cần xóa dữ liệu app, gỡ app hoặc reset database.
2. Nếu API trả 200 thì phải lưu được phiên và vào ứng dụng. Lỗi sync dữ liệu sau xác thực được báo riêng, không phải sai mật khẩu.
3. Nếu sau sửa vẫn có **HTTP401 từ `/api/auth/login`**, cần kiểm tra định danh, bàn phím, chữ hoa/thường và ký tự khoảng trắng có chủ ý. Không thử hàng loạt mật khẩu hoặc tự sửa hash.
4. Chức năng quên mật khẩu hiện tại ở backend chỉ nhận tài khoản **customer**; không coi đó là quy trình reset Owner. Nếu Owner thực sự mất mật khẩu, cần quy trình quản trị khôi phục có kiểm chứng quyền sở hữu, xác nhận riêng, đặt mật khẩu mới được hash và xử lý phiên cũ. Chưa thực hiện hoặc thêm quy trình đó trong đợt này.

Lệnh kiểm thử: `flutter test --no-pub`; trong backend: `node scripts/test-login-auth.js` và `npm run test:auth`.
