const express = require('express');
const pool = require('../config/db');
const { requireAuth } = require('../middlewares/auth.middleware');

const router = express.Router();

async function getOrCreateCart(connection, userId) {
  const [existing] = await connection.execute(
    'SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1',
    [userId]
  );
  if (existing.length > 0) return existing[0].cart_id;
  const [created] = await connection.execute('INSERT INTO carts (user_id) VALUES (?)', [userId]);
  return created.insertId;
}

function currentUserId(req) {
  return Number(req.user?.id || req.user?.user_id);
}

async function fetchCartPayload(userId) {
  const [carts] = await pool.execute(
    'SELECT cart_id FROM carts WHERE user_id = ? ORDER BY cart_id DESC LIMIT 1',
    [userId]
  );
  if (carts.length === 0) {
    return { user_id: userId, items: [] };
  }

  const [items] = await pool.execute(
    `SELECT ci.cart_item_id, ci.product_id, ci.quantity, p.product_name, p.barcode, p.price, p.image_url, p.stock
     FROM cart_items ci
     JOIN products p ON p.product_id = ci.product_id
     WHERE ci.cart_id = ?
     ORDER BY ci.cart_item_id`,
    [carts[0].cart_id]
  );
  return { user_id: userId, cart_id: carts[0].cart_id, items };
}

async function replaceCartItems(connection, userId, items) {
  const cartId = await getOrCreateCart(connection, userId);
  await connection.execute('DELETE FROM cart_items WHERE cart_id = ?', [cartId]);
  for (const item of items) {
    if (Number(item.quantity) > 0) {
      await connection.execute(
        'INSERT INTO cart_items (cart_id, product_id, quantity) VALUES (?, ?, ?)',
        [cartId, Number(item.product_id), Number(item.quantity)]
      );
    }
  }
  return cartId;
}

router.get('/', requireAuth, async (req, res) => {
  try {
    const userId = currentUserId(req);
    const data = await fetchCartPayload(userId);
    res.json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lá»—i láº¥y giá» hÃ ng', error: error.message });
  }
});

router.post('/add', requireAuth, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const userId = currentUserId(req);
    const productId = Number(req.body.product_id || req.body.productId);
    const quantity = Number(req.body.quantity || 1);

    if (!productId || quantity <= 0) {
      return res.status(400).json({ success: false, message: 'product_id vÃ  quantity khÃ´ng há»£p lá»‡' });
    }

    await connection.beginTransaction();
    const cartId = await getOrCreateCart(connection, userId);
    await connection.execute(
      `INSERT INTO cart_items (cart_id, product_id, quantity)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE quantity = quantity + VALUES(quantity)`,
      [cartId, productId, quantity]
    );
    await connection.commit();

    const data = await fetchCartPayload(userId);
    res.status(201).json({ success: true, message: 'ÄÃ£ thÃªm vÃ o giá» hÃ ng', data });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, message: 'Lá»—i thÃªm giá» hÃ ng', error: error.message });
  } finally {
    connection.release();
  }
});

router.put('/update', requireAuth, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const userId = currentUserId(req);
    const { items } = req.body;
    if (!Array.isArray(items)) {
      return res.status(400).json({ success: false, message: 'items pháº£i lÃ  array' });
    }

    await connection.beginTransaction();
    const cartId = await replaceCartItems(connection, userId, items);
    await connection.commit();
    res.json({ success: true, message: 'ÄÃ£ cáº­p nháº­t giá» hÃ ng', data: { cart_id: cartId } });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, message: 'Lá»—i cáº­p nháº­t giá» hÃ ng', error: error.message });
  } finally {
    connection.release();
  }
});

router.delete('/remove', requireAuth, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const userId = currentUserId(req);
    const productId = Number(req.body.product_id || req.body.productId);
    if (!productId) {
      return res.status(400).json({ success: false, message: 'product_id khÃ´ng há»£p lá»‡' });
    }

    await connection.beginTransaction();
    const cartId = await getOrCreateCart(connection, userId);
    await connection.execute('DELETE FROM cart_items WHERE cart_id = ? AND product_id = ?', [cartId, productId]);
    await connection.commit();

    const data = await fetchCartPayload(userId);
    res.json({ success: true, message: 'ÄÃ£ xÃ³a sáº£n pháº©m khá»i giá» hÃ ng', data });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, message: 'Lá»—i xÃ³a sáº£n pháº©m khá»i giá» hÃ ng', error: error.message });
  } finally {
    connection.release();
  }
});

// Backward-compatible routes for current Flutter screens.
router.get('/:userId', requireAuth, async (req, res) => {
  try {
    const userId = currentUserId(req);
    const data = await fetchCartPayload(userId);
    res.json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Lá»—i láº¥y giá» hÃ ng', error: error.message });
  }
});

router.put('/:userId', requireAuth, async (req, res) => {
  const connection = await pool.getConnection();
  try {
    const userId = currentUserId(req);
    const { items } = req.body;
    if (!Array.isArray(items)) {
      return res.status(400).json({ success: false, message: 'items pháº£i lÃ  array' });
    }

    await connection.beginTransaction();
    const cartId = await replaceCartItems(connection, userId, items);
    await connection.commit();
    res.json({ success: true, message: 'ÄÃ£ lÆ°u giá» hÃ ng', data: { cart_id: cartId } });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, message: 'Lá»—i lÆ°u giá» hÃ ng', error: error.message });
  } finally {
    connection.release();
  }
});

module.exports = router;
