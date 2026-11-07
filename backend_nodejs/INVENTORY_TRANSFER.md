# Bản sửa P1: chuyển hàng từ kho lên kệ

## Lỗi đã xác nhận trước khi sửa

- `DBService.releaseInventoryToShelf` cộng trực tiếp `existing.stockQuantity`, rồi gọi API cập nhật/tạo sản phẩm trước khi xuất kho.
- `/inventory/export` chỉ trừ kho và ghi log; không cộng kệ trong cùng transaction. Bước xuất kho thất bại có thể để lại kệ đã tăng.
- Không có mã thao tác bền vững để phân biệt thử lại sau mất phản hồi với lần chuyển mới.
- Nút được vô hiệu hóa trong lúc xử lý nhưng hàm xử lý chưa có chốt chống gọi lại; hộp số lượng chấp nhận 0.
- Model kho lưu barcode làm `id`, làm mất `inventory_item_id`; API cũ tìm bằng `id OR barcode`, dễ nhầm mã vạch dạng số.

## Luồng mới

`POST /api/inventory/transfer-to-shelf`

```json
{
  "inventory_item_id": 7,
  "quantity": 2,
  "operation_id": "11111111-1111-4111-8111-111111111111"
}
```

JWT Bearer bắt buộc; chỉ Owner/admin và employee/staff. Không nhận danh tính từ `x-user-id`, body, hay thời gian do Flutter gửi.

1. Kiểm tra PK nguyên dương, số lượng nguyên dương trong giới hạn INT, UUID v4.
2. Mở transaction; khóa hàng kho theo PK bằng `SELECT ... FOR UPDATE`.
3. Tìm biên nhận cùng nhân viên, PK kho và UUID bằng locking read. Nếu có, không thay đổi tồn; trả log cũ và số dư hiện tại. Cùng UUID nhưng khác số lượng trả 409.
4. Kiểm tra tồn thực tế, trạng thái. Khóa sản phẩm cùng barcode; cộng tồn bằng `stock = stock + ?`, giữ nguyên giá và thông tin sản phẩm đang có. Khác đơn vị hoặc kệ không hoạt động trả 409.
5. Nếu chưa có sản phẩm, tạo bằng metadata đọc từ kho trong database, xác minh danh mục và giá; không tin giá/danh mục Flutter.
6. Trừ kho, ghi lịch sử và biên nhận; đọc lại cả hai số dư; commit trước khi gửi phản hồi. Lỗi trước commit rollback mọi thay đổi, kể cả sản phẩm mới và log.
7. Flutter chỉ ghi cache từ phản hồi thành công; không gọi API sản phẩm và API xuất kho riêng nữa.

Nhân viên được lấy từ JWT đã xác thực và đối chiếu user đang hoạt động. **Thời điểm chuyển lấy từ timestamp của database**, không dùng `iat` của JWT vì đó là thời điểm cấp token.

### Chống gửi trùng không migration

Biên nhận có phiên bản `@shelf1:` nằm trong `inventory_logs.note`, cùng transaction với hai thay đổi tồn. Ghi chú API trả về vẫn là “Đưa hàng lên kệ”, kèm `operation_id`, `before_quantity`, `after_quantity`. API ghi kho từ chối ghi chú do client gửi có tiền tố dành riêng này.

Khóa dòng kho tuần tự hóa những request cùng nguồn, kể cả nhiều process backend. Phạm vi UUID là **nhân viên JWT + PK kho**; UUID không phải mã toàn cục cho mọi hàng/nhân viên. Không phụ thuộc khóa trong RAM để chống lặp phía backend.

Flutter lưu UUID và payload vào Hive, flush trước khi gửi. Timeout, lỗi mạng, HTTP 5xx, token hết hạn, phản hồi không đọc được hoặc lỗi ghi cache đều giữ mã để thử lại. Có thao tác chưa xác định kết quả thì chặn chuyển sản phẩm/số lượng khác cho tài khoản đó, hiển thị hướng dẫn thử lại thao tác cũ. Một thao tác đang chạy chặn lần gọi tiếp theo. Lỗi nghiệp vụ xác định 400/404/409 cho phép sửa và gửi thao tác mới. Thành công mới xóa pending.

