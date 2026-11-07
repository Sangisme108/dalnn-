# Phan quyen JWT va kiem thu

Ban sua nay khong thay doi schema, du lieu, tai khoan hay mat khau database.

## Danh tinh va vai tro

- Danh tinh chi lay tu JWT `Authorization: Bearer <token>` da xac minh chu ky HS256, han su dung va tai khoan active trong database.
- `x-user-id` khong duoc dung de dang nhap, chon vai tro hay ghi nhan nguoi thao tac.
- Vai tro duoc doc lai tu database moi request, khong tin role trong JWT/body.
- Owner (`owner`, `admin`) duoc chuan hoa thanh `admin`; nhan vien (`staff`, `employee`) thanh `employee`; khach hang la `customer`.
- Token OTP/dat lai mat khau khong duoc dung lam access token.
- 401: thieu/sai/het han token, tai khoan bi khoa; 403: sai quyen; 503: khong xac minh duoc phien do database hoac thieu cau hinh webhook. Khong fallback sang header ID.

## Ma tran quyen

| Nhom API | Owner | Nhan vien | Khach hang | Chua dang nhap |
| --- | --- | --- | --- | --- |
| Danh sach/chi tiet san pham, danh muc, danh gia cong khai | Doc | Doc | Doc | Doc |
| Tao/sua/xoa san pham va danh muc, upload anh | Co | Co | Khong | Khong |
| Quet ma san pham ban | Co | Co | Co | Khong |
| Du lieu kho/gia von, nhap/xuat/kiem ke | Co | Co | Khong | Khong |
| Don hang, chi tiet va trang thai thanh toan | Tat ca | Tat ca de xu ly ban hang | Chi don cua minh | Khong |
| Tao hoa don tai quay, xac nhan/tu choi/cap nhat trang thai | Co | Co | Khong | Khong |
| Checkout online tu gio hang | Chi gio cua minh | Chi gio cua minh | Chi gio cua minh | Khong |
| Huy/xac nhan nhan don qua endpoint khach hang | Chi don cua minh | Chi don cua minh | Chi don cua minh | Khong |
| Danh sach nguoi dung | Tat ca | Khach hang va tai khoan cua minh | Chi tai khoan cua minh | Khong |
| Tao/sua/khoa tai khoan, doi vai tro | Co | Khong | Khong | Khong |
| Cap nhat ho so ca nhan | Moi tai khoan | Chi minh | Chi minh | Khong |
| Ca lam, lich thang va tong hop nhan vien | Tat ca | Chi minh | Khong | Khong |
| Sua lich ngay, xem tong quan lich, bao cao doanh thu/hieu suat | Co | Khong | Khong | Khong |
| Tra/cong diem tai quay | Co | Co | Khong | Khong |
| Quan tri voucher | Co | Khong | Khong | Khong |
| Voucher cua user | Tat ca | Chi minh | Chi minh | Khong |
| Gio hang | Chi gio cua minh | Chi gio cua minh | Chi gio cua minh | Khong |
| Chatbot/tieu thu quota AI | Co | Co | Co | Khong |

Actor nhap/xuat kho, tich diem, tao hoa don va sua lich khong lay tu ID do Flutter gui len. Staff khong duoc cham cong cho staff khac; Owner duoc quan ly ca cua nhan vien.

## Cau hinh JWT

Dat `JWT_SECRET` ngau nhien, rieng tu, trong `backend_nodejs/.env`. Khong dua secret vao Flutter hoac commit Git.

```sh
node -e "console.log(require('node:crypto').randomBytes(48).toString('hex'))"
```

Dien ket qua vao `JWT_SECRET=...`, khoi dong lai backend, dang xuat/dang nhap lai Flutter. Production se khong khoi dong khi thieu secret. Development thieu secret su dung khoa tam chi trong tien trinh; token mat hieu luc sau moi lan restart.

API `/api/test-db` hien chi Owner co JWT moi duoc truy cap. API `/` van la health check cong khai, khong doc database.

## Cau hinh SePay sau khi sua

Webhook khong the dung JWT nguoi dung vi caller la SePay. Backend xac thuc webhook bang khoa rieng; khong chap nhan mac dinh khi thieu khoa.

1. Tao mot khoa ngau nhien khac `JWT_SECRET`, khong gui khoa len chat hay Git.
2. Trong `backend_nodejs/.env`, dien `BANK_WEBHOOK_SECRET=<khoa_webhook>` (hoac `SEPAY_API_KEY`, khong can ca hai).
3. Tren SePay, sua webhook dang dung, chon chung thuc **API Key** va dat DUNG cung khoa. Khong nham voi API Token dung de goi API quan ly SePay.
4. Giu URL HTTPS hien tai tro toi `/api/webhook/sepay` hoac `/api/payments/sepay`. Header SePay gui la `Authorization: Apikey <khoa_webhook>`.
5. Restart backend, dung chuc nang test gui webhook cua SePay va kiem tra log ket qua. Chua cau hinh khoa: HTTP 503; sai khoa: HTTP 401. Dung khoa moi duoc xu ly doi soat so tien/noi dung/tai khoan va chong trung giao dich nhu truoc.
6. Chi thu chuyen khoan that sau khi test chung thuc thanh cong. Neu da chuyen tien trong luc chua cau hinh, kiem tra lich su webhook va gui lai giao dich tu SePay; khong chuyen tien lan nua de thu.

