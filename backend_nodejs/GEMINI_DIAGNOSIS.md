# Chẩn đoán Gemini và khắc phục model_unavailable — 06/11/2026

## Kết luận đã xác minh bằng khóa hiện tại

Lỗi cũ là **HTTP 404 / NOT_FOUND**, không phải suy đoán từ nhãn `model_unavailable`. Google trả về:

```text
This model models/gemini-2.5-flash is no longer available to new users.
Please update your code to use models/gemini-3.8-flash for the latest features and improvements.
We recommend you to use the Interactions API (https://ai.google.dev/gemini-api/docs/get-started).
```

Khóa hiện tại đọc được metadata 2.5 nhưng không được dùng 2.5 để sinh nội dung. Mặc định 2.5 đặt trong đợt sửa trước không phù hợp với quyền truy cập này; đã đổi sang model thực sự gọi được, không yêu cầu bật billing.

Google cũng ghi rõ dòng 2.5 bị giới hạn cho tài khoản đã dùng trước đó và gợi ý 3.5 Flash-Lite hoặc 3.8 Flash cho dự án mới: [tài liệu model chính thức](https://ai.google.dev/gemini-api/docs/models?hl=en). Model vẫn có trong metadata không chứng minh quyền generation; xem [models.list / models.get](https://ai.google.dev/api/models).

## Những yêu cầu thực tế đã thử

| Kiểm tra | Kết quả |
|---|---|
| GET v1beta/models bằng key hiện tại | 200; liệt kê 2.5 và các model mới |
| GET v1beta/models/gemini-2.5-flash | 200; metadata có generateContent |
| GET v1/models/gemini-2.5-flash | 200; metadata có generateContent |
| POST v1beta/models/gemini-2.5-flash:generateContent, text tối giản | **404 NOT_FOUND**, thông báo quyền người dùng mới như trên |
| POST gemini-3.5-flash-lite:generateContent, text tối giản | **200 STOP**, có nội dung, khoảng 1,07 giây |
| POST gemini-3.8-flash:generateContent, text tối giản | Chưa nhận được kết quả trước timeout 15 giây; chưa kết luận nguyên nhân hoặc quyền/quota |
| 4 câu thử bằng đúng schema chatbot với 3.5 Flash-Lite | **4/4 phản hồi hợp lệ** |
| Bộ đánh giá đầy đủ bằng 3.5 Flash-Lite | **12/12 phản hồi hợp lệ**, xem bên dưới |

Danh sách metadata có các model đáng cân nhắc: `gemini-3.1-flash-lite`, `gemini-3.5-flash-lite`, `gemini-3.5-flash`, `gemini-3.6-flash`, `gemini-3.7-flash`, `gemini-3.8-flash` và các alias `gemini-flash-latest`, `gemini-flash-lite-latest`. Không gọi thử hàng loạt model vì metadata không bảo đảm quyền generation/quota và mỗi lần thử có thể dùng quota/phí.

Chọn **gemini-3.5-flash-lite**: đã xác minh cả request tối giản và schema chatbot, phù hợp tác vụ chọn ID ngắn, độ trễ thấp trong lần chạy này. Giữ endpoint Developer API `https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`; không cần đổi API/SDK để khắc phục ca này. Chưa thử generation 2.5 qua v1 và không coi metadata v1=200 là bằng chứng generation thành công.

Không có HTTP 429 trong bộ 12 câu mới. Điều đó chứng minh các yêu cầu này được phục vụ trong cấu hình/quota hiện tại, **không** chứng minh quota vô hạn hoặc xác định số quota còn lại. Không dùng API quản trị Google Cloud, không bật billing, không đổi gói hoặc hạn mức. Các lần gọi thử chỉ sử dụng quyền/quota dịch vụ đang có.

## Cấu hình và mã đã sửa

- `backend_nodejs/.env`: chỉ đổi `GEMINI_MODEL=gemini-3.5-flash-lite`, giữ nguyên API key và mọi dòng cấu hình khác. File vẫn được Git ignore, không chép key vào code/Flutter/log.
- `src/services/gemini-diagnostics.js`: default model chung, chuẩn hóa tên có/không tiền tố `models/`, lấy HTTP status/Google status/message có che bí mật; giới hạn trường diagnostics, che key/token/project ID và JSON lồng nhau.
- `src/services/ai-grounding.service.js`: dùng model đã chuẩn hóa, không theo redirect mang key sang host khác; giữ chẩn đoán lỗi Google nội bộ thay vì bỏ response lỗi. Contract `aiStatus` và tất cả quy tắc dữ liệu/giỏ hiện có giữ nguyên; không trả raw lỗi nhà cung cấp cho Flutter.
- `scripts/eval-ai-live.js`: hiện HTTP status, finishReason và chẩn đoán an toàn từng câu. Hỗ trợ `--model`, `--limit 1..12` để thử có kiểm soát mà không sửa cấu hình; vẫn dừng khi quota/key/model lỗi.
- `scripts/diagnose-gemini.js`: thêm lệnh khám phá model, so metadata v1/v1beta và một request text tối giản. Không in header, API key, raw body hoặc token.
- `scripts/test-gemini-diagnostics.js`: 7 nhóm kiểm thử redaction, lỗi 404, quota, non-JSON và chuẩn hóa model.
- `package.json`: giữ `eval:ai:live`, thêm alias `eval:ai`, `diagnose:ai`, `test:ai:diagnostics`.
- `.env.example`, `AI_CHATBOT.md`: đồng bộ default model và ghi rõ kết quả cũ chưa có key đã được cập nhật bằng lần kiểm tra này.
- `GEMINI_DIAGNOSIS.md`: báo cáo này.

Không sửa Dart, giao diện, database, dữ liệu sản phẩm, prompt/logic xếp hạng, xác nhận giỏ, tính tiền, kho hay báo cáo lợi nhuận.

## Kết quả Gemini thật sau sửa

```json
{
  "model": "gemini-3.5-flash-lite",
  "attempted": 12,
  "providerSucceeded": 12,
  "providerSuccessRate": 1,
  "modelSelectionAccuracy": 0.8333333333333334,
  "groundedFactAccuracy": 1
}
```

Tất cả 12 câu trả HTTP 200 và `finishReason: STOP`. Thời gian ghi nhận 716–1.535 ms, trung bình khoảng 1.018 ms/câu. Đây là mẫu thử nhỏ, không phải cam kết chất lượng/tốc độ cho mọi câu hoặc mọi thời điểm.

Chọn đúng tập ID theo rubric: **10/12 = 83,3%**, không đánh đồng với thành công API. Hai câu chưa đúng tập ID mô hình là “Tư vấn nguyên liệu nấu ăn” và “Chấm táo với sốt nào?”. Câu thứ hai vẫn được bộ kiểm soát/dự phòng trả sản phẩm sốt thật, nhưng không tính thành mô hình chọn đúng. Dữ kiện sản phẩm sau kiểm soát khớp danh mục giả trong 12/12 câu; không thử tạo đơn hay ghi giỏ thật.

Hồi quy: 7 nhóm diagnostics, 43 kiểm tra tư vấn/dữ liệu/lỗi, 11 nhóm giỏ, 24 nhóm tính tiền, 9 nhóm chuyển kho–kệ và 350 kiểm tra JWT qua 108 route/alias đều đạt. Không chạy lại test Flutter vì không sửa file Flutter.

Đã chép bản sửa vào dự án và restart backend. Kiểm tra qua API chatbot đang chạy với JWT trong bộ nhớ và một sản phẩm thật: HTTP 200, `aiStatus=ok`, giá/tồn khớp DB, `action=null`. Không ghi giỏ/đơn/thanh toán, không in JWT hoặc API key.

## Lệnh kiểm tra lại

Trong `backend_nodejs`:

```sh
npm run diagnose:ai
npm run eval:ai
npm run test:ai:diagnostics
npm run test:ai
```

Lệnh chẩn đoán/đánh giá thật dùng quota, không tự bật thanh toán. Nếu chỉ cần thử một câu hoặc một model khác đã thấy trong danh sách:

```sh
npm run eval:ai -- --model gemini-3.5-flash-lite --limit 1
npm run diagnose:ai -- --model gemini-2.5-flash
```

Sau khi đổi `.env`, restart backend để tiến trình đang chạy nhận model mới. Flutter không cần sửa hoặc cài thư viện mới.
