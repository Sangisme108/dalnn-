# Báo cáo doanh thu, giá vốn và lợi nhuận — P2

## Nguyên nhân và thay đổi

- Báo cáo cũ lấy giá nhập mới nhất, nên lợi nhuận của đơn cũ đổi khi nhập lô mới. Nay chỉ dùng `order_items.cost_amount`, chốt trong transaction xuất bán.
- Dashboard cũ JOIN đơn với từng dòng hàng rồi SUM tiền đơn, gây nhân doanh thu. Nay một bộ sự kiện dùng chung cho báo cáo tổng, ngày/tháng/năm, hiệu suất và sản phẩm; mỗi dòng chỉ đóng góp phần doanh thu của nó, đơn đếm bằng tập ID duy nhất.
- Điều kiện cũ “đã trả tiền HOẶC hoàn thành” đã thay bằng “đã trả tiền VÀ hoàn thành”, loại hủy/từ chối. Đơn đang giữ chỗ, chưa thanh toán, hoặc mới trả trước chưa hoàn thành không thành doanh thu.
- Flutter không tải lại toàn bộ đơn để tự tính, không âm thầm fallback về số liệu khác kỳ khi API lỗi. Tham số lọc gửi backend, các biểu đồ dùng doanh thu thuần và hỗ trợ kỳ âm do hoàn tiền.
- Thống kê nhân viên không SUM các dòng payment; lấy tiền đơn duy nhất, trừ tổng hoàn đã ghi sổ. Lịch sử chọn một payment thành công cuối cùng bằng derived-table JOIN tương thích TiDB. Thống kê theo nhân viên/ca là số tiền còn lại của các đơn được gán cho nhân viên/ca đó, không thay thế báo cáo tài chính theo ngày phát sinh hoàn.

## Migration đã được người dùng cho phép

Chạy trong `backend_nodejs`: `npm run db:migrate:reporting`.

| Bảng | Trường/bảng mới |
|---|---|
| products, inventory_items | `stock_cost DECIMAL(18,2) NULL`: tổng giá trị tồn, không phải giá nhập gần nhất |
| order_items | `cost_amount DECIMAL(18,2) NULL`, `unit_cost DECIMAL(18,6) NULL`, `allocated_discount DECIMAL(12,2) NULL` |
| orders | `voucher_discount`, `manual_discount`, `recognized_at`, `reporting_version`, `refund_status`; đều cho phép NULL |
| sales_refunds | Chứng từ hoàn, người thực hiện, UUID, hash payload, tiền hoàn, giá vốn đảo, điểm, thời điểm; UNIQUE đơn+UUID và mã chứng từ |
| sales_refund_items | Dòng bán gốc, số lượng hoàn, có nhập trả hay không, tiền hoàn và giá vốn đảo |
| inventory_valuations | Định giá tồn đã kiểm chứng, vị trí, số lượng lúc xác nhận, Owner, lý do và UUID duy nhất |

Migration chỉ ADD COLUMN và CREATE TABLE IF NOT EXISTS. Không UPDATE đơn/dòng bán/tồn cũ, không backfill giá vốn, không đổi giá hay xóa dữ liệu. Có thể chạy lại; DDL có implicit commit, không coi chuỗi DDL là một transaction rollback được. Nếu bị ngắt, chạy lại trước khi khởi động backend mới.

Fresh install theo README cũng phải chạy migration này trước server. Không cần cài dependency mới. Backend cũ bỏ qua các cột mới nên có thể dùng để rollback mã nguồn nếu cần, giữ nguyên schema bổ sung; không DROP các bảng/cột chứa sổ giao dịch mới.

## Phương pháp giá vốn

Giá vốn bình quân liên hoàn được biểu diễn bằng **tổng giá trị tồn / số lượng tồn**. Tiền được tính bằng BigInt theo đơn vị nhỏ nhất 0,01 VND. Khi xuất q trong Q:

```text
Giá vốn xuất = làm tròn(Tổng giá trị tồn × q / Q)
Giá trị tồn còn = Tổng giá trị tồn − Giá vốn xuất
```

Lấy hết tồn lấy hết giá trị còn lại, nên các lần xuất nhỏ không làm mất/chênh tiền do làm tròn. `unit_cost` là đơn giá tham khảo 6 số lẻ; báo cáo và hoàn hàng dùng `cost_amount` chính xác đến 2 số lẻ.

