import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/order_line.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';

class ProductReviewScreen extends StatefulWidget {
  final Order order;
  final OrderLine item;

  const ProductReviewScreen({
    super.key,
    required this.order,
    required this.item,
  });

  @override
  State<ProductReviewScreen> createState() => _ProductReviewScreenState();
}

class _ProductReviewScreenState extends State<ProductReviewScreen> {
  final _commentController = TextEditingController();
  int _rating = 5;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung đánh giá')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ApiService.createReview(
        orderId: widget.order.id,
        productId: widget.item.productId,
        rating: _rating,
        comment: comment,
        customerId: DBService.currentUserId(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã gửi đánh giá')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không gửi được đánh giá: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đánh giá sản phẩm'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.item.productName,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(5, (index) {
              final value = index + 1;
              return IconButton(
                onPressed: () => setState(() => _rating = value),
                icon: Icon(
                  value <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(
              labelText: 'Nội dung đánh giá',
              border: OutlineInputBorder(),
            ),
            minLines: 4,
            maxLines: 6,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Gửi đánh giá'),
          ),
        ],
      ),
    );
  }
}