Model Hive thêm trường tùy chọn `databaseId` ở field 8; cache cũ thiếu trường vẫn đọc được, rồi tra PK qua GET kho theo barcode chính xác. Không đổi schema SQL hoặc tăng phiên bản cache để xóa dữ liệu.

## File thay đổi trong đợt này

| File | Nội dung |
|---|---|
| `src/services/inventory-transfer.service.js` | Mới: transaction, khóa dòng, kiểm tra và biên nhận chống lặp |
| `src/routes/inventory.routes.js` | Endpoint mới, bảo vệ tiền tố log, giải mã lịch sử; giữ API nhập/xuất/kiểm kê |
| `scripts/test-inventory-transfer.js` | Mới: fixture transaction và kiểm thử lỗi/đồng thời/retry |
| `scripts/test-authorization.js` | Thêm kiểm tra endpoint, vai trò và chống giả mạo biên nhận |
| `package.json` | Thêm `npm run test:inventory`; không thêm dependency |
| `../lib/models/inventory_item.dart` | Lưu PK database vào model và Hive tương thích cache cũ |
| `../lib/services/api_service.dart` | Gọi API nguyên tử với JWT; phân biệt kết quả chưa xác định |
| `../lib/services/db_service.dart` | Bỏ cập nhật tồn trước xác nhận; lưu UUID, chống nhấn trùng, đồng bộ cache và log từ response |
| `../lib/screens/add_product_screen.dart` | Chặn gọi lại, số lượng >0, kiểm tra mounted, hỗ trợ thử lại thao tác pending |
| `../test/inventory_transfer_test.dart` | Mới: kiểm thử Flutter/Hive/HTTP |
| `INVENTORY_TRANSFER.md` | Báo cáo và checklist này |

Các file đã sửa JWT, tính tiền, voucher, điểm thưởng và thanh toán trước đó được giữ lại. Không sửa dữ liệu thực tế, không migration, không thêm package.

## Kiểm thử

- Node chuyển kho–kệ: **9 nhóm kịch bản**, gồm metadata DB, kiểm tra đầu vào, thiếu tồn, rollback tại nhiều bước, xóa sản phẩm mới khi rollback, hai nhân viên tranh tồn, 15 request trùng, mất xác nhận commit rồi replay, trạng thái/đơn vị/giới hạn tồn.
- Flutter: **158 test pass**, trong đó **7 test mới**: không cập nhật tồn sớm, chặn gọi đồng thời, JWT không có header giả danh, mất mạng và mở lại Hive vẫn giữ UUID, 500/phản hồi hỏng, lỗi nghiệp vụ/token, lỗi cache sau commit, tra PK cho cache cũ, số lượng không hợp lệ.
- Kiểm thử HTTP JWT/Express: **299 kiểm tra qua 104 route/alias**; gồm thiếu/expired token, sai vai trò, header giả danh, Owner/nhân viên được qua lớp phân quyền và tiền tố log dành riêng.
- Tính tiền: **24 nhóm kịch bản pass**. Các script hồi quy chatbot, FAQ, pending orders, lỗi hủy đơn, bank transfer và VNPay đều pass.
- Phân tích tĩnh Flutter trên 5 file kiểm tra: không error/warning; còn **13 lint mức info** từ code trước đó (context sau await ở luồng chỉnh sửa thủ công, dấu ngoặc và print). Lệnh analyze vẫn trả exit code 1 vì các lint này; không coi đây là kết quả analyze sạch.
- Đã đọc metadata MySQL thật: bốn bảng liên quan đều InnoDB; barcode kho và sản phẩm có UNIQUE; note VARCHAR(255). Chỉ SELECT metadata.