- Nhập kho: cộng giá trị `số lượng nhập × giá nhập của lần nhập đó`. Tạo hàng kho mới có số lượng/giá nhập hợp lệ được xem là lô đầu mới, không áp dụng ngược cho hàng đã tồn tại.
- Chuyển kho–kệ: trừ giá trị nguồn, cộng giá trị đích trong transaction và khóa dòng của bản sửa P1; retry không cộng lại.
- Bán: đọc/khóa sản phẩm, chốt giá vốn, trừ tồn và giá trị, lưu snapshot dòng bán, giảm giá và đơn trong cùng transaction. Với online, snapshot tại lúc xuất tồn logic/giữ hàng khi tạo đơn; hủy chưa thanh toán nhập lại đúng giá vốn snapshot.
- Nhập trả sau bán: cộng đúng giá vốn của lượng hàng trả theo snapshot gốc, không dùng giá nhập mới. Hoàn tiền không nhập trả không đảo giá vốn.
- Kiểm kê giảm tồn: giảm giá trị theo bình quân. Tăng tồn hoặc đổi số lượng/đơn vị bằng chức năng sửa thủ công làm giá trị chưa xác định, thay vì đoán giá cho phần tăng. Sửa giá bán/giá nhập hiển thị không viết lại snapshot cũ.

`NULL` có nghĩa chưa biết. Trộn hàng có giá trị đã biết với tồn dương chưa biết vẫn ra NULL. Khi hết tồn, giá trị còn bằng 0; lô mới có chứng từ sau đó có thể xác định giá vốn. Owner có thể định giá **tồn hiện tại** bằng chứng từ/kiểm kê qua API có audit bên dưới; việc đó không sửa giá vốn của đơn đã bán trước đó.

## Công thức và thời điểm

```text
G = Tổng tiền trước giảm giá của các dòng bán đủ điều kiện
D = Giảm voucher + giảm thủ công + giảm bằng điểm
R = Tiền hoàn đã ghi sổ trong kỳ
N = G − D − R                         (doanh thu thuần)
C = Giá vốn xuất bán − giá vốn nhập trả (giá vốn thuần)
P = N − C                             (lợi nhuận gộp)
```

Giảm giá phân bổ đến dòng bằng phương pháp tỷ lệ lũy kế và làm tròn theo cent, tổng phân bổ bằng đúng tổng giảm. Thành phần voucher/thủ công/điểm cũng được phân chia trong phần giảm dòng, tránh chênh 1 cent giữa thành phần và tổng. Không áp lại định nghĩa voucher hiện tại cho đơn cũ.

`recognized_at` được chốt một lần khi đồng thời hoàn thành và thanh toán thành công; POS tiền mặt ghi ngay. Callback lặp không ghi thêm doanh thu/điểm. Múi giờ chung `Asia/Ho_Chi_Minh` / `+07:00` cho pool và các bucket. Hoàn tiền ghi vào kỳ hoàn thực tế, không sửa lùi doanh thu kỳ bán.

Ví dụ G=200.000, voucher=10.000, thủ công=5.000, điểm=10.000, C=20.000: N=175.000, P=155.000. Hoàn một nửa và nhập trả: R=87.500, đảo C=10.000. Hoàn nửa còn lại nhưng không nhập trả: cả đơn còn lỗ giá vốn 10.000, không tự đưa lợi nhuận về 0.

## API Owner: định giá tồn có căn cứ

`POST /api/inventory/valuation`, JWT Owner/admin:

```json
{
  "location": "shelf",
  "item_id": 12,
  "expected_stock": 10,
  "stock_cost": "150000.00",
  "operation_id": "11111111-1111-4111-8111-111111111111",
  "reason": "Đã kiểm kê và đối chiếu hóa đơn nhập ..."
}
```

`location` là `shelf` hoặc `warehouse`; `item_id` là PK database, không phải barcode. `stock_cost` là tổng giá trị của toàn bộ tồn đang có, không phải đơn giá. Không nhập số giả chỉ để làm xuất hiện lợi nhuận. Tồn đã thay đổi so với `expected_stock` trả 409; phải kiểm chứng lại. UUID cũ cùng nội dung chỉ trả biên nhận, không định giá lại sau các giao dịch khác.

## API Owner: ghi nhận hoàn tiền đã thực hiện

`POST /api/orders/:id/refunds`, JWT Owner/admin:

