# Sua P1 tinh tien don hang

## Loi da xac nhan truoc khi sua

- POS doc `item.price` tu Flutter, nhan `discount_amount` thay vi tu tinh voucher.
- POS khong kiem tra du gia tri don toi thieu/muc giam toi da; voucher co gioi han 0 bi coi nhu khong gioi han.
- Kiem tra tung dong san pham truoc khi tru ton: nhieu dong cung ID co the vuot ton tong cong.
- So luong/diem khong kiem tra du so nguyen, NaN/Infinity/gia tri am; phep tinh tien dung so thuc truc tiep.
- Don pending co the dung lai diem cua nhau vi chi tru diem khi nhan tien.
- API cong diem cu tin so tien gui len va cho cong diem khong gan don.
- Flutter dung tong tu gio local de tao QR/in ket qua, tim don sau luu bang transaction ID do client tao.
- Callback thanh toan chua khoa don truoc khi kiem tra paid; callback that bai co the ghi de paid neu xu ly dong thoi.

## Quy tac sau khi sua

1. Tong hang = tong (gia DB tai luc khoa san pham x so luong). Chi nhan ID/so luong, khong tin gia/subtotal/tong/diem thuong cua client.
2. Gop ID trung, sap ID tang dan va `SELECT ... FOR UPDATE`; tru ton co dieu kien `stock >= quantity` va kiem tra affectedRows.
3. Tien tinh bang so nguyen don vi 1/100 VND, toi da 99.999.999,99 VND. Phan tram duoc lam tron mot lan den 2 chu so thap phan. Chi chap nhan nhieu nhat 2 chu so thap phan (ngoai sai so IEEE-754 rat nho cua so JSON).
4. Voucher doc trong transaction, khoa dong, kiem tra active, ngay het han, gioi han, don toi thieu va muc giam toi da cho ca fixed/percent. `expiry_date` co kieu DATE: con hieu luc het ngay theo calendar cua database, dong nhat voi danh sach voucher.
5. `usage_limit = NULL` la khong gioi han; 0 la het luot. Cap nhat bo dem co dieu kien. `user_vouchers` ghi dung khach cua don, khong dung ID nhan vien/user_id gia tu body.
6. Schema hien tai chi co gioi han su dung TOAN BO voucher. `user_vouchers.used_count` la theo doi, khong tu y ap dat gioi han moi 1 lan/khach. Luu/claim voucher khong tieu thu luot; tao don moi tieu thu luot nhu luong cu. Huy don khong tu hoan luot voucher.
7. `discount_amount` khi co voucher chi la preview cu, backend bo qua va tinh lai. Khong co voucher, so tien nay la giam thu cong: chi Owner duoc phep. Truong ro rang moi `manual_discount_amount` cung chi Owner, khong vuot so tien sau voucher, co ghi chu audit. Nhan vien/khach khong duoc tu giam gia.
8. Tong phai tra = tong hang - voucher - giam Owner hop le - giam diem. Diem doi theo quy tac cu (100 diem = 10.000 VND), duoc kiem tra so nguyen/boi so/so du/gioi han tien.
9. Diem duoc giu ngay trong transaction tao don (ledger `redeem`). Khong the dung cung diem cho nhieu don cho chuyen khoan. Diem thuong chi cong khi paid, theo final_amount va hang diem nhu cong thuc cu; ledger/order lock ngan cong/tru lap.
10. Huy/tu choi don CHUA thanh toan hoan ton va diem giu mot lan (ledger `refund_redeem`); khong mo lai don da ket thuc. Don da thu tien tra 409, can doi soat/hoan tien rieng, khong am tham tra hang/diem trong khi tien ngan hang chua duoc hoan.
11. Callback den muon cho don da huy/tu choi khong mo lai don. Callback trung khong thuong diem hay tao ban ghi paid lap; callback failed khong ghi de paid.
12. POS tien mat duoc paid khi nhan vien xac nhan; cac cach chuyen khoan/the/vi/VNPay van pending cho toi khi co xac nhan tu he thong. Truong hop so tien bang 0 thi backend tu xac nhan, khong yeu cau chuyen khoan 0 VND. Ewallet demo khong con tu danh dau paid.
13. Flutter gui `expected_final_amount` cho tien mat de so sanh voi so tien da xac nhan. Neu gia/voucher thay doi, backend tra 409 va rollback, yeu cau cap nhat gio/xac nhan lai. QR chuyen khoan va hoa don dung final_amount/ma don backend tra ve.

Tat ca ghi don, hang, payment, voucher va diem nam trong cung transaction. Response duoc doc bang chinh connection truoc commit, tranh loi doc sau commit lam client hieu nham don chua tao. Loi deadlock/lock timeout khong tu retry giao dich; client can kiem tra truoc khi gui lai.

## Tuong thich va schema