Các bài kiểm thử đồng thời/rollback dùng SQL double có khóa FIFO và rollback journal, chạy service thật; **chưa chạy stress/integration với MySQL thật**, chưa tạo chuyển hàng thật trên dữ liệu của bạn.

Lệnh chạy lại tại root:

```sh
cd backend_nodejs
npm run test:inventory
npm run test:auth
npm run test:billing
cd ..
flutter test --no-pub
```

## Kiểm tra thủ công sau khi restart backend và Flutter

1. Đăng nhập Owner hoặc nhân viên; ghi lại kho W, kệ S. Chọn lấy q: kết quả phải là W−q, S+q; chỉ một lịch sử, đúng nhân viên và thời điểm.
2. Chọn mặt hàng chưa có trên kệ: tạo sản phẩm bằng giá, ảnh, đơn vị, danh mục trong kho. Thử cả sản phẩm đã có trên kệ để xác nhận giá bán cũ được giữ.
3. Nhập 0, số âm, số lẻ và số vượt tồn. Không trường hợp nào được thay đổi dữ liệu. Mở hai thiết bị để kiểm tra tồn thay đổi sau khi hộp chọn đã mở.
4. Hai nhân viên cùng chuyển một mặt hàng: tổng lượng đã chuyển không vượt tồn; kho/kệ khớp nhau. Nhấn nhanh nhiều lần khi đang xử lý chỉ có một thao tác.
5. Ngắt mạng ngay sau khi gửi (dùng proxy/debugger để mô phỏng mất response sau commit). Không xóa cache; bật mạng, chọn lại **đúng hàng và số lượng**. Chỉ có một log/chuyển hàng. Có thể đóng/mở app giữa hai lần thử.
6. Token hết hạn yêu cầu đăng nhập lại. Tài khoản khách hàng hoặc token giả gọi endpoint phải nhận 401/403 và không thay đổi tồn.
7. Kiểm tra hồi quy nhập kho, xuất kho thông thường, kiểm kê, bán tại quầy, đặt online, voucher, tích điểm, QR/SePay và hủy đơn chưa thanh toán.

## Giới hạn và việc còn lại

- Chưa tự cân chỉnh lệch tồn đã phát sinh trước bản sửa: cần đối chiếu thực tế trước khi điều chỉnh, không đoán số rồi ghi database.
- Phải giữ nguyên biên nhận `@shelf1:` trong log để bảo đảm retry bền vững. Không sửa/xóa log này hoặc xóa Hive pending khi đang có thao tác chưa xác định. Nếu người dùng xóa dữ liệu ứng dụng làm mất UUID, không thể tự suy ra một thao tác mới có phải retry hay không.
- Kho có danh mục null, giá không hợp lệ, khác đơn vị, hoặc sản phẩm không hoạt động sẽ bị chặn bằng lỗi nghiệp vụ; cần sửa dữ liệu qua chức năng quản lý hiện có sau khi đối chiếu.
- Các thao tác chỉnh tồn thủ công hiện có vẫn là thao tác riêng, không phải chuyển kho–kệ. Bản sửa không biến một lần ghi đè tồn thủ công bằng dữ liệu cũ thành một phép cộng/trừ an toàn; cần tránh kiểm kê/chỉnh tồn bằng số liệu cũ trong lúc đang chuyển/bán hàng.
- Khi triển khai, cập nhật backend và Flutter cùng đợt. Flutter cũ còn dùng hai API riêng vẫn có luồng cũ; cần ngừng dùng bản cũ.
- Với dữ liệu lớn hoặc nhu cầu quản lý/xóa log, nên có bảng idempotency riêng với UNIQUE, retention và màn hình đối soát pending; cần migration được phê duyệt trước. Phiên bản hiện tại dùng index FK của nguồn kho để giới hạn tìm log, chưa thêm index/schema.