```json
{
  "operation_id": "22222222-2222-4222-8222-222222222222",
  "refund_reference": "MA-CHUNG-TU-HOAN-THUC-TE",
  "reason": "Khách trả hàng, đã hoàn tiền theo chứng từ",
  "items": [{"order_item_id": 45, "quantity": 1, "restock": true}]
}
```

Đây là sổ xác nhận khoản hoàn đã thực hiện, **không tự chuyển tiền ngân hàng**. SePay hiện dùng xác nhận tiền đến, không được coi là API chuyển tiền ra. Backend tự tính tiền theo dòng bán trừ phần giảm đã phân bổ, không nhận số tiền/giá vốn/điểm do client chỉ định.

Khóa đơn, kiểm tra số lượng đã hoàn, nhập trả và điểm trong transaction. UUID cùng nội dung replay; đổi payload trả 409. Mã chứng từ không dùng cho khoản khác. Mất phản hồi: gửi lại đúng UUID, chứng từ và payload; không tạo UUID mới để thử.

Hoàn lại điểm đã dùng và thu hồi điểm đã thưởng theo tỷ lệ lũy kế giá trị hàng hoàn; hoàn toàn bộ cân đủ điểm, không cộng/trừ lặp. Nếu khách đã tiêu điểm thưởng, số dư có thể âm để thể hiện khoản điểm cần thu hồi; không cho đổi điểm khi không đủ số dư. Không trừ doanh thu một lần nữa vì hoàn điểm.

Giữ trạng thái payment `paid` để callback đến muộn không coi đơn là chưa trả tiền; `refund_status` là `partial/full`. Sổ hoàn là nguồn tính tiền âm. Chưa bổ sung màn hình thao tác định giá/hoàn tiền trong Flutter; Owner dùng API/Postman theo mẫu, giao diện báo cáo đã đọc sổ này. Không gửi tiền thật trong các kiểm thử.

## Dữ liệu cũ và giới hạn

- Giá vốn dòng cũ, phân tách voucher/thủ công cũ và thời điểm ghi nhận cũ vẫn NULL. Không lấy giá nhập hiện tại hoặc voucher hiện tại để điền ngược.
- Doanh thu của đơn cũ đủ điều kiện dùng ngày tạo đơn, có `quality.legacy_date_orders` và ghi chú hiển thị; không gọi đó là ngày ghi nhận kế toán đã xác minh.
- Dòng thiếu giá vốn làm C/P của tổng tương ứng NULL; Flutter hiện “Chưa xác định”. Định giá tồn hôm nay không chữa được giá vốn lịch sử đã mất.
- Đơn lệch tổng tiền/chi tiết/phân bổ bị loại và tăng `quality.inconsistent_orders`. Đơn có trạng thái refunded cũ nhưng không có sổ hoàn được đánh dấu `quality.untracked_refunded_orders`; không đoán ngày/số tiền hoàn. Nếu có các lỗi này, lợi nhuận bị chặn và báo cáo ghi chưa đầy đủ; số doanh thu là phần giao dịch xác định được.
- API hoàn tự động phân bổ chỉ nhận đơn phiên bản mới đã có snapshot và thời điểm ghi nhận. Hoàn đơn cũ cần đối soát và quy trình nhập chứng từ riêng, không giả lập giá vốn chính xác.
- Lợi nhuận gộp chưa trừ lương, thuê nhà, điện nước, thuế và chi phí hoạt động. Đơn vị hiện có là số lượng nguyên, chưa quản lý cân lẻ.
- Đọc báo cáo trong consistent snapshot để tránh trộn các thời điểm. Phiên bản này đọc các dòng bán/hoàn để tổng hợp bằng số nguyên; dữ liệu lớn cần chuyển sang aggregation theo phạm vi trong SQL hoặc kho báo cáo, không nên tải lịch sử vô hạn.

## Kiểm thử và kiểm tra thủ công

Kết quả ngày 06/11/2026:

- **16 nhóm integration MySQL/TiDB đạt**, chạy trên database thử nghiệm độc lập, đã dọn sau chạy.
- **160 test Flutter đạt**, gồm 2 test mới cho báo cáo.
- **309 kiểm tra HTTP JWT qua 107 route/alias đạt**.
- **24 nhóm tính tiền và 9 nhóm chuyển kho–kệ đạt**; các script hồi quy chatbot/FAQ, pending orders, lỗi hủy, bank transfer, VNPay đều đạt.
- Phân tích tĩnh 5 file Flutter liên quan: không error/warning; còn 4 info cũ (tên file và dấu ngoặc if). Analyze trả exit code 1 vì các info, không coi là analyze sạch.
- **Đã áp dụng migration trên database dự án** sau khi người dùng đồng ý. Đối chiếu trước/sau: số bản ghi 9 bảng, tổng tồn kho/kệ, điểm, tổng tiền gộp/giảm/thuần giữ nguyên. Giá vốn/định giá/thời điểm ghi nhận bổ sung của tất cả bản ghi cũ vẫn NULL. Không chạy giao dịch bán/định giá/hoàn tiền thật.
- Lưu cấu trúc và số đối chiếu trước migration tại `/tmp/mini-market-reporting-before-20261106.json`.
- Backend đã restart. Ba GET thật có JWT Owner (`/api/reports/revenue`, `/api/reports/product-performance`, `/api/performance/dashboard`) trả 200; header giả danh không JWT trả 401. Token thử chỉ giữ trong bộ nhớ, không ghi ra file/log.

- `npm run test:reporting:mysql`: opt-in tạo database `test_reporting_<random>`, chỉ sao chép cấu trúc và dữ liệu giả, sau đó dọn đúng database thử nghiệm. Cần quyền CREATE/DROP DATABASE; không chạy trên tài khoản production hạn chế quyền. Không sao chép dữ liệu cá nhân.
- Các nhóm integration kiểm tra migration lặp/NULL lịch sử, bình quân, thay giá nhập, giảm giá/điểm, nhiều dòng không đếm lặp, pending/cancel, refund một phần/toàn phần, không nhập trả, UUID đồng thời, rollback giữa chừng, phân kỳ tháng/năm, JWT, định giá Owner, bảo toàn cent, callback và payment trùng.
- `npm run test:billing`, `npm run test:inventory`, `npm run test:auth` giữ kiểm thử hồi quy P1.
- `flutter test --no-pub`: kiểm tra cả UI cũ và report mới chỉ gọi API đúng bộ lọc, hiển thị NULL và không fallback số liệu sai.

Sau restart backend và Hot Restart Flutter: thử bán mặt hàng có căn cứ giá vốn, đổi giá nhập, xem lại cùng kỳ; thử voucher+điểm; đối chiếu tổng/net/COGS/P. Kiểm tra một đơn nhiều dòng chỉ đếm một lần; đơn pending/cancel không thành doanh thu. Dùng dữ liệu demo để ghi nhận hoàn có/không nhập trả, kiểm tra tiền âm đúng kỳ và không trừ hai lần khi retry. Kiểm tra ghi chú dữ liệu cũ, danh sách hàng không có giá vốn, ca nhân viên, QR/SePay, checkout online và hủy đơn chưa thanh toán.

## File thay đổi trong đợt này

- `backend_nodejs/src/config/db.js`
- `backend_nodejs/src/routes/inventory.routes.js`
- `backend_nodejs/src/routes/order.routes.js`
- `backend_nodejs/src/routes/performance.routes.js`
- `backend_nodejs/src/routes/product.routes.js`
- `backend_nodejs/src/routes/report.routes.js`
- `backend_nodejs/src/routes/user.routes.js`
- `backend_nodejs/src/services/costing.service.js`
- `backend_nodejs/src/services/inventory-transfer.service.js`
- `backend_nodejs/src/services/order-billing.service.js`
- `backend_nodejs/src/services/order-payment.service.js`
- `backend_nodejs/src/services/refund.service.js`
- `backend_nodejs/src/services/reporting.service.js`
- `backend_nodejs/src/services/valuation.service.js`
- `backend_nodejs/scripts/helpers/billing-fixture.js`
- `backend_nodejs/scripts/migrate-reporting.js`
- `backend_nodejs/scripts/test-authorization.js`
- `backend_nodejs/scripts/test-inventory-transfer.js`
- `backend_nodejs/scripts/test-reporting-mysql.js`
- `lib/screens/RevenueOverviewScreen.dart`
- `lib/screens/product_performance_report_screen.dart`
- `lib/screens/revenue_period_chart_screen.dart`
- `lib/services/api_service.dart`
- `test/reporting_authoritative_test.dart`
- `backend_nodejs/package.json`
- `README.md`
- `backend_nodejs/REPORTING.md`