Tai lieu chinh thuc: https://developer.sepay.vn/vi/sepay-webhooks/xac-thuc

VNPay return/IPN van cong khai cho cong thanh toan goi vao, nhung phai qua xac minh chu ky va ma merchant VNPay. `VNP_TMN_CODE` va `VNP_HASH_SECRET` bat buoc dung cau hinh rieng cua ban, ke ca sandbox; khong con khoa demo mac dinh. API tao URL thanh toan can JWT va quyen tren don. API xac nhan chuyen khoan thu cong da bi go, khong duoc khoi phuc de tranh bo qua doi soat.

## Tuong thich Flutter

- Cac API cu, upload anh va voucher da gui JWT. Cac tham so userId/employeeId cu van duoc giu trong chu ky ham de tranh pha vo cac man hinh, nhung khong con duoc dung lam chung thuc.
- Truy van don khach hang duoc loc o backend, ke ca endpoint danh sach tong, lich su, ma DH, chi tiet va payment-status.
- Dong bo kho chi chay cho Owner/nhan vien. Sau khi dang nhap, phien va vai tro duoc doi chieu voi `/api/auth/profile`.
- Logout/doi tai khoan xoa cache rieng cua user/don/gio/kho/ca lam tren thiet bi; khong xoa database. San pham cong khai va anh van duoc giu.
- Token cu khong hop le/het han phai dang nhap lai. Khong tu retry giao dich bang danh tinh khac.

## Kiem thu

```sh
cd backend_nodejs
npm run test:auth
node scripts/test-pending-orders.js
node scripts/test-order-cancel-errors.js
node scripts/test-bank-transfer-routes.js
node scripts/test-ai-chat-validation.js
node scripts/test-ai-faq.js
node scripts/test-vnpay-sign.js
```

Tu thu muc goc:

```sh
flutter test --no-pub
flutter analyze --no-pub
```

Test authorization dung Express/JWT that voi database gia lap; khong tao/sua/xoa du lieu that, khong goi dich vu thanh toan/AI/SMS. Bao phu alias route, token het han/sai chu ky/sai purpose/thieu exp, khoa tai khoan, gia mao header/role/actor, cross-customer IDOR, vai tro Owner/staff aliases, tu choi webhook thieu/sai khoa va loi database khi xac thuc.

Kiem tra lai tren thiet bi: Owner quan ly nhan vien/voucher/bao cao; staff ban hang/nhap-xuat-kho/cham cong chinh minh/xac nhan online; khach dang ky/dang nhap/gio/voucher/checkout/huy/nhan hang/danh gia; doi tai khoan Owner sang khach; token het han; upload anh; SePay sau khi cau hinh khoa; VNPay sandbox.

Khong co kiem thu tu dong nao chung minh duoc giao dich ngan hang that thanh cong. Phan nay can test end-to-end sau khi cau hinh SePay.

## File thay doi trong dot sua JWT

- `src/config/jwt.js`: khoa JWT rieng, fail closed khi production thieu khoa.
- `src/middlewares/auth.middleware.js`: JWT bat buoc, chuan hoa vai tro, helper quyen so huu, khong fallback header.
- `src/services/auth.service.js`: access/reset token dung chung cau hinh khoa, tach purpose va gioi han thuat toan.
- `src/services/vnpay.service.js`, `scripts/test-vnpay-sign.js`: bo khoa demo mac dinh, kiem tra chu ky/merchant/du lieu bi sua, tu choi khi thieu khoa.
- `src/server.js`: bao ve API chan doan database.
- `src/routes/product.routes.js`, `category.routes.js`, `inventory.routes.js`, `upload.routes.js`: quyen danh muc/san pham/kho/upload va audit actor.
- `src/routes/order.routes.js`, `myOrder.routes.js`, `payment.routes.js`, `cart.routes.js`: quyen don/gio/checkout/payment-status theo JWT; xac thuc webhook rieng.
- `src/routes/user.routes.js`, `workShift.routes.js`, `employeeSchedule.routes.js`: quyen tai khoan/ca/lich va nguoi cap nhat lich.
- `src/routes/report.routes.js`, `performance.routes.js`, `point.routes.js`, `voucher.routes.js`, `ai.routes.js`: bao ve bao cao, diem, voucher, quota AI.
- `../lib/services/api_service.dart`: gui JWT cho API cu va multipart, bo header gia danh, lay phien tu backend.
- `../lib/services/db_service.dart`: dong bo theo vai tro va xoa cache rieng khi logout/doi tai khoan/het phien.
- `../lib/services/voucher_service.dart`: gui JWT, bo header ID.
- `scripts/test-authorization.js`: ma tran HTTP dung middleware that va database gia lap.
- `scripts/test-ai-chat-validation.js`, `test-ai-faq.js`, `test-order-cancel-errors.js`, `test-pending-orders.js`: cap nhat mock router cho middleware chung, giu nguyen kiem thu nghiep vu.
- `../test/api_authorization_test.dart`: JWT headers, loi 401, cache, doi tai khoan va phien het han.
- `package.json`, `.env.example`, `../README.md`, `AUTHORIZATION.md`: lenh kiem thu va huong dan cau hinh.

File `.env` local chi duoc bo sung `JWT_SECRET` ngau nhien neu chua co; khong thay cau hinh database, khong dua khoa that vao Git. Khoa webhook SePay do chu du an cau hinh sau.
