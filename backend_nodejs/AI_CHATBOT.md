# Hoàn thiện chatbot Gemini / SmartSales

## Lỗi xác nhận trước khi sửa

1. `/chat` cho Gemini gọi `addToCart` khi chỉ thấy câu mua hàng, dù Flutter có luồng hỏi lại. Prompt không phải cơ chế phân quyền/xác nhận.
2. `/reply` coi `toolResult` do client gửi là “kết quả thực tế”. Client có thể đưa giá/ưu đãi giả vào ngữ cảnh.
3. Các route tư vấn/giới thiệu trả nguyên văn mô hình, không kiểm tra tên/giá/tồn/khuyến mãi trong câu trả lời.
4. Lời gọi Gemini không timeout, thử lại cả quota 3 lần; thời gian xử lý có thể vượt timeout Flutter. Default model trong route không khớp `.env.example`.
5. Danh mục bị cắt 80 sản phẩm. Xác nhận do client tự gửi không có bằng chứng đã hiển thị đề nghị; gửi lại thao tác `add` có thể cộng lặp.
6. Flutter tiêu thụ pending trước khi có kết quả, gây khó xử lý mất phản hồi. Các biến static giữ hội thoại giữa những lần mở chat có thể mang ngữ cảnh sang tài khoản khác.

## Luồng mới và phần nào thực sự dùng AI

Giữ giao diện Messenger, tìm/xem giỏ/đơn, hủy đơn và checkout có xác nhận hiện có. Không sửa schema, database nghiệp vụ hoặc các service tính tiền/kho/báo cáo P1/P2.

```text
Flutter → JWT → truy vấn sản phẩm active từ DB
                ↓
       Gemini phân loại/chọn ID (JSON có schema)
                ↓
       xác minh ID, ngân sách, phạm vi và dữ liệu
                ↓
       backend dựng tên, giá, đơn vị, tồn và câu so sánh từ DB
```

- **AI:** hiểu câu hỏi và xếp/chọn ID phù hợp bằng Gemini. Không dùng văn bản mô hình làm nguồn số liệu hoặc kết quả thao tác.
- **Quy tắc:** chào hỏi, chính sách chưa cấu hình, truy vấn voucher, lọc ngân sách, so sánh giá trên đơn vị bán, kiểm tra dữ liệu và xác nhận giỏ. Không gọi đây là mô hình ML tự huấn luyện.
- JSON phải đúng các trường `intent`, `productIds`, `information`; ID phải có trong ngữ cảnh DB. Trường giá/khuyến mãi tự sinh, function call, JSON hỏng, phản hồi bị cắt hoặc bị chặn đều bị loại.
- Tên/giá/tồn trả về luôn dựng từ dòng DB tại lúc tra cứu, không lấy giá từ client, Gemini, lịch sử hoặc `toolResult`. Mô tả được ghi rõ là mô tả cửa hàng, không tự thêm công dụng/dinh dưỡng/hạn dùng.
- Tư vấn ngân sách nêu các lựa chọn riêng lẻ, không tự gọi một danh sách là combo trong ngân sách. Không quy đổi hộp/chai/kg khi thiếu dữ liệu. Hết hàng vẫn có thể hiển thị để trả câu hỏi tồn; đề xuất ngân sách chỉ lấy hàng còn.
- Voucher được đọc lại từ DB: active, chưa hết hạn và còn lượt. Hiển thị điều kiện và mức trần kể cả trần 0; checkout vẫn xác minh điều kiện tài khoản/đơn. Không lấy mã do mô hình nghĩ ra.
- Lấy danh mục active không cắt 80; ngữ cảnh mô hình tối đa 100 sản phẩm, ưu tiên kết quả tìm kiếm và ID đang hỏi. ID cụ thể vẫn truy xuất được ngoài 80 dòng trước đây.

