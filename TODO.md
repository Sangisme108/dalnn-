# TODO - Sửa lỗi category_id NULL khi release inventory lên kệ

- [ ] Bước 1: Run query DB để cập nhật `inventory_items.category_id` theo `products.category_id` (JOIN theo `barcode`).
- [ ] Bước 2: Sửa `database.sql` phần seed `inventory_items` để chèn `category_id` ngay từ đầu (tránh NULL vĩnh viễn).
- [ ] Bước 3: (Optional) Rà soát lại `lib/screens/import_inventory_screen.dart` và flow tạo inventory item để đảm bảo payload gửi `categoryId`/`category_id` đúng.
- [ ] Bước 4: Test lại màn "Thêm sản phẩm từ kho lên kệ" xem không còn lỗi "chưa có danh mục".