- Khong chay migration, khong xoa hay backfill du lieu.
- Da doc metadata instance hien tai: `orders.points_used`/`points_earned` la INT, `points_discount` la DECIMAL(12,2), `loyalty_transactions.type` la VARCHAR(20); luu duoc `refund_redeem`.
- Neu may khac chua co cot diem, API tu choi dung diem va bao can kiem tra migration hien co, khong tu tao cot.
- JWT/role/ownership van giu nguyen; POS chi cho Owner/nhan vien, online lay gio theo JWT. Gia san pham chi thay doi qua API catalog da phan quyen, khong qua POST order.
- POS `/api/orders` tao hoa don offline. Online di qua `/api/orders/checkout` nhu Flutter hien tai; body customer/items/totals khong thay duoc chu gio hoac gia online.
- `POST /api/points/add` duoc giu nhung bat buoc ma don paid va dung khach; bo qua amount/points do client tu gui. Endpoint nay khong con la duong cong diem khong can hoa don.
- Bo cuc/man hinh khong doi; chi bo sung vat lieu Material trong khoi cu de SwitchListTile khong bi assertion khi kiem thu, khong doi mau/kich thuoc.
- Don cu giu nguyen. Don pending duoc tao truoc ban sua chua giu diem ngay tu dau; can doi soat neu da dung diem trung. Khong tu sua lich su kinh doanh.
- Cau hinh JWT/SePay/VNPay tu dot sua truoc van ap dung, khong thay secret hay thong tin tai khoan ngan hang trong dot nay.

## File thay doi

- `src/services/order-billing.service.js`: tinh tien/gia/so luong/voucher/quyen giam thu cong/ton kho.
- `src/routes/order.routes.js`: dung chung billing cho POS/online, transaction, dong bo huy/tu choi, tra don backend.
- `src/controllers/voucher.controller.js`: preview tu gia DB, ngay het han va kiem tra cau hinh voucher.
- `src/services/loyalty.service.js`: giu/hoan diem, kiem tra diem, reward idempotent.
- `src/routes/point.routes.js`: cong diem dua vao hoa don that, khong dua vao amount client.
- `src/services/order-payment.service.js`, `src/routes/payment.routes.js`: khoa callback, khong paid don da huy, xu ly ket qua that bai.
- `../lib/services/api_service.dart`: expected_final_amount; `db_service.dart`: tra ve don da luu; `voucher_service.dart`: truyen items cho preview.
- `../lib/screens/payment_screen.dart`: QR/hoa don dung don server, khong fallback don client.
- `../lib/screens/customer_online_checkout_screen.dart`: bo qua cong thanh toan khi so tien backend bang 0 va da paid.
- `../lib/models/order.dart`: doc so du diem hien tai backend tra ve de hien thi ket qua; day la gia tri runtime, khong doi Hive adapter hay schema database.
- `../lib/screens/apply_voucher_screen.dart`, `../lib/widgets/voucher_input_widget.dart`: them input items tuy chon cho preview ma khong doi giao dien.
- `scripts/test-order-billing.js`, `scripts/helpers/billing-fixture.js`: kiem thu nghiep vu/rollback/dong thoi voi database gia lap va khoa dong FIFO.
- `../test/payment_authoritative_amount_test.dart`: kiem thu QR va man thanh cong su dung so tien/ma don backend.
- `package.json`, `BILLING.md`: lenh kiem thu va ban giao.

## Kiem thu va gioi han

```sh
cd backend_nodejs
npm run test:billing
npm run test:auth
```

Tu thu muc goc: `flutter test --no-pub`, `flutter analyze --no-pub`.

Billing test goi route/service that tren fake DB co transaction/undo log/khoa dong; khong goi bank/AI/database that. Test chung minh luong ma va cac cau SQL khoa/co dieu kien, khong thay the stress test tren MySQL/TiDB that.

Kiem tra thu cong truoc khi demo:

1. POS tien mat, voucher, dung/khong dung diem: so tien dialog, don, payment, bien lai va so du diem phai khop.
2. POS QR sau khi gia DB thay doi: QR lay gia moi cua don; khong tu gui lai lenh tao don khi mat mang.
3. Gia tien mat thay doi sau khi gio duoc hien thi: 409, khong tao don/tru ton/tieu thu voucher/diem.
4. Checkout online giao hang/nhan tai quay voi voucher; bank/VNPay pending den khi callback that hop le. Don 0 VND khong mo QR 0.
5. Hai thiet bi tranh san pham cuoi, luot voucher cuoi va cung so du diem tren MySQL/TiDB that voi du lieu demo rieng; khong dung hang/so du dang kinh doanh de stress test.
6. Huy/tu choi pending, lap lai thao tac, callback den muon va paid-cancel can doi soat; khong thu chuyen tien that khi webhook chua cau hinh.
7. Dang nhap Owner/nhan vien/khach; khach khong tao don POS/tu giam gia, khong xem don nguoi khac; thu JWT het han.

Luot voucher khong tu hoan khi huy, chua co chinh sach het han tu dong cho don pending/diem giu, va chua co quy trinh hoan tien ngan hang tu dong. Day la cac quy tac can thong nhat truoc khi van hanh that, khong duoc khac phuc bang nut xac nhan thanh toan thu cong.