Tham khảo cách cấu hình JSON cho API hiện có: [Google Gemini structured output](https://ai.google.dev/gemini-api/docs/generate-content/structured-output). Schema chỉ ràng buộc định dạng; mã ứng dụng vẫn phải xác minh nội dung và dựng dữ kiện từ DB.

## Xác nhận giỏ, không trao quyền ghi cho AI

1. Flutter gửi `/api/ai/cart-proposal` với productId, quantity, mode. Route JWT **customer** chỉ đọc giá/tồn/giỏ hiện tại, không tạo cart hoặc ghi hàng.
2. Backend trả câu xác nhận và JWT mục đích `cart_confirmation`, hạn 5 phút, gắn user/product/quantity/giá/đơn vị và số lượng giỏ trước–sau.
3. Khách xác nhận rõ; Flutter gửi token đến `/api/ai/chat`. Backend xác minh chữ ký, hạn, mục đích, tài khoản và lời xác nhận, rồi khóa cart/product và kiểm tra lại dữ liệu.
4. Ghi **tổng số lượng đích**, không cộng lại số lượng từ request. Retry đồng thời hoặc mất phản hồi sau commit gặp cùng đích sẽ trả trạng thái giỏ hiện tại. Giá/đơn vị/tồn hoặc giỏ thay đổi ngoài đề nghị thì trả 409, yêu cầu xác nhận lại.
5. Thành công mới cập nhật cache; lỗi làm mới cache không biến giao dịch thành thất bại. Lỗi mạng giữ đề nghị trong phiên chat để thử lại cùng token. Đổi chủ đề/từ chối không tự thao tác; khi mở/gửi chat dưới tài khoản khác, ngữ cảnh static được xóa.

`confirmedCart` không có token hợp lệ không đủ quyền ghi. Header `x-user-id`, lịch sử, ID gợi ý hoặc function call của mô hình không thể cấp quyền. Token xác nhận giỏ không dùng làm access token được. Gemini không nhận tool tạo đơn/thanh toán/ghi dữ liệu. Luồng checkout/hủy đơn của Flutter tiếp tục dùng API nghiệp vụ hiện có với các bước xác nhận riêng.

Không thêm bảng chống lặp theo yêu cầu giữ schema. Cơ chế trên là compare-and-set đến số lượng đích, không phải sổ idempotency bền vững toàn hệ thống. Nếu app bị xóa/khởi động lại, token hết hạn hoặc khách sửa giỏ rồi đưa về đúng trạng thái cũ (ABA), cần kiểm tra giỏ và xác nhận mới; không tự phát lại yêu cầu mua cũ. Mỗi tab/thiết bị có thể giữ một đề nghị khác, backend sẽ chặn phần lớn xung đột bằng trạng thái trước–sau, không hứa lưu lịch sử mọi thao tác giỏ.

## Lỗi dịch vụ và bảo mật

- Key chỉ ở `backend_nodejs/.env`; dùng header `x-goog-api-key`, không gắn URL. Không có Gemini key trong `lib`/assets. Không đưa raw response/error của nhà cung cấp vào UI/log.
- Timeout mặc định 7 giây (`GEMINI_TIMEOUT_MS`, giới hạn 0,1–12 giây). Một lần gọi/lượt, không lặp 429. Mất mạng, quota, model/key lỗi, safety block, output không hợp lệ đều chuyển sang tìm dữ liệu dự phòng và trả `aiStatus` để đánh giá.
- Kết quả dự phòng có ghi rõ AI tạm không khả dụng. Không đoán dữ liệu khi DB lỗi. Câu hỏi về sản phẩm đã chọn không dùng giá/tồn cũ trong cache để xác nhận khi không tra được server.
- Lọc SĐT/email và thông tin địa chỉ có nhãn trước khi gửi nội dung/lịch sử tới Gemini. Không gửi kết quả đơn/giỏ hay `toolResult` không xác minh làm dữ kiện. Đây không phải bộ DLP bao phủ mọi cách viết thông tin cá nhân; người dùng vẫn nên tránh gửi dữ liệu nhạy cảm ngoài luồng nhận hàng.
- Giới hạn tin 2.000 ký tự, lịch sử 30 lượt (mô hình chỉ nhận tối đa 6 lượt rút gọn), ngữ cảnh 100 sản phẩm và 30 lượt tư vấn/phút/tài khoản/process. Xác nhận giỏ không bị quota Gemini/rate-limit tư vấn chặn. Rate limit dùng RAM, chưa chia sẻ giữa nhiều process.

## Kết quả kiểm thử và cách hiểu tỷ lệ

| Đánh giá | Kết quả | Phạm vi |
|---|---:|---|
| Câu hỏi chuẩn, provider phản hồi theo fixture | 27/27 | Hồi quy tích hợp với Gemini giả lập; không phải accuracy Gemini thật |
| Tìm/chọn đúng bộ ID khi **không gọi Gemini** | 26/27 = **96,3%** | So đáp án ID trên danh mục giả cố định; câu tư vấn nguyên liệu chung còn thiếu lựa chọn |
| Tình huống tự động tư vấn và bất thường | **43 kiểm tra đạt** | Quota, network, timeout, JSON/ID/giá giả, function call, safety/truncation, dữ liệu client giả, PII, sản phẩm ngoài 80 dòng |
| Xác nhận giỏ hợp lệ | **14/14 = 100%** | 14 phản hồi xác nhận hợp lệ, gồm replay; các lần cố ý gây lỗi không nằm mẫu số. Fixture transaction/cart, không phải giao dịch người dùng thật |
| Nhóm bảo vệ giỏ | **11 nhóm đạt** | Chưa xác nhận, sai tài khoản/chữ ký/hết hạn, đổi giá/đơn vị/tồn/giỏ, rollback, số lượng sai |
| Flutter | **163 test đạt** | Thêm 3 widget test: propose trước confirm, giữ token sau mất phản hồi, từ chối/đổi tài khoản; giữ UI và hồi quy cũ |
| JWT | **350 kiểm tra / 108 route/alias đạt** | HTTP thật, DB giả; customer-only proposal, token khác purpose, header giả danh, giới hạn 30 lượt tư vấn/phút |

Corpus là tập nghiệm thu có đáp án minh bạch và đã dùng trong phát triển, không phải tập holdout độc lập; không suy ra độ chính xác toàn bộ câu hỏi ngoài thực tế. Ở giai đoạn kiểm tra ban đầu chưa có key nên chưa thể công bố độ chính xác Gemini thật. Kết quả kiểm tra sau khi có key và đổi model được ghi tại GEMINI_DIAGNOSIS.md. Các con số không đo mức hài lòng, dinh dưỡng hay công thức nấu ăn.

Các script tính tiền (24 nhóm), kho–kệ (9 nhóm), pending/hủy đơn, bank transfer và VNPay đã chạy hồi quy đạt. Không chạy migration hoặc ghi giao dịch thật để thử chatbot. Phân tích Flutter không error/warning trong các file đã kiểm tra; còn các lint info về dấu ngoặc từ code đang có.

Bản sửa đã được chép vào thư mục dự án, backend khởi động thành công. Smoke test trên database thật xác nhận giá/tồn trả về khớp dòng sản phẩm, đề nghị giỏ chưa ghi dữ liệu, xác nhận không ký trả 400 và header giả danh không JWT trả 401. Số bản ghi carts/cart_items/orders/payments trước và sau không đổi; không thực hiện xác nhận giỏ thật. Ở lần kiểm tra trước khi người dùng cấu hình key, trạng thái là `not_configured` và `attempted:0`. Trạng thái mới sau khi khắc phục quyền truy cập model xem [GEMINI_DIAGNOSIS.md](GEMINI_DIAGNOSIS.md).

## Cấu hình và đo Gemini thật

Trong **backend_nodejs/.env**, không phải Flutter assets:

```dotenv
GEMINI_API_KEY=...khóa của bạn...
GEMINI_MODEL=gemini-3.5-flash-lite
GEMINI_TIMEOUT_MS=7000
```

Dùng model `generateContent` được tài khoản của bạn cấp quyền; tên trên là default khớp `.env.example`, không khẳng định model luôn còn khả dụng. Nếu nhận `model_unavailable`, chọn model đang có trong Google AI Studio/tài khoản. Không gửi key vào chat hoặc commit Git. Restart backend sau khi sửa `.env`.

```sh
cd backend_nodejs
npm run test:ai
npm run test:auth
npm run eval:ai:live
```

`eval:ai:live` gọi tối đa 12 câu trên danh mục giả, không truy cập database, tự dừng khi quota/key/model lỗi. Kết quả tách provider success rate, chọn ID đúng của mô hình và dữ kiện đúng của câu trả lời sau kiểm soát. Không có key thì `attempted:0`, các tỷ lệ mô hình là null, không giả thành 100%. Có thể tốn quota/phí dịch vụ.

Sau Hot Restart Flutter, kiểm tra: tìm giá/tồn, so sánh hai sản phẩm, ngân sách, mã ưu đãi thật, yêu cầu thêm chưa xác nhận, xác nhận/nhấn lặp, đổi giá giữa đề nghị và xác nhận, từ chối mua, mất mạng rồi thử lại token cũ, mở chat ở tài khoản khác. Checkout/QR/thanh toán phải tiếp tục cần xác nhận riêng; không có câu hỏi tư vấn nào tự ghi đơn.

Giới hạn còn lại: tìm kiếm dự phòng chưa hiểu đầy đủ lỗi chính tả/tiếng lóng và tư vấn nguyên liệu; so sánh không suy ra giá trên cùng khối lượng nếu thiếu quy đổi; không sáng tác công dụng/hạn dùng/dinh dưỡng; ngữ cảnh mô hình có giới hạn; giỏ trong hội thoại không có ledger chống lặp xuyên mọi thay đổi ngoài luồng.

## File thay đổi

- `backend_nodejs/src/routes/ai.routes.js`
- `backend_nodejs/src/services/ai-cart.service.js`
- `backend_nodejs/src/services/ai-grounding.service.js`
- `backend_nodejs/scripts/eval-ai-live.js`
- `backend_nodejs/scripts/helpers/ai-cases.js`
- `backend_nodejs/scripts/test-ai-cart.js`
- `backend_nodejs/scripts/test-ai-chat-validation.js`
- `backend_nodejs/scripts/test-ai-faq.js`
- `backend_nodejs/scripts/test-authorization.js`
- `lib/services/api_service.dart`
- `lib/widgets/smart_sales_chatbox.dart`
- `test/smart_sales_confirmation_test.dart`
- `backend_nodejs/package.json`
- `backend_nodejs/.env.example`
- `backend_nodejs/AI_CHATBOT.md`
